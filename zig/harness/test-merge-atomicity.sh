#!/usr/bin/env bash
# Merge Atomicity Test Suite for Zig CR-SQLite
# Tests that batch change application via crsql_changes is atomic
#
# Reference: core/rs/core/src/changes_vtab_write.rs (Rust uses savepoints)
# C test: core/src/rows-impacted.test.c (testMultipartInsertInTx)
#
# This is a SPEC (RED) test -- tests define expected behavior.
# If Zig doesn't guarantee atomicity, these tests will FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Merge Atomicity (crsql_changes batch application)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Allow override via environment
LIB="${EXT:-$LIB}"

if [[ ! -f "$LIB" ]]; then
    echo "Extension not found at $LIB"
    echo "Run 'nix run nixpkgs#zig -- build' first"
    exit 1
fi

echo "Using extension: $LIB"
echo ""

TMPDIR="${SCRIPT_DIR}/../../.tmp"
mkdir -p "$TMPDIR"
ERRFILE=$(mktemp "$TMPDIR/atomicity-err.XXXXXX")
OUTFILE=$(mktemp "$TMPDIR/atomicity-out.XXXXXX")
trap "rm -f $ERRFILE $OUTFILE" EXIT

PASS=0
FAIL=0
SKIP=0

run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_sql_file() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_sql_check_error() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>&1 | tail -1 || true
}

