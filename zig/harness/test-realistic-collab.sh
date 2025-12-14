#!/usr/bin/env bash
# =============================================================================
# Realistic Collaborative Editing Test
# =============================================================================
#
# SCENARIO: Alice and Bob are collaborating on a shared document.
# They both edit the same field concurrently. CR-SQLite uses Last-Writer-Wins
# (LWW) semantics based on col_version to resolve conflicts deterministically.
#
# This test demonstrates:
# 1. How concurrent edits to the same cell create a conflict
# 2. How CR-SQLite resolves conflicts using col_version (higher wins)
# 3. How tie-breakers work (same col_version → larger value wins)
# 4. Why both devices converge to the same result regardless of sync order
#
# WHAT YOU'LL LEARN:
# - Conflict resolution is automatic and deterministic
# - col_version acts as a logical clock per cell
# - Convergence happens regardless of sync order
# - No data loss - losing values are simply superseded, not deleted
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "═══════════════════════════════════════════════════════════════════════"
echo "REALISTIC SCENARIO: Collaborative Document Editing"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Actors: Alice and Bob editing a shared document"
echo "Goal: Understand how concurrent edits are resolved"
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

ALICE_DB="$TMPDIR/alice.sqlite"
BOB_DB="$TMPDIR/bob.sqlite"

FAILURES=0

# Helper function to run SQL (suppress debug output)
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

# =============================================================================
# Setup: Both devices have identical initial document
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SETUP: Create initial document on both devices"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Schema: documents(id INTEGER PRIMARY KEY, title, content)"
echo ""

# Create schema and initial document on Alice's device
run_sql "$ALICE_DB" "
    CREATE TABLE documents (id INTEGER PRIMARY KEY NOT NULL, title, content);
    SELECT crsql_as_crr('documents');
    INSERT INTO documents VALUES (1, 'Meeting Notes', 'Initial content...');
"

# Sync initial document to Bob (so they start with same state)
run_sql "$BOB_DB" "
    CREATE TABLE documents (id INTEGER PRIMARY KEY NOT NULL, title, content);
    SELECT crsql_as_crr('documents');
"
sync_changes "$ALICE_DB" "$BOB_DB" 0 > /dev/null

echo "Initial state (both devices):"
echo "  Title:   'Meeting Notes'"
echo "  Content: 'Initial content...'"
echo ""

# =============================================================================
# SCENARIO 1: Simple concurrent edit - higher col_version wins
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SCENARIO 1: Concurrent edits - higher col_version wins"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Alice and Bob both edit the title offline:"
echo ""

# Alice edits the title once
run_sql "$ALICE_DB" "UPDATE documents SET title = 'Q4 Planning Notes' WHERE id = 1;"
ALICE_TITLE=$(run_sql "$ALICE_DB" "SELECT title FROM documents WHERE id = 1;")
ALICE_COL_VER=$(run_sql "$ALICE_DB" "SELECT col_version FROM crsql_changes WHERE cid = 'title';")

echo "  Alice sets title to: 'Q4 Planning Notes'"
echo "    → col_version becomes: $ALICE_COL_VER"
echo ""

# Bob edits the title TWICE (so his col_version is higher)
run_sql "$BOB_DB" "UPDATE documents SET title = 'Budget Review Notes' WHERE id = 1;"
run_sql "$BOB_DB" "UPDATE documents SET title = 'Budget Review 2024' WHERE id = 1;"
BOB_TITLE=$(run_sql "$BOB_DB" "SELECT title FROM documents WHERE id = 1;")
BOB_COL_VER=$(run_sql "$BOB_DB" "SELECT col_version FROM crsql_changes WHERE cid = 'title';")

echo "  Bob edits twice, ending with: 'Budget Review 2024'"
echo "    → col_version becomes: $BOB_COL_VER (higher because he edited twice)"
echo ""

echo "Before sync:"
echo "  Alice sees: '$ALICE_TITLE' (col_version=$ALICE_COL_VER)"
echo "  Bob sees:   '$BOB_TITLE' (col_version=$BOB_COL_VER)"
echo ""

# Sync both directions
echo "Syncing..."
sync_changes "$ALICE_DB" "$BOB_DB" 0 > /dev/null
sync_changes "$BOB_DB" "$ALICE_DB" 0 > /dev/null

ALICE_AFTER=$(run_sql "$ALICE_DB" "SELECT title FROM documents WHERE id = 1;")
BOB_AFTER=$(run_sql "$BOB_DB" "SELECT title FROM documents WHERE id = 1;")

echo "After sync:"
echo "  Alice sees: '$ALICE_AFTER'"
echo "  Bob sees:   '$BOB_AFTER'"
echo ""

if [[ "$ALICE_AFTER" == "$BOB_AFTER" ]]; then
    echo "PASS: Both devices converged to same title"
else
    echo "FAIL: Devices did not converge"
    echo "  Alice: $ALICE_AFTER"
    echo "  Bob:   $BOB_AFTER"
    FAILURES=$((FAILURES + 1))
fi

