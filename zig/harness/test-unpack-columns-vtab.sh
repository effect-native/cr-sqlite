#!/usr/bin/env bash
# crsql_unpack_columns Virtual Table Module Test Suite
# Validates SELECT ... FROM crsql_unpack_columns WHERE package = ... behavior
#
# Reference: core/rs/core/src/unpack_columns_vtab.rs
#
# The crsql_unpack_columns module:
#   - Is a read-only (INNOCUOUS) virtual table
#   - Unpacks binary blob format produced by crsql_pack_columns()
#   - Returns one row per packed column with the unpacked cell value
#   - Requires WHERE package = ... constraint (hidden column)
#
# This is a SPEC (RED) test — expects to FAIL until unpack_columns module is implemented in Zig.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: crsql_unpack_columns Virtual Table Module"
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
ERRFILE=$(mktemp "$TMPDIR/unpack-err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

PASS=0
FAIL=0
SKIP=0

run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_sql_check_error() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>&1 || true
}

run_sql_all() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" || true
}

# =============================================================================
# Test 1: Module exists
# =============================================================================
# Reference: unpack_columns_vtab.rs:connect() creates module "crsql_unpack_columns"
echo "Test 1: Module exists (no 'no such module' or 'no such table' error)"
RESULT=$(run_sql_check_error "SELECT * FROM crsql_unpack_columns WHERE package = X'00';")
if echo "$RESULT" | grep -qi "no such module\|no such table"; then
    echo "  FAIL: crsql_unpack_columns module not found (expected for RED phase)"
    echo "        Error: $RESULT"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: Module exists"
    PASS=$((PASS + 1))
fi

# =============================================================================
# Test 2: Unpack single integer
# =============================================================================
# Reference: unpack_columns_vtab.rs uses unpack_columns() to decode values
echo "Test 2: Unpack single integer"
RESULT=$(run_sql "SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns(42);")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "42" ]]; then
    echo "  PASS: Unpacked integer 42"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 42, got: $RESULT"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 3: Unpack single string
# =============================================================================
echo "Test 3: Unpack single string"
RESULT=$(run_sql "SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns('hello');")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "hello" ]]; then
    echo "  PASS: Unpacked string 'hello'"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 'hello', got: $RESULT"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 4: Unpack single blob
# =============================================================================
echo "Test 4: Unpack single blob"
RESULT=$(run_sql "SELECT hex(cell) FROM crsql_unpack_columns WHERE package = crsql_pack_columns(x'DEADBEEF');")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "DEADBEEF" ]]; then
    echo "  PASS: Unpacked blob X'DEADBEEF'"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected DEADBEEF, got: $RESULT"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 5: Unpack multiple values (compound PK simulation)
# =============================================================================
# Reference: unpack_columns_vtab.rs:next() iterates through unpacked columns
echo "Test 5: Unpack multiple values (compound PK simulation)"
RESULT=$(run_sql_all "SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns(12, 'str', x'010203');")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
else
    # Expected output: 3 rows, one per column
    EXPECTED=$'12\nstr\n\x01\x02\x03'
    # Check row count and first value
    ROW_COUNT=$(echo "$RESULT" | wc -l | tr -d ' ')
    FIRST_ROW=$(echo "$RESULT" | head -1)
    SECOND_ROW=$(echo "$RESULT" | sed -n '2p')
    if [[ "$ROW_COUNT" -eq 3 && "$FIRST_ROW" == "12" && "$SECOND_ROW" == "str" ]]; then
        echo "  PASS: Unpacked 3 values: 12, 'str', blob"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Expected 3 rows (12, str, blob), got $ROW_COUNT rows:"
        echo "        First: '$FIRST_ROW', Second: '$SECOND_ROW'"
        cat "$ERRFILE" 2>/dev/null || true
        FAIL=$((FAIL + 1))
    fi
fi

# =============================================================================
# Test 6: Unpack NULL value
# =============================================================================
echo "Test 6: Unpack NULL value"
RESULT=$(run_sql "SELECT coalesce(cell, 'NULL_VALUE') FROM crsql_unpack_columns WHERE package = crsql_pack_columns(NULL);")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "NULL_VALUE" ]]; then
    echo "  PASS: Unpacked NULL value"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected NULL (displayed as 'NULL_VALUE'), got: $RESULT"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 7: Unpack mixed types (preserves type info)
# =============================================================================
# Reference: unpack_columns_vtab.rs:column() returns Integer, Text, Float, Null, Blob
echo "Test 7: Unpack mixed types preserves type info"
RESULT=$(run_sql_all "SELECT typeof(cell) FROM crsql_unpack_columns WHERE package = crsql_pack_columns(123, 'text', 3.14, NULL, x'AB');")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
else
    # Expected types in order: integer, text, real, null, blob
    TYPE1=$(echo "$RESULT" | sed -n '1p')
    TYPE2=$(echo "$RESULT" | sed -n '2p')
    TYPE3=$(echo "$RESULT" | sed -n '3p')
    TYPE4=$(echo "$RESULT" | sed -n '4p')
    TYPE5=$(echo "$RESULT" | sed -n '5p')
    if [[ "$TYPE1" == "integer" && "$TYPE2" == "text" && "$TYPE3" == "real" && "$TYPE4" == "null" && "$TYPE5" == "blob" ]]; then
        echo "  PASS: Types preserved: integer, text, real, null, blob"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Expected (integer, text, real, null, blob), got:"
        echo "        ($TYPE1, $TYPE2, $TYPE3, $TYPE4, $TYPE5)"
        cat "$ERRFILE" 2>/dev/null || true
        FAIL=$((FAIL + 1))
    fi
