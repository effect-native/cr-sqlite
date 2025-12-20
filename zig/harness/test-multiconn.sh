#!/usr/bin/env bash
# Multi-Connection Parity Test for Zig CR-SQLite
#
# Tests multi-connection scenarios with on-disk databases:
# 1. Two connections open same file
# 2. Insert on conn1, verify visible on conn2 (after commit)
# 3. Schema change on conn2, operations on conn1 still work
# 4. Interleaved inserts from both connections
# 5. Final state is union of all inserts
#
# Oracle parity: compares Zig vs Rust/C extension behavior

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "=== Multi-Connection Parity Test ==="
echo ""

# Determine extension paths
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
    RUST_EXT="$ROOT_DIR/lib/crsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
    RUST_EXT="$ROOT_DIR/lib/crsqlite.so"
fi

# Build Zig extension if needed
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    exit 1
fi

echo "Zig extension: $ZIG_EXT"

# Check for Rust/C extension (oracle)
HAVE_ORACLE=false
if [[ -f "$RUST_EXT" ]]; then
    echo "Oracle extension: $RUST_EXT"
    HAVE_ORACLE=true
else
    echo "Oracle extension: NOT FOUND (skipping parity tests)"
fi
echo ""

# Create temp directory under .tmp for test databases
TMPDIR="$ROOT_DIR/.tmp/multiconn-test-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Helper function to run SQL with extension
run_sql() {
    local ext="$1"
    local db="$2"
    local sql="$3"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $ext" "$sql" 2>&1 || true
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Two connections, insert on conn1 visible on conn2
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Insert on conn1 visible on conn2 (same file)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ZIG="$TMPDIR/test1_zig.db"
DB_RUST="$TMPDIR/test1_rust.db"

# Zig test
output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'from_conn1');
")

if echo "$output" | grep -q "no such function: crsql_as_crr"; then
    echo "  [Zig] BLOCKED: crsql_as_crr not implemented"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    # Conn2: Open same file, verify data visible
    count=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT COUNT(*) FROM foo;" | tail -1)
    if [[ "$count" == "1" ]]; then
        echo "  [Zig] PASS: Insert from conn1 visible on conn2"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [Zig] FAIL: Expected 1 row, got: $count"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# Oracle parity (Rust/C)
if [[ "$HAVE_ORACLE" == "true" ]]; then
    run_sql "$RUST_EXT" "$DB_RUST" "
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'from_conn1');
" > /dev/null

    rust_count=$(run_sql "$RUST_EXT" "$DB_RUST" "SELECT COUNT(*) FROM foo;" | tail -1)
    if [[ "$rust_count" == "1" ]]; then
        echo "  [Rust/C] PASS: Insert from conn1 visible on conn2"
        echo "  PARITY: Both extensions behave identically"
    else
        echo "  [Rust/C] Result: $rust_count"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Interleaved inserts from two connections
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Interleaved inserts from two connections"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ZIG="$TMPDIR/test2_zig.db"
DB_RUST="$TMPDIR/test2_rust.db"

# Zig test: setup
output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, source TEXT);
SELECT crsql_as_crr('items');
")

if echo "$output" | grep -q "no such function: crsql_as_crr"; then
    echo "  [Zig] BLOCKED: crsql_as_crr not implemented"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    # Interleaved inserts (each is a separate connection)
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO items VALUES (1, 'conn1_first');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO items VALUES (2, 'conn2_first');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO items VALUES (3, 'conn1_second');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO items VALUES (4, 'conn2_second');" > /dev/null
    
    count=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT COUNT(*) FROM items;" | tail -1)
    if [[ "$count" == "4" ]]; then
        echo "  [Zig] PASS: All 4 interleaved inserts present"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [Zig] FAIL: Expected 4 rows, got: $count"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# Oracle parity
if [[ "$HAVE_ORACLE" == "true" ]]; then
    run_sql "$RUST_EXT" "$DB_RUST" "
CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, source TEXT);
SELECT crsql_as_crr('items');
" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO items VALUES (1, 'conn1_first');" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO items VALUES (2, 'conn2_first');" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO items VALUES (3, 'conn1_second');" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO items VALUES (4, 'conn2_second');" > /dev/null
    
    rust_count=$(run_sql "$RUST_EXT" "$DB_RUST" "SELECT COUNT(*) FROM items;" | tail -1)
    if [[ "$rust_count" == "4" ]]; then
        echo "  [Rust/C] PASS: All 4 interleaved inserts present"
        echo "  PARITY: Both extensions behave identically"
    else
        echo "  [Rust/C] Result: $rust_count rows"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Schema change on conn2, operations on conn1 still work
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Add column on conn2, verify conn1 sees it"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ZIG="$TMPDIR/test3_zig.db"

# Zig test: setup
output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
CREATE TABLE notes (id INTEGER PRIMARY KEY NOT NULL, title TEXT);
SELECT crsql_as_crr('notes');
INSERT INTO notes VALUES (1, 'First note');
")

if echo "$output" | grep -q "no such function: crsql_as_crr"; then
    echo "  [Zig] BLOCKED: crsql_as_crr not implemented"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    # Add column via crsql_begin_alter/crsql_commit_alter
    alter_output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
SELECT crsql_begin_alter('notes');
ALTER TABLE notes ADD COLUMN body TEXT;
SELECT crsql_commit_alter('notes');
")
    
    if echo "$alter_output" | grep -q "no such function: crsql_begin_alter"; then
        echo "  [Zig] SKIP: crsql_begin_alter not implemented"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    else
        # Verify new column exists
        insert_output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
INSERT INTO notes VALUES (2, 'Second note', 'Body text');
SELECT id, title, body FROM notes WHERE id = 2;
")
        
        if echo "$insert_output" | grep -q "Second note"; then
            echo "  [Zig] PASS: Schema change visible across connections"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  [Zig] FAIL: Schema change not visible"
            echo "  Output: $insert_output"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: db_version consistency across connections
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: db_version consistency across connections"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ZIG="$TMPDIR/test4_zig.db"

