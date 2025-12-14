#!/usr/bin/env bash
# Merge Integration Tests for Zig CR-SQLite
# Tests that changes_vtab.changesUpdate correctly implements merge semantics
#
# These tests verify behavior defined in merge_oracle.zig:
# 1. Identical value INSERTs don't increment crsql_rows_impacted()
# 2. Winning value INSERTs do increment crsql_rows_impacted()
# 3. Higher col_version beats lower col_version
#
# TDD Status: These tests will FAIL until merge logic is implemented in changesUpdate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig CR-SQLite Merge Integration Tests ==="
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

# Run tests via sqlite3 CLI
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $TMPFILE $ERRFILE" EXIT

echo "=== Test 1: Identical value INSERT is no-op ==="
echo "Source: rows-impacted.test.c:testUpdateThatDoesNotChangeAnything:196"
echo ""
echo "Expected: crsql_rows_impacted() returns 0 when remote sends identical value"
echo ""

# Test 1: Identical value with same col_version should NOT increment counter
nix run nixpkgs#sqlite -- :memory: <<EOF > "$TMPFILE" 2>"$ERRFILE" || true
.load $EXT

-- Setup: Create CRR table with initial data
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);

-- Get the site_id for local changes (should be 16 zero bytes)
-- After INSERT, clock table has: pk=1, col_name='b', col_version=1, db_version=1

-- Reset rows_impacted counter (COMMIT resets it)
-- Note: After crsql_as_crr(), we're in autocommit mode, so start a transaction
BEGIN;

-- INSERT identical change via crsql_changes (simulating sync)
-- This uses the same value (2) and same col_version (1)
-- Local should win, so rows_impacted should be 0
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 2, 1, 1, X'00000000000000000000000000000000', 1, 0);

SELECT 'TEST1_ROWS_IMPACTED=' || crsql_rows_impacted();

SELECT crsql_finalize();
EOF

echo "SQL Output:"
if [[ -s "$TMPFILE" ]]; then
    cat "$TMPFILE"
fi

if [[ -s "$ERRFILE" ]]; then
    echo ""
    echo "SQL Errors:"
    cat "$ERRFILE"
    
    # Check for specific missing functionality
    if grep -q "no such function: crsql_as_crr" "$ERRFILE"; then
        echo ""
        echo "BLOCKED: crsql_as_crr() function not yet implemented"
        exit 2
    fi
fi

echo ""
TEST1_RESULT=$(grep 'TEST1_ROWS_IMPACTED=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")

if [[ "$TEST1_RESULT" == "0" ]]; then
    echo "PASS: Identical value INSERT is no-op (rows_impacted=0)"
elif [[ "$TEST1_RESULT" == "MISSING" ]]; then
    echo "FAIL: Test did not produce output"
    exit 1
else
    echo "FAIL: Identical value INSERT incremented counter (rows_impacted=$TEST1_RESULT, expected 0)"
    echo "NOTE: This is expected to fail until merge logic is implemented"
    # Don't exit - continue to run other tests
fi

echo ""
echo "=== Test 2: Higher col_version wins and increments counter ==="
echo "Source: test_cl_merging.py:test_larger_col_version_same_cl"
echo ""
echo "Expected: crsql_rows_impacted() returns 1 when remote has higher col_version"
echo ""

# Test 2: Higher col_version should win and increment counter
nix run nixpkgs#sqlite -- :memory: <<EOF > "$TMPFILE" 2>"$ERRFILE" || true
.load $EXT

-- Setup: Create CRR table with initial data
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);

-- After INSERT, clock has col_version=1 for column 'b'

-- Start transaction for merge test (counter resets on commit)
BEGIN;

-- INSERT change with HIGHER col_version (2 > 1)
-- Remote should win, rows_impacted should be 1
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 99, 2, 2, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 1, 0);

SELECT 'TEST2_ROWS_IMPACTED=' || crsql_rows_impacted();

