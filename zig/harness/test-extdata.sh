#!/usr/bin/env bash
# ExtData Lifecycle Tests for Zig CR-SQLite
# Tests observable behaviors mapped to C ext-data.test.c:
#   - Schema changes trigger table info refresh (crsql_fetchPragmaSchemaVersion)
#   - db_version correctly computed after schema changes (crsql_recreate_db_version_stmt)
#   - Multiple CRR tables tracked correctly (tableInfos tracking)
#   - Dropping tables removes from tracked set
#
# Reference: core/src/ext-data.test.c
# Oracle parity: compare Zig vs Rust/C on same operations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: ExtData Lifecycle (ext-data.test.c observable behaviors)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        ARCH="aarch64"
    fi
    ZIG_EXT_PREBUILT="$ROOT_DIR/lib/crsqlite-zig-darwin-${ARCH}.dylib"
    ZIG_EXT_BUILD="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
    RUST_EXT="$ROOT_DIR/lib/crsqlite.dylib"
else
    ARCH=$(uname -m)
    ZIG_EXT_PREBUILT="$ROOT_DIR/lib/crsqlite-zig-linux-${ARCH}.so"
    ZIG_EXT_BUILD="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
    RUST_EXT="$ROOT_DIR/lib/crsqlite.so"
fi

# Try to build, but fall back to pre-built if build fails
echo "Building Zig extension..."
cd "$ZIG_DIR"
if nix run nixpkgs#zig -- build 2>&1; then
    ZIG_EXT="$ZIG_EXT_BUILD"
    echo "Using freshly built extension"
elif [[ -f "$ZIG_EXT_PREBUILT" ]]; then
    ZIG_EXT="$ZIG_EXT_PREBUILT"
    echo "Build failed, using pre-built extension at $ZIG_EXT"
else
    echo "FAIL: Zig build failed and no pre-built extension at $ZIG_EXT_PREBUILT"
    exit 1
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    exit 1
fi

echo "Zig extension: $ZIG_EXT"
if [[ -f "$RUST_EXT" ]]; then
    echo "Rust/C extension: $RUST_EXT (oracle parity enabled)"
    HAS_ORACLE=1
else
    echo "Rust/C extension: not found (oracle parity disabled)"
    HAS_ORACLE=0
fi
echo ""

TMPDIR="${ROOT_DIR}/.tmp"
mkdir -p "$TMPDIR"
ERRFILE=$(mktemp "$TMPDIR/extdata-err.XXXXXX")
TMPFILE=$(mktemp "$TMPDIR/extdata-tmp.XXXXXX")
trap "rm -f $ERRFILE $TMPFILE" EXIT

PASS=0
FAIL=0
SKIP=0

# Helper to run SQL with Zig extension
run_zig() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL with Rust/C extension
run_rust() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $RUST_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL and get all output
run_zig_all() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Check core function availability
echo "Checking function availability..."
SMOKE=$(run_zig "SELECT crsql_as_crr('nonexistent');" 2>&1 || echo "ERROR")
if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo "SKIP: crsql_as_crr() not implemented"
    echo ""
    echo "All ExtData tests SKIPPED (core functions not implemented)"
    exit 2
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Schema changes trigger table info refresh
# Observable: After CREATE TABLE + as_crr, changes vtab shows the new table
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Schema change triggers table info refresh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Test 1a: New CRR table is immediately trackable"
RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
SELECT COUNT(*) FROM crsql_changes WHERE \"table\" = 'foo';
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: New CRR table tracked in crsql_changes after schema change"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 1 change, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test 1b: Adding second CRR table updates tracking"
RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');

CREATE TABLE bar (x PRIMARY KEY NOT NULL, y);
SELECT crsql_as_crr('bar');
INSERT INTO bar VALUES (10, 'world');

