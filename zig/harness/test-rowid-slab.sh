#!/usr/bin/env bash
# Test harness for Zig CR-SQLite rowid slab allocation
# Equivalent to core/src/changes-vtab-rowid.test.c
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ROWID_SLAB_SIZE from core/src/consts.h
ROWID_SLAB_SIZE=10000000000000

echo "=== Zig CR-SQLite Rowid Slab Tests ==="
echo "ROWID_SLAB_SIZE: $ROWID_SLAB_SIZE"

# Build the extension
echo ""
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

# Run tests via sqlite3 CLI (using nix-provided sqlite with loadable extension support)
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $TMPFILE $ERRFILE" EXIT

echo "Running SQL tests..."

# Execute tests and capture both stdout and stderr
nix run nixpkgs#sqlite -- :memory: <<EOF > "$TMPFILE" 2>"$ERRFILE" || true
.load $EXT

-- Test setup: Create first CRR table
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
INSERT INTO foo VALUES (2, 3);

-- Test 1: First table rowids start at 1
SELECT 'TEST1_ROWID1=' || _rowid_ FROM crsql_changes ORDER BY _rowid_ LIMIT 1;
SELECT 'TEST1_ROWID2=' || _rowid_ FROM crsql_changes ORDER BY _rowid_ LIMIT 1 OFFSET 1;

-- Test setup: Create second CRR table
CREATE TABLE bar (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('bar');
INSERT INTO bar VALUES (1, 2);
INSERT INTO bar VALUES (2, 3);

-- Test setup: Create third CRR table  
CREATE TABLE baz (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('baz');
INSERT INTO baz VALUES (1, 2);
INSERT INTO baz VALUES (2, 3);

-- Test 2-3: Second and third table rowids use correct slabs
-- Query all changes ordered by rowid to match C test assertions
SELECT 'ALL_ROWIDS=' || group_concat(_rowid_, ',') FROM (SELECT _rowid_ FROM crsql_changes ORDER BY _rowid_);

SELECT crsql_finalize();
EOF

echo ""
echo "=== SQL Output ==="
if [[ -s "$TMPFILE" ]]; then
    cat "$TMPFILE"
fi

if [[ -s "$ERRFILE" ]]; then
    echo ""
    echo "=== SQL Errors ==="
    cat "$ERRFILE"
    echo ""
    
    # Check for specific missing functionality
    if grep -q "no such function: crsql_as_crr" "$ERRFILE"; then
        echo "BLOCKED: crsql_as_crr() function not yet implemented in Zig extension"
        exit 2
    fi
    if grep -q "no such table: crsql_changes" "$ERRFILE"; then
        echo "BLOCKED: crsql_changes virtual table not yet implemented in Zig extension"
        exit 2
    fi
    if grep -q "no such function: crsql_finalize" "$ERRFILE"; then
        echo "BLOCKED: crsql_finalize() function not yet implemented in Zig extension"
        exit 2
    fi
fi

echo ""

# Parse and verify results
FAILURES=0

# Test 1: First rowid should be 1
ROWID1=$(grep 'TEST1_ROWID1=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")
if [[ "$ROWID1" == "1" ]]; then
    echo "PASS: First table, first rowid = 1"
elif [[ "$ROWID1" == "MISSING" ]]; then
    echo "FAIL: First table, first rowid = MISSING (test did not produce output)"
    FAILURES=$((FAILURES + 1))
else
    echo "FAIL: First table, first rowid = $ROWID1 (expected 1)"
    FAILURES=$((FAILURES + 1))
fi

# Test 2: Second rowid should be 2
ROWID2=$(grep 'TEST1_ROWID2=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "MISSING")
if [[ "$ROWID2" == "2" ]]; then
    echo "PASS: First table, second rowid = 2"
elif [[ "$ROWID2" == "MISSING" ]]; then
    echo "FAIL: First table, second rowid = MISSING (test did not produce output)"
    FAILURES=$((FAILURES + 1))
else
    echo "FAIL: First table, second rowid = $ROWID2 (expected 2)"
    FAILURES=$((FAILURES + 1))
fi

# Test 3-6: Verify all rowids match expected slab allocation
# Expected: 1, 2, 10000000000001, 10000000000002, 20000000000001, 20000000000002
ALL_ROWIDS=$(grep 'ALL_ROWIDS=' "$TMPFILE" 2>/dev/null | cut -d= -f2 || echo "")

if [[ -z "$ALL_ROWIDS" ]]; then
    echo "FAIL: ALL_ROWIDS not found in output (crsql_changes query failed)"
    FAILURES=$((FAILURES + 1))
else
    IFS=',' read -ra ROWID_ARRAY <<< "$ALL_ROWIDS"

    EXPECTED_ROWIDS=(
        1
        2
        $((1 * ROWID_SLAB_SIZE + 1))
        $((1 * ROWID_SLAB_SIZE + 2))
        $((2 * ROWID_SLAB_SIZE + 1))
        $((2 * ROWID_SLAB_SIZE + 2))
    )

    for i in "${!EXPECTED_ROWIDS[@]}"; do
        EXPECTED="${EXPECTED_ROWIDS[$i]}"
        ACTUAL="${ROWID_ARRAY[$i]:-MISSING}"
        if [[ "$ACTUAL" == "$EXPECTED" ]]; then
            echo "PASS: rowid[$i] = $ACTUAL"
        else
            echo "FAIL: rowid[$i] = $ACTUAL (expected $EXPECTED)"
            FAILURES=$((FAILURES + 1))
        fi
    done
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "=== All rowid slab tests PASSED ==="
    exit 0
else
    echo "=== $FAILURES test(s) FAILED ==="
    exit 1
fi
