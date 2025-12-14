#!/usr/bin/env bash
# =============================================================================
# Realistic Multi-Device Sync Test
# =============================================================================
#
# SCENARIO: Alice and Bob each have a phone with a local SQLite database.
# They work on a shared todo list. Alice adds items offline, Bob adds items
# offline, then they sync via a central server (simulated here).
#
# This test demonstrates the fundamental CR-SQLite use case:
# 1. Two devices start with the same empty schema
# 2. Each device makes independent local changes
# 3. Changes are extracted via crsql_changes
# 4. Changes are applied to the other device
# 5. Both devices converge to the same state
#
# WHAT YOU'LL LEARN:
# - How to set up a table for CRDT sync with crsql_as_crr()
# - How to extract changes for syncing (SELECT FROM crsql_changes)
# - How to apply changes from another device (INSERT INTO crsql_changes)
# - How site_id tracks the origin of each change
# - How db_version provides a sync cursor
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "═══════════════════════════════════════════════════════════════════════"
echo "REALISTIC SCENARIO: Multi-Device Todo List Sync"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Actors: Alice (phone A) and Bob (phone B)"
echo "Goal: Both maintain a shared todo list that syncs when online"
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

# Helper function to run SQL
run_sql() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$sql" 2>"$ERRFILE" || true
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function: crsql_as_crr" "$ERRFILE"; then
            echo "BLOCKED: crsql_as_crr() not yet implemented"
            exit 2
        fi
        # Silently ignore debug output
        if ! grep -q "^Error:" "$ERRFILE"; then
            true  # Just debug messages
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
# STEP 1: Alice and Bob set up their devices with identical schema
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Both devices initialize with same schema"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SQL (both devices):"
echo "  CREATE TABLE todos (id INTEGER PRIMARY KEY NOT NULL, title, done);"
echo "  SELECT crsql_as_crr('todos');"
echo ""
echo "Note: Using INTEGER PK. Each device generates unique IDs to avoid collisions."
echo ""

for db in "$ALICE_DB" "$BOB_DB"; do
    run_sql "$db" "
        CREATE TABLE todos (id INTEGER PRIMARY KEY NOT NULL, title, done);
        SELECT crsql_as_crr('todos');
    "
done

ALICE_SITE=$(run_sql "$ALICE_DB" "SELECT hex(crsql_site_id());")
BOB_SITE=$(run_sql "$BOB_DB" "SELECT hex(crsql_site_id());")

echo "Result:"
echo "  Alice's site_id: ${ALICE_SITE:0:16}..."
echo "  Bob's site_id:   ${BOB_SITE:0:16}..."
echo ""

if [[ "$ALICE_SITE" != "$BOB_SITE" ]]; then
    echo "PASS: Each device has a unique site_id"
else
    echo "FAIL: Site IDs should be unique per device"
    FAILURES=$((FAILURES + 1))
fi
echo ""

# =============================================================================
# STEP 2: Alice adds todos while offline
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Alice adds todos while offline"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Alice's SQL (using IDs 1-100 range):"
echo "  INSERT INTO todos VALUES (1, 'Buy groceries', 0);"
echo "  INSERT INTO todos VALUES (2, 'Walk the dog', 0);"
echo ""

run_sql "$ALICE_DB" "
    INSERT INTO todos VALUES (1, 'Buy groceries', 0);
    INSERT INTO todos VALUES (2, 'Walk the dog', 0);
"

ALICE_VERSION=$(run_sql "$ALICE_DB" "SELECT crsql_db_version();")
ALICE_COUNT=$(run_sql "$ALICE_DB" "SELECT COUNT(*) FROM todos;")

echo "Result:"
echo "  Alice's db_version: $ALICE_VERSION (advanced by local changes)"
echo "  Alice's todo count: $ALICE_COUNT"
echo ""

if [[ "$ALICE_COUNT" == "2" ]]; then
    echo "PASS: Alice has 2 todos"
else
    echo "FAIL: Expected 2 todos, got $ALICE_COUNT"
    FAILURES=$((FAILURES + 1))
fi
echo ""

# =============================================================================
# STEP 3: Bob adds todos while offline (concurrently)
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Bob adds todos while offline (concurrently)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Bob's SQL (using IDs 101-200 range to avoid collision):"
echo "  INSERT INTO todos VALUES (101, 'Call mom', 0);"
echo "  INSERT INTO todos VALUES (102, 'Fix bike', 0);"
echo ""

run_sql "$BOB_DB" "
    INSERT INTO todos VALUES (101, 'Call mom', 0);
    INSERT INTO todos VALUES (102, 'Fix bike', 0);
"