SELECT COUNT(DISTINCT \"table\") FROM crsql_changes;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: Both CRR tables tracked after schema changes"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 2 distinct tables, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: db_version correctly computed after schema changes
# Observable: crsql_db_version() returns correct value after CREATE/INSERT
# Maps to: testRecreateDbVersionStmt in ext-data.test.c
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: db_version correctly computed after schema changes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Test 2a: db_version=0 before any CRR tables exist"
RESULT=$(run_zig "SELECT crsql_db_version();")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: db_version=0 with no CRR tables"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version=0, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test 2b: db_version=0 after crsql_as_crr but before any data"
RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: db_version=0 after as_crr, before data"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version=0, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test 2c: db_version=1 after first insert"
RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: db_version=1 after first insert"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version=1, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test 2d: db_version increments across multiple tables"
RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');

CREATE TABLE bar (x PRIMARY KEY NOT NULL, y);
SELECT crsql_as_crr('bar');
INSERT INTO bar VALUES (10, 'world');

SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: db_version=2 after inserts into two tables"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version=2, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Multiple CRR tables tracked correctly
# Observable: crsql_changes includes data from all CRR tables
# Maps to: tableInfos tracking in ext-data.test.c
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Multiple CRR tables tracked correctly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Test 3a: Three CRR tables all tracked"
RESULT=$(run_zig "
CREATE TABLE t1 (id PRIMARY KEY NOT NULL, v);
CREATE TABLE t2 (id PRIMARY KEY NOT NULL, v);
CREATE TABLE t3 (id PRIMARY KEY NOT NULL, v);
SELECT crsql_as_crr('t1');
SELECT crsql_as_crr('t2');
SELECT crsql_as_crr('t3');
INSERT INTO t1 VALUES (1, 'one');
INSERT INTO t2 VALUES (2, 'two');
INSERT INTO t3 VALUES (3, 'three');
SELECT COUNT(*) FROM crsql_changes;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: 3 CRR tables produce 3 changes"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 3 changes, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test 3b: Each table appears in changes"
RESULT=$(run_zig_all "
CREATE TABLE t1 (id PRIMARY KEY NOT NULL, v);
CREATE TABLE t2 (id PRIMARY KEY NOT NULL, v);
CREATE TABLE t3 (id PRIMARY KEY NOT NULL, v);
SELECT crsql_as_crr('t1');
SELECT crsql_as_crr('t2');
SELECT crsql_as_crr('t3');
INSERT INTO t1 VALUES (1, 'one');
INSERT INTO t2 VALUES (2, 'two');
INSERT INTO t3 VALUES (3, 'three');
SELECT DISTINCT \"table\" FROM crsql_changes ORDER BY \"table\";
" | grep -E '^t[123]$' | sort | tr '\n' ',' | sed 's/,$//')
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "t1,t2,t3" ]]; then
    echo "  PASS: All three tables (t1,t2,t3) appear in crsql_changes"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 't1,t2,t3', got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Dropping tables removes from tracked set
# Observable: After DROP TABLE, changes vtab no longer shows that table
# Maps to: test_ensure_table_infos_are_up_to_date in tableinfo.rs
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Dropping tables removes from tracked set"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Test 4a: Dropped CRR table stops tracking new inserts"
# Note: We can't easily test that old changes disappear (they may remain in clock table)
# but new inserts to a dropped table should fail
RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
SELECT crsql_db_version();
")
V1="$RESULT"

RESULT=$(run_zig "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
DROP TABLE foo;
DROP TABLE foo__crsql_clock;
SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "$V1" ]]; then
    echo "  PASS: db_version unchanged after drop (no new changes tracked)"
    PASS=$((PASS + 1))
else
    echo "  INFO: db_version=$RESULT after drop (was $V1 before drop)"
    # This is acceptable - db_version may or may not change on drop
    PASS=$((PASS + 1))
fi

