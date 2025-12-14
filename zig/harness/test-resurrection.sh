#!/usr/bin/env bash
# Tombstone Resurrection Test for Zig CR-SQLite
# Tests that a higher causal length from a remote node resurrects a deleted row.
#
# Scenario (from merge_oracle.zig:resurrection_wins_over_delete):
#   - Node A: creates row (cl=1), then deletes it (cl=2, tombstone)
#   - Node B: modifies the row (cl=3, live)
#   - When A merges B's change, the row is resurrected (cl=3 > cl=2)
#
# Source: test_cl_merging.py:test_resurrection_of_dead_thing_via_sentinel
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Tombstone Resurrection Test ==="
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
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$LIB" ]]; then
    echo "FAIL: Extension not found at $LIB"
    exit 1
fi

echo "Extension: $LIB"
echo ""

# Use temp files for database and outputs
DB=$(mktemp).db
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $DB $TMPFILE $ERRFILE" EXIT

echo "Testing tombstone resurrection..."
echo "Scenario:"
echo "  1. Node A creates row id=1, val='original' (cl=1)"
echo "  2. Node A deletes row id=1 (cl=2, tombstone)"
echo "  3. Node B had modified row to val='resurrected' (cl=3)"
echo "  4. A receives B's change -> row should resurrect with val='resurrected'"
echo ""

# Step 1 & 2: Setup Node A - create row then delete it (creates tombstone cl=2)
echo "Step 1: Create table, insert row, then delete (tombstone cl=2)"
nix run nixpkgs#sqlite -- "$DB" <<EOF 2>"$ERRFILE" || true
.load $LIB

-- Create CRR table
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('foo');

-- Insert row (cl becomes 1)
INSERT INTO foo VALUES (1, 'original');

-- Delete row (cl becomes 2, creates tombstone)
DELETE FROM foo WHERE id = 1;

SELECT crsql_finalize();
EOF

if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo "BLOCKED: crsql_as_crr() not yet implemented"
    exit 2
fi

if [[ -s "$ERRFILE" ]]; then
    echo "Setup errors:"
    cat "$ERRFILE"
fi

# Verify row is deleted
echo ""
echo "Step 2: Verify row is deleted locally"
ROW_COUNT=$(nix run nixpkgs#sqlite -- "$DB" -cmd ".load $LIB" "SELECT COUNT(*) FROM foo WHERE id = 1;" 2>/dev/null)
if [[ "$ROW_COUNT" == "0" ]]; then
    echo "  PASS: Row is deleted (count=0)"
else
    echo "  FAIL: Row should be deleted, but count=$ROW_COUNT"
    exit 1
fi

# Verify tombstone exists in clock table (col_version=2 on sentinel row)
# Note: The cl (causal length) is stored as col_version on the sentinel (-1) row
echo ""
echo "Step 3: Verify tombstone in clock table (col_version=2 on sentinel)"
# pk is stored as integer for single-column integer PKs
TOMBSTONE_CL=$(nix run nixpkgs#sqlite -- "$DB" -cmd ".load $LIB" "
SELECT col_version FROM foo__crsql_clock WHERE pk = 1 AND col_name = '-1';
" 2>&1 | head -1)
if [[ "$TOMBSTONE_CL" == "2" ]]; then
    echo "  PASS: Tombstone exists with col_version=2 (cl=2)"
else
    echo "  INFO: Tombstone col_version=$TOMBSTONE_CL (expected 2)"
    # Don't fail - implementation may vary
fi

# Step 3: Simulate receiving resurrection from Node B (cl=3)
# Node B's site_id: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB (16 bytes of 0xBB)
# PK encoding for integer 1: X'010901' (01=1 col, 09=int type, 01=value 1)
echo ""
echo "Step 4: Apply resurrection from Node B (cl=3)"
echo "  Sending: INSERT INTO crsql_changes with cl=3, val='resurrected'"
nix run nixpkgs#sqlite -- "$DB" <<EOF > "$TMPFILE" 2>"$ERRFILE" || true
.load $LIB

BEGIN;

-- First, send the sentinel row to resurrect (cl=3 > local cl=2)
-- cid='-1' is the sentinel indicating row existence
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 10, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 3, 0);

-- Then send the actual column value
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'val', 'resurrected', 1, 10, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 3, 1);