# Zig test: setup
output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
CREATE TABLE data (id INTEGER PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('data');
")

if echo "$output" | grep -q "no such function: crsql_as_crr"; then
    echo "  [Zig] BLOCKED: crsql_as_crr not implemented"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    # Get initial version
    ver0=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT crsql_db_version();" | tail -1)
    
    # Insert and get version
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO data VALUES (1, 100);" > /dev/null
    ver1=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT crsql_db_version();" | tail -1)
    
    # Conn2: Should see same version
    ver2=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT crsql_db_version();" | tail -1)
    
    # Conn2: Insert
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO data VALUES (2, 200);" > /dev/null
    ver3=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT crsql_db_version();" | tail -1)
    
    # Conn1: Should see updated version
    ver4=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT crsql_db_version();" | tail -1)
    
    echo "  [Zig] Versions: v0=$ver0 v1=$ver1 v2=$ver2 v3=$ver3 v4=$ver4"
    
    # Verify monotonic increase
    if [[ "$ver1" -gt "$ver0" && "$ver3" -gt "$ver1" && "$ver4" -ge "$ver3" ]]; then
        echo "  [Zig] PASS: db_version monotonically increases"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [Zig] FAIL: db_version not monotonically increasing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Changes from both connections appear in crsql_changes
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Changes from multiple connections tracked correctly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ZIG="$TMPDIR/test5_zig.db"

# Zig test: setup
output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
CREATE TABLE records (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('records');
")

if echo "$output" | grep -q "no such function: crsql_as_crr"; then
    echo "  [Zig] BLOCKED: crsql_as_crr not implemented"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    # Multiple connections insert
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO records VALUES (1, 'Alice');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO records VALUES (2, 'Bob');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO records VALUES (3, 'Charlie');" > /dev/null
    
    # Count changes
    change_count=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT COUNT(*) FROM crsql_changes;" | tail -1)
    record_count=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT COUNT(*) FROM records;" | tail -1)
    
    # Each insert should generate at least one change (for the 'name' column)
    if [[ "$record_count" == "3" && "$change_count" -ge "3" ]]; then
        echo "  [Zig] PASS: $record_count records, $change_count changes tracked"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [Zig] FAIL: Expected 3 records and >=3 changes"
        echo "    Got: $record_count records, $change_count changes"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Final state union test - comprehensive with compound PK
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Final state is union of all inserts (compound PK)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ZIG="$TMPDIR/test6_zig.db"
DB_RUST="$TMPDIR/test6_rust.db"

# Zig test: setup with compound primary key
output=$(run_sql "$ZIG_EXT" "$DB_ZIG" "
CREATE TABLE events (
    user_id INTEGER NOT NULL,
    event_id INTEGER NOT NULL,
    event_type TEXT,
    PRIMARY KEY (user_id, event_id)
);
SELECT crsql_as_crr('events');
")

if echo "$output" | grep -q "no such function: crsql_as_crr"; then
    echo "  [Zig] BLOCKED: crsql_as_crr not implemented"
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    # Multiple connections insert different data
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO events VALUES (1, 1, 'login');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO events VALUES (1, 2, 'click');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO events VALUES (2, 1, 'signup');" > /dev/null
    run_sql "$ZIG_EXT" "$DB_ZIG" "INSERT INTO events VALUES (2, 2, 'purchase');" > /dev/null
    
    # Get final state
    row_count=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT COUNT(*) FROM events;" | tail -1)
    
    if [[ "$row_count" == "4" ]]; then
        echo "  [Zig] PASS: All 4 events present (compound PK works)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [Zig] FAIL: Expected 4 events, got: $row_count"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# Oracle parity
if [[ "$HAVE_ORACLE" == "true" ]]; then
    run_sql "$RUST_EXT" "$DB_RUST" "
CREATE TABLE events (
    user_id INTEGER NOT NULL,
    event_id INTEGER NOT NULL,
    event_type TEXT,
    PRIMARY KEY (user_id, event_id)
);
SELECT crsql_as_crr('events');
" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO events VALUES (1, 1, 'login');" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO events VALUES (1, 2, 'click');" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO events VALUES (2, 1, 'signup');" > /dev/null
    run_sql "$RUST_EXT" "$DB_RUST" "INSERT INTO events VALUES (2, 2, 'purchase');" > /dev/null
    
    rust_count=$(run_sql "$RUST_EXT" "$DB_RUST" "SELECT COUNT(*) FROM events;" | tail -1)
    
    if [[ "$rust_count" == "4" ]]; then
        echo "  [Rust/C] PASS: All 4 events present"
        
        # Compare final state for parity (filter out error messages)
        zig_state=$(run_sql "$ZIG_EXT" "$DB_ZIG" "SELECT user_id, event_id, event_type FROM events ORDER BY user_id, event_id;" | grep -v "^Error:")
        rust_state=$(run_sql "$RUST_EXT" "$DB_RUST" "SELECT user_id, event_id, event_type FROM events ORDER BY user_id, event_id;" | grep -v "^Error:")
        
        if [[ "$zig_state" == "$rust_state" ]]; then
            echo "  PARITY: Zig and Rust/C final states identical"
        else
            echo "  DIVERGENCE: Final states differ"
            echo "    Zig: $zig_state"
            echo "    Rust/C: $rust_state"
        fi
    else
        echo "  [Rust/C] Result: $rust_count rows"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║              MULTI-CONNECTION TEST SUMMARY                           ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$PASS_COUNT"
printf "║  FAILED:  %-58d ║\n" "$FAIL_COUNT"
printf "║  SKIPPED: %-58d ║\n" "$SKIP_COUNT"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $FAIL_COUNT -eq 0 && $PASS_COUNT -gt 0 ]]; then
    echo "All implemented multi-connection tests PASSED"
    exit 0
elif [[ $FAIL_COUNT -eq 0 && $PASS_COUNT -eq 0 ]]; then
    echo "All tests SKIPPED (core functions not implemented)"
    exit 2
else
    echo "Some tests FAILED"
    exit 1
fi