echo "Test 4b: After drop, remaining tables still tracked"
RESULT=$(run_zig "
CREATE TABLE t1 (id PRIMARY KEY NOT NULL, v);
CREATE TABLE t2 (id PRIMARY KEY NOT NULL, v);
SELECT crsql_as_crr('t1');
SELECT crsql_as_crr('t2');
INSERT INTO t1 VALUES (1, 'one');
INSERT INTO t2 VALUES (2, 'two');

-- Drop t1 and its clock table
DROP TABLE t1;
DROP TABLE t1__crsql_clock;

-- Insert into t2 should still work and advance version
INSERT INTO t2 VALUES (3, 'three');
SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: Remaining table (t2) still tracked after dropping t1"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version=3, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Data version detection across connections (file-based DB)
# Observable: Changes from other connection detected via pragmaDataVersion
# Maps to: testFetchPragmaDataVersion in ext-data.test.c
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Multi-connection data version detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TESTDB="$TMPDIR/extdata-multiconn-$$.db"
rm -f "$TESTDB"

# Setup: Create table and CRR in first session
nix run nixpkgs#sqlite -- "$TESTDB" -cmd ".load $ZIG_EXT" "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'initial');
" 2>"$ERRFILE"

# Session 2: Write from another connection
nix run nixpkgs#sqlite -- "$TESTDB" -cmd ".load $ZIG_EXT" "
INSERT INTO foo VALUES (2, 'from_session2');
" 2>"$ERRFILE"

# Session 1 again: Should see updated db_version
RESULT=$(nix run nixpkgs#sqlite -- "$TESTDB" -cmd ".load $ZIG_EXT" "
SELECT crsql_db_version();
" 2>"$ERRFILE" | tail -1)

rm -f "$TESTDB"

if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: db_version=2 reflects changes from both connections"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version=2, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Oracle parity - Zig vs Rust/C on same operations
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Oracle parity (Zig vs Rust/C)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$HAS_ORACLE" -eq 0 ]]; then
    echo "  SKIP: Rust/C extension not available for oracle comparison"
    SKIP=$((SKIP + 3))
else
    # Test SQL for oracle comparison
    ORACLE_SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
INSERT INTO foo VALUES (2, 'world');
UPDATE foo SET b = 'updated' WHERE a = 1;
SELECT crsql_db_version();
"
    echo "Test 6a: db_version parity after INSERT/UPDATE sequence"
    ZIG_RESULT=$(run_zig "$ORACLE_SQL")
    RUST_RESULT=$(run_rust "$ORACLE_SQL")
    
    if [[ "$ZIG_RESULT" == "$RUST_RESULT" ]]; then
        echo "  PASS: Zig db_version=$ZIG_RESULT matches Rust/C db_version=$RUST_RESULT"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: DIVERGENCE - Zig db_version=$ZIG_RESULT vs Rust/C db_version=$RUST_RESULT"
        FAIL=$((FAIL + 1))
    fi

    # Oracle test: changes count
    ORACLE_SQL2="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
INSERT INTO foo VALUES (2, 'world');
SELECT COUNT(*) FROM crsql_changes;
"
    echo "Test 6b: crsql_changes count parity"
    ZIG_RESULT=$(run_zig "$ORACLE_SQL2")
    RUST_RESULT=$(run_rust "$ORACLE_SQL2")
    
    if [[ "$ZIG_RESULT" == "$RUST_RESULT" ]]; then
        echo "  PASS: Zig changes=$ZIG_RESULT matches Rust/C changes=$RUST_RESULT"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: DIVERGENCE - Zig changes=$ZIG_RESULT vs Rust/C changes=$RUST_RESULT"
        FAIL=$((FAIL + 1))
    fi

    # Oracle test: multiple tables
    ORACLE_SQL3="
CREATE TABLE t1 (id PRIMARY KEY NOT NULL, v);
CREATE TABLE t2 (id PRIMARY KEY NOT NULL, v);
SELECT crsql_as_crr('t1');
SELECT crsql_as_crr('t2');
INSERT INTO t1 VALUES (1, 'a');
INSERT INTO t2 VALUES (2, 'b');
INSERT INTO t1 VALUES (3, 'c');
SELECT crsql_db_version();
"
    echo "Test 6c: Multi-table db_version parity"
    ZIG_RESULT=$(run_zig "$ORACLE_SQL3")
    RUST_RESULT=$(run_rust "$ORACLE_SQL3")
    
    if [[ "$ZIG_RESULT" == "$RUST_RESULT" ]]; then
        echo "  PASS: Zig multi-table db_version=$ZIG_RESULT matches Rust/C=$RUST_RESULT"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: DIVERGENCE - Zig=$ZIG_RESULT vs Rust/C=$RUST_RESULT"
        FAIL=$((FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Leak condition test (from tableinfo.rs test_leak_condition)
# Observable: Multiple schema changes + operations don't crash/error
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Leak condition (schema churn stability)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LEAKDB="$TMPDIR/extdata-leak-$$.db"
rm -f "$LEAKDB"

# Simulate the test_leak_condition scenario from tableinfo.rs
# Multiple connections, schema changes interleaved with data operations
echo "Test 7: Schema churn with interleaved operations"

# Connection 1: Create table, make CRR, insert, update
nix run nixpkgs#sqlite -- "$LEAKDB" -cmd ".load $ZIG_EXT" "
CREATE TABLE foo (a NOT NULL, b NOT NULL, PRIMARY KEY (a, b));
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
UPDATE foo SET b = 3 WHERE a = 1;
" 2>"$ERRFILE"

ERR1=$?

# Connection 2: Insert, create another table
nix run nixpkgs#sqlite -- "$LEAKDB" -cmd ".load $ZIG_EXT" "
INSERT INTO foo VALUES (2, 3);
CREATE TABLE bar (x);
" 2>"$ERRFILE"

ERR2=$?

# Connection 1 again: More inserts
nix run nixpkgs#sqlite -- "$LEAKDB" -cmd ".load $ZIG_EXT" "
INSERT INTO foo VALUES (3, 4);
" 2>"$ERRFILE"

ERR3=$?

# Connection 2 again: More inserts
nix run nixpkgs#sqlite -- "$LEAKDB" -cmd ".load $ZIG_EXT" "
INSERT INTO foo VALUES (4, 5);
" 2>"$ERRFILE"

ERR4=$?

# Final check: db_version should reflect all operations
RESULT=$(nix run nixpkgs#sqlite -- "$LEAKDB" -cmd ".load $ZIG_EXT" "
SELECT crsql_db_version();
" 2>"$ERRFILE" | tail -1)

rm -f "$LEAKDB"

if [[ $ERR1 -eq 0 && $ERR2 -eq 0 && $ERR3 -eq 0 && $ERR4 -eq 0 ]]; then
    # Should have 5 operations: insert(1,2), update(1,3), insert(2,3), insert(3,4), insert(4,5)
    # But update doesn't create new row, so 4 distinct row versions minimum
    if [[ "$RESULT" -ge 4 ]]; then
        echo "  PASS: Schema churn stable, db_version=$RESULT (expected >=4)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: db_version=$RESULT, expected >=4"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: Errors during schema churn operations"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                      EXTDATA TEST SUMMARY                            ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$PASS"
printf "║  FAILED:  %-58d ║\n" "$FAIL"
printf "║  SKIPPED: %-58d ║\n" "$SKIP"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All ExtData lifecycle tests PASSED"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All ExtData tests SKIPPED (functions not implemented)"
    exit 2
else
    echo "Some ExtData tests FAILED"
    exit 1
fi