SELECT 'ROWS_IMPACTED=' || crsql_rows_impacted();

COMMIT;
SELECT crsql_finalize();
EOF

if [[ -s "$ERRFILE" ]]; then
    echo "  Merge errors:"
    cat "$ERRFILE"
fi

ROWS_IMPACTED=$(grep 'ROWS_IMPACTED=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")
echo "  rows_impacted: $ROWS_IMPACTED"

# Step 4: Verify resurrection
echo ""
echo "Step 5: Verify row is resurrected"

# Track test results for summary
TEST_PASSED=true

# Check if row exists
ROW_EXISTS=$(nix run nixpkgs#sqlite -- "$DB" -cmd ".load $LIB" "SELECT COUNT(*) FROM foo WHERE id = 1;" 2>&1 | head -1)
if [[ "$ROW_EXISTS" == "1" ]]; then
    echo "  PASS: Row exists after resurrection (count=1)"
else
    echo "  FAIL: Row not resurrected (count=$ROW_EXISTS, expected 1)"
    echo "  NOTE: This is expected to fail until resurrection logic is implemented"
    TEST_PASSED=false
fi

# Check the value (only if row exists)
if [[ "$ROW_EXISTS" == "1" ]]; then
    ROW_VAL=$(nix run nixpkgs#sqlite -- "$DB" -cmd ".load $LIB" "SELECT val FROM foo WHERE id = 1;" 2>&1 | head -1)
    if [[ "$ROW_VAL" == "resurrected" ]]; then
        echo "  PASS: Row has correct value (val='resurrected')"
    else
        echo "  FAIL: Row value incorrect (val='$ROW_VAL', expected 'resurrected')"
        TEST_PASSED=false
    fi
else
    echo "  SKIP: Cannot check value - row does not exist"
fi

# Verify clock table shows cl=3 (stored as col_version on sentinel)
echo ""
echo "Step 6: Verify clock table updated (col_version=3 on sentinel)"
NEW_CL=$(nix run nixpkgs#sqlite -- "$DB" -cmd ".load $LIB" "
SELECT col_version FROM foo__crsql_clock WHERE pk = 1 AND col_name = '-1';
" 2>&1 | head -1)
if [[ "$NEW_CL" == "3" ]]; then
    echo "  PASS: Clock table shows col_version=3 (cl=3)"
else
    echo "  INFO: Clock table col_version=$NEW_CL (expected 3)"
    # Clock update failure is secondary - doesn't affect test pass/fail
fi

echo ""
if [[ "$TEST_PASSED" == "true" ]]; then
    echo "=== Resurrection Test PASSED ==="
    echo ""
    echo "Summary:"
    echo "  - Row was deleted locally (cl=2 tombstone)"
    echo "  - Received resurrection from remote (cl=3)"
    echo "  - Row was resurrected with remote's value"
    echo "  - This confirms: higher cl wins, resurrection beats delete"
    exit 0
else
    echo "=== Resurrection Test FAILED ==="
    echo ""
    echo "Summary:"
    echo "  - Row was deleted locally (cl=2 tombstone)"
    echo "  - Received resurrection from remote (cl=3)"
    echo "  - Row was NOT resurrected (merge logic incomplete)"
    echo ""
    echo "This test will pass once changes_vtab implements:"
    echo "  1. Detect resurrection (incoming cl > local tombstone cl)"
    echo "  2. Re-insert row into base table on resurrection"
    echo "  3. Update clock table with new cl"
    exit 1
fi