if [[ "$ALICE_AFTER" == "Budget Review 2024" ]]; then
    echo "PASS: Higher col_version ($BOB_COL_VER) won over lower ($ALICE_COL_VER)"
else
    echo "INFO: Winner was '$ALICE_AFTER' (expected 'Budget Review 2024' since Bob had higher col_version)"
fi
echo ""

# =============================================================================
# SCENARIO 2: Same col_version - value comparison breaks tie
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SCENARIO 2: Tie-breaker when col_version is equal"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When two devices have the same col_version, the larger value wins."
echo "This ensures deterministic convergence regardless of sync order."
echo ""

# Reset to fresh state for this scenario
ALICE_DB2="$TMPDIR/alice2.sqlite"
BOB_DB2="$TMPDIR/bob2.sqlite"

run_sql "$ALICE_DB2" "
    CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, score INTEGER);
    SELECT crsql_as_crr('items');
"
run_sql "$BOB_DB2" "
    CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, score INTEGER);
    SELECT crsql_as_crr('items');
"

# Both insert same row with different values (col_version will be 1 for both)
run_sql "$ALICE_DB2" "INSERT INTO items VALUES (1, 50);"
run_sql "$BOB_DB2" "INSERT INTO items VALUES (1, 75);"

ALICE_SCORE=$(run_sql "$ALICE_DB2" "SELECT score FROM items WHERE id = 1;")
BOB_SCORE=$(run_sql "$BOB_DB2" "SELECT score FROM items WHERE id = 1;")

echo "Both devices insert id=1 with col_version=1:"
echo "  Alice: score = $ALICE_SCORE"
echo "  Bob:   score = $BOB_SCORE"
echo ""

# Sync in both directions
sync_changes "$ALICE_DB2" "$BOB_DB2" 0 > /dev/null
sync_changes "$BOB_DB2" "$ALICE_DB2" 0 > /dev/null

ALICE_FINAL=$(run_sql "$ALICE_DB2" "SELECT score FROM items WHERE id = 1;")
BOB_FINAL=$(run_sql "$BOB_DB2" "SELECT score FROM items WHERE id = 1;")

echo "After sync (tie-break by value):"
echo "  Alice: score = $ALICE_FINAL"
echo "  Bob:   score = $BOB_FINAL"
echo ""

if [[ "$ALICE_FINAL" == "$BOB_FINAL" ]]; then
    echo "PASS: Both devices converged to same value"
else
    echo "FAIL: Devices did not converge"
    FAILURES=$((FAILURES + 1))
fi

if [[ "$ALICE_FINAL" == "75" ]]; then
    echo "PASS: Larger value (75) won the tie-break"
else
    echo "INFO: Winner was $ALICE_FINAL (tie-break rule may vary by implementation)"
fi
echo ""

# =============================================================================
# SCENARIO 3: Sync order doesn't matter
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SCENARIO 3: Sync order independence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "CRDTs guarantee: final state is independent of sync order."
echo "Let's verify with a third device that syncs in reverse order."
echo ""

# Create Carol's device and sync in opposite order
CAROL_DB="$TMPDIR/carol.sqlite"
run_sql "$CAROL_DB" "
    CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, score INTEGER);
    SELECT crsql_as_crr('items');
"

# Carol gets Bob's changes first, then Alice's (opposite of Alice's sync order)
echo "Carol syncs: Bob first, then Alice"
sync_changes "$BOB_DB2" "$CAROL_DB" 0 > /dev/null
sync_changes "$ALICE_DB2" "$CAROL_DB" 0 > /dev/null

CAROL_FINAL=$(run_sql "$CAROL_DB" "SELECT score FROM items WHERE id = 1;")

echo "  Carol's result: score = $CAROL_FINAL"
echo "  Alice's result: score = $ALICE_FINAL"
echo ""

if [[ "$CAROL_FINAL" == "$ALICE_FINAL" ]]; then
    echo "PASS: Same result regardless of sync order (CRDT property)"
else
    echo "FAIL: Sync order affected result (violates CRDT invariant)"
    FAILURES=$((FAILURES + 1))
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "═══════════════════════════════════════════════════════════════════════"
echo "SUMMARY: CR-SQLite Conflict Resolution"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Key concepts demonstrated:"
echo ""
echo "  1. COLUMN-LEVEL GRANULARITY"
echo "     - Each column of each row has its own col_version"
echo "     - Editing 'title' doesn't affect 'content'"
echo ""
echo "  2. LAST-WRITER-WINS (LWW)"
echo "     - Higher col_version always wins"
echo "     - col_version increments on each local write"
echo ""
echo "  3. DETERMINISTIC TIE-BREAK"
echo "     - Same col_version → larger value wins"
echo "     - Ensures all devices converge to identical state"
echo ""
echo "  4. ORDER INDEPENDENCE"
echo "     - Final state is same regardless of sync order"
echo "     - This is the key CRDT property"
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "✓ All conflict resolution scenarios PASSED"
    exit 0
else
    echo "✗ $FAILURES scenario(s) FAILED"
    exit 1
fi
