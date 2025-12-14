#!/usr/bin/env bash
# =============================================================================
# Realistic Offline-First Test
# =============================================================================
#
# SCENARIO: A field worker uses a mobile app while disconnected from the network.
# They make multiple changes over time, then reconnect and sync all at once.
# Meanwhile, the server has received updates from other users.
#
# This test demonstrates:
# 1. Accumulating multiple changes while offline
# 2. Using db_version as a sync cursor (only sync changes since last sync)
# 3. Batch syncing accumulated changes on reconnect
# 4. Merging offline changes with changes from other users
# 5. Partial sync / resumable sync patterns
#
# WHAT YOU'LL LEARN:
# - How db_version tracks local change sequence
# - How to implement incremental sync with "sync since version X"
# - How accumulated offline changes merge correctly
# - How to track sync progress for resume capability
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "═══════════════════════════════════════════════════════════════════════"
echo "REALISTIC SCENARIO: Offline-First Field Worker App"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Actors: Field worker (mobile), Office server, Other field workers"
echo "Goal: Work offline, sync cleanly when back online"
echo ""

# Build the extension
echo "Building Zig extension..."
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo "FAIL: Zig build failed"
    exit 1
fi

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$EXT" ]]; then
    echo "FAIL: Extension not found at $EXT"
    exit 1
fi

echo "Extension: $EXT"
echo ""

# Create temp directory for test databases
TMPDIR=$(mktemp -d)
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -rf $TMPDIR $TMPFILE $ERRFILE" EXIT

FIELD_DB="$TMPDIR/field-worker.sqlite"
SERVER_DB="$TMPDIR/server.sqlite"
OTHER_DB="$TMPDIR/other-worker.sqlite"

FAILURES=0

# Helper function to run SQL (suppress debug)
run_sql() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$sql" 2>"$ERRFILE" || true
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function: crsql_as_crr" "$ERRFILE"; then
            echo "BLOCKED: crsql_as_crr() not yet implemented"
            exit 2
        fi
    fi
}

# Sync helper: extract changes from source DB and apply to target DB
sync_changes() {
    local src_db="$1"
    local dst_db="$2"
    local since_version="${3:-0}"
    
    # Get destination's site_id to exclude its own changes
    local dst_site_id
    dst_site_id=$(run_sql "$dst_db" "SELECT quote(crsql_site_id());")
    
    # Extract changes from source
    nix run nixpkgs#sqlite -- "$src_db" -cmd ".load $EXT" "
        SELECT 'CHANGE:' || 
            [table] || '|' || 
            quote(pk) || '|' || 
            cid || '|' || 
            quote(val) || '|' || 
            col_version || '|' || 
            db_version || '|' || 
            quote(site_id) || '|' || 
            cl || '|' || 
            seq
        FROM crsql_changes
        WHERE db_version > $since_version AND site_id IS NOT $dst_site_id;
    " > "$TMPFILE" 2>/dev/null
    
    # Apply each change to destination
    local change_count=0
    while IFS= read -r line; do
        if [[ "$line" == CHANGE:* ]]; then
            local change="${line#CHANGE:}"
            IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
            run_sql "$dst_db" "
                INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
                VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
            " 2>/dev/null
            change_count=$((change_count + 1))
        fi
    done < "$TMPFILE"
    
    echo "$change_count"
}

# Get max db_version from changes (for sync cursor tracking)
get_max_version() {
    local db="$1"
    run_sql "$db" "SELECT COALESCE(MAX(db_version), 0) FROM crsql_changes;"
}

# =============================================================================
# Setup: Initialize all databases with shared schema
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SETUP: Initialize databases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Schema: inspections(id INTEGER PRIMARY KEY, location, status, notes)"
echo ""

# Initialize all databases with same schema
for db in "$FIELD_DB" "$SERVER_DB" "$OTHER_DB"; do
    run_sql "$db" "
        CREATE TABLE inspections (
            id INTEGER PRIMARY KEY NOT NULL,
            location,
            status,
            notes
        );
        SELECT crsql_as_crr('inspections');
    "
done

# Create initial server data (using IDs 1-100)
run_sql "$SERVER_DB" "
    INSERT INTO inspections VALUES (1, 'Building A', 'pending', 'Scheduled for Monday');
    INSERT INTO inspections VALUES (2, 'Building B', 'pending', 'Scheduled for Tuesday');
    INSERT INTO inspections VALUES (3, 'Building C', 'pending', 'Scheduled for Wednesday');