BOB_VERSION=$(run_sql "$BOB_DB" "SELECT crsql_db_version();")
BOB_COUNT=$(run_sql "$BOB_DB" "SELECT COUNT(*) FROM todos;")

echo "Result:"
echo "  Bob's db_version: $BOB_VERSION"
echo "  Bob's todo count: $BOB_COUNT"
echo ""

if [[ "$BOB_COUNT" == "2" ]]; then
    echo "PASS: Bob has 2 todos"
else
    echo "FAIL: Expected 2 todos, got $BOB_COUNT"
    FAILURES=$((FAILURES + 1))
fi
echo ""

# =============================================================================
# STEP 4: Bidirectional sync (both devices come online)
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Bidirectional sync - devices come online"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "How sync works:"
echo "  1. Extract changes: SELECT * FROM crsql_changes WHERE db_version > ?"
echo "  2. Apply changes:   INSERT INTO crsql_changes VALUES (...)"
echo ""

# Sync Alice -> Bob
echo "Syncing Alice's changes to Bob..."
A_TO_B=$(sync_changes "$ALICE_DB" "$BOB_DB" 0)
echo "  Applied $A_TO_B change(s) from Alice to Bob"

# Sync Bob -> Alice
echo "Syncing Bob's changes to Alice..."
B_TO_A=$(sync_changes "$BOB_DB" "$ALICE_DB" 0)
echo "  Applied $B_TO_A change(s) from Bob to Alice"
echo ""

# =============================================================================
# STEP 5: Verify convergence - both devices should have identical data
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Verify convergence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ALICE_FINAL=$(run_sql "$ALICE_DB" "SELECT id, title FROM todos ORDER BY id;")
BOB_FINAL=$(run_sql "$BOB_DB" "SELECT id, title FROM todos ORDER BY id;")

ALICE_FINAL_COUNT=$(run_sql "$ALICE_DB" "SELECT COUNT(*) FROM todos;")
BOB_FINAL_COUNT=$(run_sql "$BOB_DB" "SELECT COUNT(*) FROM todos;")

echo "Alice's todos after sync:"
run_sql "$ALICE_DB" "SELECT '  ' || id || ': ' || title FROM todos ORDER BY id;"
echo ""

echo "Bob's todos after sync:"
run_sql "$BOB_DB" "SELECT '  ' || id || ': ' || title FROM todos ORDER BY id;"
echo ""

if [[ "$ALICE_FINAL" == "$BOB_FINAL" ]]; then
    echo "PASS: Alice and Bob have converged to identical state"
else
    echo "FAIL: Data mismatch after sync"
    echo "  Alice: $ALICE_FINAL"
    echo "  Bob:   $BOB_FINAL"
    FAILURES=$((FAILURES + 1))
fi

if [[ "$ALICE_FINAL_COUNT" == "4" ]]; then
    echo "PASS: Both devices have all 4 todos"
else
    echo "FAIL: Expected 4 todos, got Alice=$ALICE_FINAL_COUNT, Bob=$BOB_FINAL_COUNT"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# =============================================================================
# BONUS: Show how site_id tracks change origin
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "BONUS: Change origin tracking via site_id"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Even after sync, each change remembers which device created it:"
echo ""

# Get the integer PKs from todos table and show their origin
run_sql "$ALICE_DB" "
    SELECT '  todo ' || 
        CASE 
            WHEN pk = X'010901' THEN '1'
            WHEN pk = X'010902' THEN '2'
            WHEN pk = X'010965' THEN '101'
            WHEN pk = X'010966' THEN '102'
            ELSE quote(pk)
        END ||
        ' originated from ' ||
        CASE 
            WHEN hex(site_id) = '$ALICE_SITE' THEN 'Alice'
            WHEN hex(site_id) = '$BOB_SITE' THEN 'Bob'
            ELSE 'Unknown'
        END
    FROM crsql_changes
    WHERE cid = 'title'
    ORDER BY pk;
"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "═══════════════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "This test demonstrated:"
echo "  ✓ Setting up CRDT-enabled tables with crsql_as_crr()"
echo "  ✓ Making offline changes that automatically track in crsql_changes"
echo "  ✓ Extracting changes for sync: SELECT FROM crsql_changes WHERE db_version > ?"
echo "  ✓ Applying changes from peer: INSERT INTO crsql_changes VALUES (...)"
echo "  ✓ Automatic convergence - both devices end up with identical data"
echo "  ✓ Origin tracking - site_id shows where each change came from"
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "✓ All realistic sync scenarios PASSED"
    exit 0
else
    echo "✗ $FAILURES scenario(s) FAILED"
    exit 1
fi