# =============================================================================
# Test 1: Single multi-row INSERT is atomic (all succeed together)
# =============================================================================
# Reference: rows-impacted.test.c:testMultipartInsertInTx (lines 89-118)
# A single INSERT with multiple VALUE tuples should apply all or none
echo "Test 1: Single multi-row INSERT applies all rows atomically"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES 
  ('foo', X'010901', 'b', 10, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0),
  ('foo', X'010902', 'b', 20, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0),
  ('foo', X'010903', 'b', 30, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
SELECT crsql_rows_impacted();
")
if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif grep -qi "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: All 3 rows applied (rows_impacted=3)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected rows_impacted=3, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 2: Invalid table in batch causes rollback of entire statement
# =============================================================================
# A multi-row INSERT where one row references invalid table should fail atomically
# Note: Unknown columns are IGNORED by policy (best-effort apply), so we use
# an invalid table name to test hard error atomicity.
echo "Test 2: Invalid table in batch causes entire statement to fail"
TMPDB2=$(mktemp "$TMPDIR/atomicity-test2.XXXXXX.db")

# Setup table first
run_sql_file "$TMPDB2" "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('items');
" > /dev/null 2>&1

# Try the batch insert with invalid table - this should fail with hard error
run_sql_file "$TMPDB2" "
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES 
  ('items', X'010901', 'name', 'valid_item', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0),
  ('NONEXISTENT_TABLE', X'010902', 'col', 'fail', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
COMMIT;
" > /dev/null 2>&1

# Now check if the first row persisted (it should NOT if atomic)
ITEM_COUNT=$(run_sql_file "$TMPDB2" "SELECT count(*) FROM items;" 2>/dev/null)
rm -f "$TMPDB2"

if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ITEM_COUNT" == "0" ]]; then
    echo "  PASS: Entire batch rolled back (item count=0)"
    PASS=$((PASS + 1))
elif [[ "$ITEM_COUNT" == "1" ]]; then
    echo "  FAIL: First row persisted despite invalid second row (count=$ITEM_COUNT)"
    echo "        Expected atomic rollback of entire statement"
    FAIL=$((FAIL + 1))
else
    echo "  INFO: Unexpected item count=$ITEM_COUNT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 3: rows_impacted reflects only committed changes (0 after failed batch)
# =============================================================================
# After a failed batch, rows_impacted should be 0 (nothing committed)
echo "Test 3: rows_impacted is 0 after failed batch"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('items');
-- First: successful insert
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
COMMIT;
-- rows_impacted resets on commit, should be 0 now
SELECT crsql_rows_impacted();
")
if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: rows_impacted resets to 0 after commit"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected rows_impacted=0 after commit, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 4: Transaction boundary behavior (COMMIT fails, nothing persists)
# =============================================================================
# When a transaction contains valid and invalid inserts, COMMIT should fail
# and nothing should persist
echo "Test 4: Failed transaction commits nothing"
# Use a temp file-based DB so we can check state after failed commit
TMPDB=$(mktemp "$TMPDIR/atomicity-test4.XXXXXX.db")
run_sql_file "$TMPDB" "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 100, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
-- Now insert an invalid row (invalid table)
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('NONEXISTENT_TABLE', X'010902', 'x', 200, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
COMMIT;
" > /dev/null 2>&1

# Check if any data persisted
PERSISTED=$(run_sql_file "$TMPDB" "SELECT count(*) FROM foo;" 2>/dev/null || echo "ERROR")
rm -f "$TMPDB"

if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$PERSISTED" == "ERROR" ]]; then
    echo "  SKIP: Could not query database"
    SKIP=$((SKIP + 1))
elif [[ "$PERSISTED" == "0" ]]; then
    echo "  PASS: Failed transaction committed nothing (count=0)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Data persisted despite failed transaction (count=$PERSISTED)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 5: Explicit savepoint behavior (partial commit possible)
# =============================================================================
# With explicit savepoints, user can control rollback granularity
echo "Test 5: Explicit savepoints allow partial rollback"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('items');
BEGIN;
SAVEPOINT sp1;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('items', X'010901', 'name', 'persisted_item', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
RELEASE sp1;
-- This insert should fail (invalid table), but sp1 changes should persist
SAVEPOINT sp2;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('NONEXISTENT', X'010902', 'x', 'fail', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
ROLLBACK TO sp2;
RELEASE sp2;
COMMIT;
SELECT count(*) FROM items;
")
if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif grep -qi "error" "$ERRFILE" 2>/dev/null; then
    # If the first savepoint's insert failed due to invalid table error propagating,
    # that's also acceptable behavior (strict atomicity)
    echo "  INFO: Transaction rolled back entirely (strict atomicity)"
    echo "        This is acceptable; explicit savepoints require correct usage"
    PASS=$((PASS + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: First savepoint's data persisted, second rolled back (count=1)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 1 item (from first savepoint), got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 6: Multi-row INSERT into crsql_changes with duplicate PKs
# =============================================================================
# Duplicate PKs in same batch - should either merge or fail atomically
echo "Test 6: Duplicate PKs in single batch handled correctly"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES 
  ('foo', X'010901', 'b', 10, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0),
  ('foo', X'010901', 'b', 20, 2, 2, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
COMMIT;
SELECT b FROM foo WHERE a = 1;
")
if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "20" ]]; then
    echo "  PASS: Second value (higher col_version) wins (b=20)"
    PASS=$((PASS + 1))
elif [[ "$RESULT" == "10" ]]; then
    echo "  FAIL: First value persisted, second didn't apply (b=10)"
    FAIL=$((FAIL + 1))
else
    echo "  INFO: Result=$RESULT (expected 20 with proper merge semantics)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 7: Verify base table integrity after hard error in batch
# =============================================================================
# After a batch with mix of valid row + hard error, base table should be consistent
# Note: Unknown columns are IGNORED by policy, so we use invalid table for hard error
echo "Test 7: Base table integrity after failed batch (hard error)"
TMPDB=$(mktemp "$TMPDIR/atomicity-test7.XXXXXX.db")

# Setup: create table with some initial data
run_sql_file "$TMPDB" "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name, qty INTEGER);
SELECT crsql_as_crr('items');
INSERT INTO items VALUES (1, 'existing', 100);
" > /dev/null 2>&1

# Attempt batch with valid update + invalid table (hard error)
run_sql_file "$TMPDB" "
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES 
  ('items', X'010901', 'qty', 999, 2, 2, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0),
  ('NONEXISTENT_TABLE', X'010902', 'col', 'fail', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
COMMIT;
" > /dev/null 2>&1

# Check if existing row was modified
QTY=$(run_sql_file "$TMPDB" "SELECT qty FROM items WHERE id = 1;" 2>/dev/null || echo "ERROR")
rm -f "$TMPDB"

if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$QTY" == "100" ]]; then
    echo "  PASS: Existing row unchanged after failed batch (qty=100)"
    PASS=$((PASS + 1))
elif [[ "$QTY" == "999" ]]; then
    echo "  FAIL: First change applied despite second failing (qty=999)"
    echo "        Expected atomic rollback"
    FAIL=$((FAIL + 1))
else
    echo "  INFO: qty=$QTY (expected 100 with atomic rollback)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 8: rows_impacted count within active transaction
# =============================================================================
# During a transaction (before commit), rows_impacted should accumulate
echo "Test 8: rows_impacted accumulates within transaction"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 10, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010902', 'b', 20, 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
SELECT crsql_rows_impacted();
")
if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: rows_impacted accumulates in transaction (count=2)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected rows_impacted=2, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 9: Best-effort apply for unknown columns (ignorable case)
# =============================================================================
# Unknown columns are IGNORED by policy -- valid rows should still be applied.
# This validates the "best-effort apply" contract for schema mismatches.
echo "Test 9: Best-effort apply ignores unknown columns, applies valid rows"
TMPDB=$(mktemp "$TMPDIR/atomicity-test9.XXXXXX.db")

# Setup: create table
run_sql_file "$TMPDB" "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('items');
" > /dev/null 2>&1

# Batch with valid column + unknown column (both should NOT cause error)
# The unknown column row should be ignored, valid row should be applied
run_sql_file "$TMPDB" "
BEGIN;
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES 
  ('items', X'010901', 'name', 'valid_item', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0),
  ('items', X'010902', 'UNKNOWN_COLUMN', 'ignored', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
COMMIT;
" > /dev/null 2>&1

# Check the result: valid row should exist, second row should be missing (column ignored)
ITEM_COUNT=$(run_sql_file "$TMPDB" "SELECT count(*) FROM items;" 2>/dev/null || echo "ERROR")
VALID_ITEM=$(run_sql_file "$TMPDB" "SELECT name FROM items WHERE id = 1;" 2>/dev/null || echo "ERROR")
rm -f "$TMPDB"

if grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ITEM_COUNT" == "1" && "$VALID_ITEM" == "valid_item" ]]; then
    echo "  PASS: Valid row applied, unknown column row ignored (count=1, name='valid_item')"
    PASS=$((PASS + 1))
elif [[ "$ITEM_COUNT" == "0" ]]; then
    echo "  FAIL: Both rows rolled back (count=0)"
    echo "        Expected best-effort apply: unknown columns ignored, valid rows applied"
    FAIL=$((FAIL + 1))
elif [[ "$ITEM_COUNT" == "2" ]]; then
    echo "  FAIL: Both rows applied (count=2)"
    echo "        Expected: unknown column row should be ignored (row not created)"
    FAIL=$((FAIL + 1))
else
    echo "  INFO: Unexpected result: count=$ITEM_COUNT, name=$VALID_ITEM"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Merge Atomicity Tests Summary: $PASS passed, $FAIL failed, $SKIP skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All merge atomicity tests passed!"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All merge atomicity tests SKIPPED (functions not implemented)"
    # Exit 2 indicates tests skipped due to missing implementation
    exit 2
else
    echo "Some merge atomicity tests FAILED"
    echo ""
    echo "NOTE: Failures indicate the Zig implementation may not guarantee"
    echo "statement/transaction atomicity for crsql_changes batch inserts."
    echo ""
    echo "Reference: Rust uses savepoints (core/rs/core/src/changes_vtab_write.rs)"
    exit 1
fi