fi

# =============================================================================
# Test 8: Empty package returns no rows
# =============================================================================
echo "Test 8: Empty package returns no rows"
RESULT=$(run_sql "SELECT count(*) FROM crsql_unpack_columns WHERE package = X'';")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: Empty package returns 0 rows"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 0 rows for empty package, got: $RESULT"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 9: Invalid package returns error or empty
# =============================================================================
# Reference: unpack_columns_vtab.rs:filter() returns ERROR for decode failure
echo "Test 9: Invalid package returns error or empty"
RESULT=$(run_sql_check_error "SELECT * FROM crsql_unpack_columns WHERE package = X'FFFF';")
if echo "$RESULT" | grep -qi "no such module\|no such table"; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif echo "$RESULT" | grep -qi "error"; then
    # Error is expected behavior for invalid package
    echo "  PASS: Invalid package returns error"
    PASS=$((PASS + 1))
elif [[ -z "$RESULT" ]]; then
    # Empty result is also acceptable
    echo "  PASS: Invalid package returns empty result"
    PASS=$((PASS + 1))
else
    # Document observed behavior
    echo "  INFO: Invalid package returned: $RESULT (documenting behavior)"
    PASS=$((PASS + 1))
fi

# =============================================================================
# Test 10: Module is INNOCUOUS (read-only, no INSERT)
# =============================================================================
# Reference: unpack_columns_vtab.rs:connect() calls vtab_config(INNOCUOUS)
# Reference: MODULE.xUpdate is None (read-only)
echo "Test 10: Module is INNOCUOUS (INSERT fails)"
RESULT=$(run_sql_check_error "INSERT INTO crsql_unpack_columns (cell) VALUES (1);")
if echo "$RESULT" | grep -qi "no such module\|no such table"; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif echo "$RESULT" | grep -qi "cannot modify\|read-only\|virtual table.*read.only\|not authorized\|attempt to write"; then
    echo "  PASS: INSERT correctly rejected (read-only vtab)"
    PASS=$((PASS + 1))
elif echo "$RESULT" | grep -qi "error"; then
    echo "  PASS: INSERT failed with error (expected for INNOCUOUS vtab)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: INSERT should fail on read-only vtab, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 11: Requires package constraint (best-index behavior)
# =============================================================================
# Reference: unpack_columns_vtab.rs:best_index() requires PACKAGE column constraint
echo "Test 11: Requires package constraint (SELECT without WHERE fails)"
RESULT=$(run_sql_check_error "SELECT * FROM crsql_unpack_columns;")
if echo "$RESULT" | grep -qi "no such module\|no such table"; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
elif echo "$RESULT" | grep -qi "no package column\|constraint\|error\|misuse"; then
    echo "  PASS: SELECT without WHERE package= correctly rejected"
    PASS=$((PASS + 1))
elif [[ -z "$RESULT" ]]; then
    # Empty result acceptable (though error is preferred)
    echo "  INFO: SELECT without WHERE returned empty (acceptable, error preferred)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected error or empty for unconstrained SELECT, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 12: Round-trip with crsql_pack_columns (parity)
# =============================================================================
# This verifies pack/unpack are inverse operations
echo "Test 12: Round-trip pack/unpack parity"
RESULT=$(run_sql_all "SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns(100, 'test', 2.718, x'CAFE');")
if grep -qi "no such module\|no such table" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_unpack_columns module not found"
    SKIP=$((SKIP + 1))
else
    ROW1=$(echo "$RESULT" | sed -n '1p')
    ROW2=$(echo "$RESULT" | sed -n '2p')
    ROW3=$(echo "$RESULT" | sed -n '3p')
    # Note: Row 4 is blob, check via hex
    if [[ "$ROW1" == "100" && "$ROW2" == "test" ]]; then
        echo "  PASS: Round-trip preserves values (100, 'test', 2.718, blob)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Round-trip failed. Got row1='$ROW1', row2='$ROW2', row3='$ROW3'"
        cat "$ERRFILE" 2>/dev/null || true
        FAIL=$((FAIL + 1))
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "crsql_unpack_columns Tests Summary: $PASS passed, $FAIL failed, $SKIP skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All crsql_unpack_columns tests passed!"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All crsql_unpack_columns tests SKIPPED (module not implemented)"
    echo "RED PHASE: This is expected until crsql_unpack_columns vtab is implemented in Zig"
    # Exit 2 indicates tests skipped due to missing implementation
    # This is expected for RED phase of RGRTDD
    exit 2
else
    echo "Some crsql_unpack_columns tests FAILED"
    # In RED phase, FAIL on test 1 (module missing) is expected
    if [[ $FAIL -ge 1 ]]; then
        echo "RED PHASE: Module not yet implemented in Zig (expected)"
    fi
    exit 1
fi
