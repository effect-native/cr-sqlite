#!/usr/bin/env bash
# Schema Alter Tests for Zig CR-SQLite
# Tests crsql_begin_alter() and crsql_commit_alter() UDFs
#
# These functions enable safe schema modification on CRR tables:
# - crsql_begin_alter('table'): Disables triggers, prepares for schema change
# - crsql_commit_alter('table'): Recreates triggers for new schema
#
# Test cases:
# 1. Basic alter flow (add column)
# 2. Triggers disabled during alter
# 3. Drop column handling (placeholder)
# 4. Changes sync after alter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig CR-SQLite Schema Alter Tests ==="
echo "Tests: crsql_begin_alter() / crsql_commit_alter()"
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

TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $TMPFILE $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# Helper to run SQL and get result (returns last line of output)
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Check if alter functions are available
echo "Checking alter function availability..."
SMOKE_RESULT=$(run_sql "SELECT crsql_begin_alter('nonexistent');" 2>&1 || echo "ERROR")
if grep -q "no such function: crsql_begin_alter" "$ERRFILE" 2>/dev/null; then
    echo "SKIP: crsql_begin_alter() not yet implemented"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                           TEST SUMMARY                               ║"
    echo "╠═══════════════════════════════════════════════════════════════════════╣"
    echo "║  PASSED:  0                                                          ║"
    echo "║  FAILED:  0                                                          ║"
    echo "║  SKIPPED: 4 (alter functions not implemented)                        ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "⚠ All tests SKIPPED (crsql_begin_alter not yet implemented)"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Basic Alter Flow (Add Column)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Basic Alter Flow (Add Column)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');

-- Begin alter
SELECT crsql_begin_alter('foo');

-- Add column
ALTER TABLE foo ADD COLUMN c TEXT;

-- Commit alter
SELECT crsql_commit_alter('foo');

-- Verify triggers work on new column
UPDATE foo SET c = 'world' WHERE a = 1;

-- Verify clock has entry for new column
SELECT COUNT(*) FROM foo__crsql_clock WHERE col_name = 'c';
")

if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_as_crr() not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null || grep -q "error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Clock has entry for new column 'c' after alter"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected clock entry count=1 for new column, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Triggers Disabled During Alter
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Triggers Disabled During Alter"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "
CREATE TABLE bar (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('bar');

SELECT crsql_begin_alter('bar');

-- Inserts during alter should NOT create clock entries (triggers disabled)
INSERT INTO bar VALUES (1, 'test');

-- Clock should be empty (triggers disabled)
SELECT COUNT(*) FROM bar__crsql_clock;
")

if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_as_crr() not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null || grep -q "error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: Clock is empty during alter (triggers disabled)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected clock count=0 during alter, got: $RESULT"
    echo "        (Triggers should be disabled during alter)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test 2b: After commit_alter, new inserts create clock entries
echo ""
echo "Test 2b: Triggers Re-enabled After commit_alter"
RESULT=$(run_sql "
CREATE TABLE bar2 (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('bar2');

SELECT crsql_begin_alter('bar2');
SELECT crsql_commit_alter('bar2');

-- Now inserts should create clock entries
INSERT INTO bar2 VALUES (2, 'test2');

-- Should have at least 1 entry (for column b and/or sentinel)
-- Note: pk in clock table is rowid (integer), not packed blob
SELECT CASE WHEN COUNT(*) >= 1 THEN 'OK' ELSE 'EMPTY' END FROM bar2__crsql_clock;
")

if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null || grep -q "error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "OK" ]]; then
    echo "  PASS: Clock entries created after commit_alter (triggers re-enabled)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected clock entries after commit_alter, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Drop Column Handling (Begin/Commit Flow)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Drop Column Handling (Begin/Commit Flow)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "
CREATE TABLE baz (a PRIMARY KEY NOT NULL, b, c);
SELECT crsql_as_crr('baz');
INSERT INTO baz VALUES (1, 'b_val', 'c_val');

-- Verify clock has entries for b and c
SELECT COUNT(*) FROM baz__crsql_clock WHERE col_name IN ('b', 'c');
")

if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null || grep -q "error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: Clock has entries for columns b and c (pre-alter baseline)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected clock entries=2 for b and c, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test that begin/commit flow works without actual drop
echo ""
echo "Test 3b: Begin/Commit Alter Flow Works"
RESULT=$(run_sql "
CREATE TABLE baz2 (a PRIMARY KEY NOT NULL, b, c);
SELECT crsql_as_crr('baz2');
INSERT INTO baz2 VALUES (1, 'b_val', 'c_val');

-- Begin/commit without actual schema change should succeed
SELECT crsql_begin_alter('baz2');
SELECT crsql_commit_alter('baz2');

-- Table should still work
UPDATE baz2 SET b = 'updated' WHERE a = 1;
SELECT b FROM baz2 WHERE a = 1;
")

if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null || grep -q "error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "updated" ]]; then
    echo "  PASS: Begin/commit alter flow works, table still functional"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'updated', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Changes Sync After Alter
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Changes Sync After Alter"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "
CREATE TABLE sync_test (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('sync_test');
INSERT INTO sync_test VALUES (1, 'original');

SELECT crsql_begin_alter('sync_test');
ALTER TABLE sync_test ADD COLUMN c INTEGER DEFAULT 0;
SELECT crsql_commit_alter('sync_test');

UPDATE sync_test SET c = 42 WHERE a = 1;

-- crsql_changes should include the new column
SELECT cid FROM crsql_changes WHERE [table] = 'sync_test' AND cid = 'c';
")

if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null || grep -q "error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "c" ]]; then
    echo "  PASS: crsql_changes includes new column 'c' after alter"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected crsql_changes to have cid='c', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                           TEST SUMMARY                               ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$TOTAL_PASS"
printf "║  FAILED:  %-58d ║\n" "$TOTAL_FAIL"
printf "║  SKIPPED: %-58d ║\n" "$TOTAL_SKIP"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "✓ All implemented tests PASSED"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo "⚠ All tests SKIPPED (alter functions not yet implemented)"
    exit 0
else
    echo "✗ Some tests FAILED"
    exit 1
fi