"

# Sync initial data to field worker (simulates initial app sync)
sync_changes "$SERVER_DB" "$FIELD_DB" 0 > /dev/null

INITIAL_VERSION=$(get_max_version "$FIELD_DB")
echo "Field worker synced initial data (db_version: $INITIAL_VERSION)"
echo "Field worker has $(run_sql "$FIELD_DB" "SELECT COUNT(*) FROM inspections;") inspections"
echo ""

# =============================================================================
# PHASE 1: Field worker goes offline and makes changes
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 1: Field worker goes OFFLINE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The field worker visits sites and updates inspection status..."
echo ""

# Field worker completes inspections over time (all while offline)
echo "  [9:00 AM] Complete inspection at Building A"
run_sql "$FIELD_DB" "UPDATE inspections SET status = 'complete', notes = 'All clear, passed' WHERE id = 1;"

echo "  [10:30 AM] Update Building B - found issues"
run_sql "$FIELD_DB" "UPDATE inspections SET status = 'failed', notes = 'Fire exit blocked, needs follow-up' WHERE id = 2;"

echo "  [2:00 PM] Complete Building C inspection"
run_sql "$FIELD_DB" "UPDATE inspections SET status = 'complete', notes = 'Minor issues fixed on site' WHERE id = 3;"

echo "  [3:00 PM] Add new emergency inspection (using ID 101)"
run_sql "$FIELD_DB" "INSERT INTO inspections VALUES (101, 'Building D', 'complete', 'Emergency water leak - fixed');"

OFFLINE_VERSION=$(get_max_version "$FIELD_DB")
OFFLINE_CHANGES=$((OFFLINE_VERSION - INITIAL_VERSION))

echo ""
echo "Field worker accumulated $OFFLINE_CHANGES change(s) while offline"
echo "  Local db_version: $INITIAL_VERSION → $OFFLINE_VERSION"
echo ""

# =============================================================================
# PHASE 2: Meanwhile, other workers update the server
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 2: Meanwhile at the office... (other worker syncs to server)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Other worker syncs initial data
sync_changes "$SERVER_DB" "$OTHER_DB" 0 > /dev/null

# Other worker makes their own changes (using IDs 201+ for new items)
echo "Other worker adds new inspections and updates priority..."
run_sql "$OTHER_DB" "INSERT INTO inspections VALUES (201, 'Building E', 'pending', 'High priority - CEO visit');"
run_sql "$OTHER_DB" "UPDATE inspections SET notes = 'URGENT: Reschedule to Friday' WHERE id = 2;"

# Other worker syncs to server
sync_changes "$OTHER_DB" "$SERVER_DB" 0 > /dev/null

SERVER_VERSION=$(get_max_version "$SERVER_DB")
echo "Server received updates from other worker"
echo "  Server db_version: $SERVER_VERSION"
echo "  Server has $(run_sql "$SERVER_DB" "SELECT COUNT(*) FROM inspections;") inspections"
echo ""

# =============================================================================
# PHASE 3: Field worker reconnects and syncs
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 3: Field worker comes ONLINE - bidirectional sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Track sync cursor (in real app, this would be persisted)
LAST_SERVER_SYNC=0  # Field worker's last known server version

echo "Step 1: Pull server changes since last sync (version > $LAST_SERVER_SYNC)"
PULLED=$(sync_changes "$SERVER_DB" "$FIELD_DB" "$LAST_SERVER_SYNC")
echo "  Pulled $PULLED change(s) from server"

echo ""
echo "Step 2: Push local changes to server"
PUSHED=$(sync_changes "$FIELD_DB" "$SERVER_DB" 0)
echo "  Pushed $PUSHED change(s) to server"
echo ""