-- Verify the value was actually updated in base table
SELECT 'TEST2_VALUE=' || b FROM foo WHERE a = 1;

SELECT crsql_finalize();
EOF

echo "SQL Output:"
if [[ -s "$TMPFILE" ]]; then
    cat "$TMPFILE"
fi

if [[ -s "$ERRFILE" ]]; then
    echo ""
    echo "SQL Errors:"
    cat "$ERRFILE"
fi

echo ""
TEST2_ROWS=$(grep 'TEST2_ROWS_IMPACTED=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")
TEST2_VALUE=$(grep 'TEST2_VALUE=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")

if [[ "$TEST2_ROWS" == "1" ]]; then
    echo "PASS: Higher col_version INSERT incremented counter (rows_impacted=1)"
elif [[ "$TEST2_ROWS" == "MISSING" ]]; then
    echo "FAIL: Test did not produce output"
else
    echo "INFO: rows_impacted=$TEST2_ROWS (expected 1)"
    echo "NOTE: Current stub always increments, so this may show 1 even without real merge"
fi

if [[ "$TEST2_VALUE" == "99" ]]; then
    echo "PASS: Base table value was updated to 99"
else
    echo "FAIL: Base table value not updated (value=$TEST2_VALUE, expected 99)"
    echo "NOTE: This is expected to fail until merge logic updates base table"
fi

echo ""
echo "=== Test 3: Lower col_version loses (no-op) ==="
echo "Source: rows-impacted.test.c:testUpdateThatDoesNotChangeAnything:214"
echo ""
echo "Expected: crsql_rows_impacted() returns 0 when remote has lower col_version"
echo ""

# Test 3: Lower col_version should lose (no-op)
nix run nixpkgs#sqlite -- :memory: <<EOF > "$TMPFILE" 2>"$ERRFILE" || true
.load $EXT

-- Setup: Create CRR table with initial data
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);

-- After INSERT, clock has col_version=1 for column 'b'

-- Start transaction for merge test (counter resets on commit)
BEGIN;

-- INSERT change with LOWER col_version (0 < 1)
-- Local should win, rows_impacted should be 0
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 999, 0, 1, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 1, 0);

SELECT 'TEST3_ROWS_IMPACTED=' || crsql_rows_impacted();

-- Verify the value was NOT updated in base table
SELECT 'TEST3_VALUE=' || b FROM foo WHERE a = 1;

SELECT crsql_finalize();
EOF

echo "SQL Output:"
if [[ -s "$TMPFILE" ]]; then
    cat "$TMPFILE"
fi

if [[ -s "$ERRFILE" ]]; then
    echo ""
    echo "SQL Errors:"
    cat "$ERRFILE"
fi

echo ""
TEST3_ROWS=$(grep 'TEST3_ROWS_IMPACTED=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")
TEST3_VALUE=$(grep 'TEST3_VALUE=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")

if [[ "$TEST3_ROWS" == "0" ]]; then
    echo "PASS: Lower col_version INSERT is no-op (rows_impacted=0)"
else
    echo "FAIL: Lower col_version INSERT should be no-op (rows_impacted=$TEST3_ROWS, expected 0)"
    echo "NOTE: This is expected to fail until merge logic is implemented"
fi

if [[ "$TEST3_VALUE" == "2" ]]; then
    echo "PASS: Base table value unchanged (value=2)"
else
    echo "INFO: Base table value=$TEST3_VALUE (expected 2)"
fi

echo ""
echo "=== Summary ==="
echo ""
echo "These tests document expected merge behavior per merge_oracle.zig."
echo "Tests will FAIL until changes_vtab.changesUpdate implements:"
echo "  1. Query local state from clock table"
echo "  2. Use determineMergeWinner() logic for conflict resolution"
echo "  3. Only increment rows_impacted when remote wins"
echo "  4. Update base table and clock table when remote wins"
echo ""
echo "Current stub in changesUpdate unconditionally increments counter."