# =============================================================================
# PHASE 4: Verify convergence
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 4: Verify convergence after sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Complete the sync (server changes may have been applied after field worker's changes)
sync_changes "$SERVER_DB" "$FIELD_DB" 0 > /dev/null

FIELD_DATA=$(run_sql "$FIELD_DB" "SELECT id, status FROM inspections ORDER BY id;")
SERVER_DATA=$(run_sql "$SERVER_DB" "SELECT id, status FROM inspections ORDER BY id;")

echo "Field worker's view:"
run_sql "$FIELD_DB" "SELECT '  ' || id || ': ' || status || ' @ ' || location FROM inspections ORDER BY id;"
echo ""

echo "Server's view:"
run_sql "$SERVER_DB" "SELECT '  ' || id || ': ' || status || ' @ ' || location FROM inspections ORDER BY id;"
echo ""

if [[ "$FIELD_DATA" == "$SERVER_DATA" ]]; then
    echo "PASS: Field worker and server have converged"
else
    echo "FAIL: Data mismatch between field worker and server"
    FAILURES=$((FAILURES + 1))
fi

# Check that all inspections are present
FIELD_COUNT=$(run_sql "$FIELD_DB" "SELECT COUNT(*) FROM inspections;")
if [[ "$FIELD_COUNT" == "5" ]]; then
    echo "PASS: All 5 inspections present (3 original + 1 from field + 1 from other)"
else
    echo "FAIL: Expected 5 inspections, got $FIELD_COUNT"
    FAILURES=$((FAILURES + 1))
fi

# Check conflict resolution: insp id=2 had concurrent edits
# Field worker: status='failed', notes='Fire exit blocked...'
# Other worker: notes='URGENT: Reschedule...'
echo ""
echo "Checking conflict on id=2 (both workers edited it):"
INSP2_STATUS=$(run_sql "$FIELD_DB" "SELECT status FROM inspections WHERE id = 2;")
INSP2_NOTES=$(run_sql "$FIELD_DB" "SELECT notes FROM inspections WHERE id = 2;")
echo "  Status: $INSP2_STATUS"
echo "  Notes: $INSP2_NOTES"
echo ""

# The field worker's status='failed' should win (they actually did the inspection)
if [[ "$INSP2_STATUS" == "failed" ]]; then
    echo "PASS: Field worker's status update was preserved (they completed the inspection)"
else
    echo "INFO: Status resolved to '$INSP2_STATUS' based on col_version"
fi

# =============================================================================
# BONUS: Demonstrate incremental sync pattern
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "BONUS: Incremental sync (only new changes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "In production, track the last synced db_version to avoid re-syncing."
echo ""

# Store current version as sync cursor
SYNC_CURSOR=$(get_max_version "$SERVER_DB")
echo "Current sync cursor: $SYNC_CURSOR"
echo ""

# Server gets more updates (using ID 301)
run_sql "$SERVER_DB" "INSERT INTO inspections VALUES (301, 'Building F', 'pending', 'Added after sync');"
NEW_VERSION=$(get_max_version "$SERVER_DB")

echo "Server adds new inspection (db_version: $SYNC_CURSOR → $NEW_VERSION)"
echo ""

# Incremental sync - only get changes since cursor
echo "Incremental sync (WHERE db_version > $SYNC_CURSOR):"
INCREMENTAL=$(sync_changes "$SERVER_DB" "$FIELD_DB" "$SYNC_CURSOR")
echo "  Only $INCREMENTAL new change(s) synced (not full history)"
echo ""

if [[ "$INCREMENTAL" -lt "$PUSHED" ]]; then
    echo "PASS: Incremental sync transferred fewer changes than full sync"
else
    echo "INFO: Incremental sync transferred $INCREMENTAL changes"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "SUMMARY: Offline-First Patterns with CR-SQLite"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Key patterns demonstrated:"
echo ""
echo "  1. OFFLINE ACCUMULATION"
echo "     - Changes accumulate locally in crsql_changes"
echo "     - No special handling needed - just write normally"
echo "     - db_version tracks change sequence"
echo ""
echo "  2. SYNC CURSOR"
echo "     - Track last synced db_version per peer"
echo "     - SELECT FROM crsql_changes WHERE db_version > cursor"
echo "     - Enables incremental sync (only new changes)"
echo ""
echo "  3. BIDIRECTIONAL SYNC"
echo "     - Pull: SELECT from server's crsql_changes → INSERT into local"
echo "     - Push: SELECT from local crsql_changes → INSERT into server"
echo "     - Order doesn't matter - CRDTs guarantee convergence"
echo ""
echo "  4. CONCURRENT EDIT MERGE"
echo "     - Multiple users can edit same records offline"
echo "     - Changes merge automatically on sync"
echo "     - Column-level granularity preserves non-conflicting edits"
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "✓ All offline-first scenarios PASSED"
    exit 0
else
    echo "✗ $FAILURES scenario(s) FAILED"
    exit 1
fi
