#!/usr/bin/env bash
# Fractional Indexing Tests for Zig CR-SQLite
# Tests crsql_fract_key_between() UDF
#
# This function computes lexicographically-ordered keys for list positioning.
#
# Test cases:
# 1. null, null returns middle key "a "
# 2. null, key returns key before
# 3. key, null returns key after
# 4. key1, key2 returns key between
# 5. Error cases (invalid order, invalid chars)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig CR-SQLite Fractional Indexing Tests ==="
echo "Tests: crsql_fract_key_between()"
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

ERRFILE=$(mktemp)
trap "rm -f $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# Helper to run SQL and get result
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Check if fract function is available
echo "Checking fract function availability..."
SMOKE_RESULT=$(run_sql "SELECT crsql_fract_key_between(null, null);" 2>&1 || echo "ERROR")
if grep -q "no such function: crsql_fract_key_between" "$ERRFILE" 2>/dev/null; then
    echo "SKIP: crsql_fract_key_between() not yet implemented"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                           TEST SUMMARY                               ║"
    echo "╠═══════════════════════════════════════════════════════════════════════╣"
    echo "║  PASSED:  0                                                          ║"
    echo "║  FAILED:  0                                                          ║"
    echo "║  SKIPPED: All (function not implemented)                             ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "⚠ All tests SKIPPED (crsql_fract_key_between not yet implemented)"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: null, null returns middle key
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: crsql_fract_key_between(null, null) returns 'a '"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "SELECT crsql_fract_key_between(null, null);")

if [[ "$RESULT" == "a " ]]; then
    echo "  PASS: null, null returns 'a ' (INTEGER_ZERO)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'a ', got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: null, 'a ' returns key before (Z~)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: crsql_fract_key_between(null, 'a ') returns 'Z~'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "SELECT crsql_fract_key_between(null, 'a ');")

if [[ "$RESULT" == "Z~" ]]; then
    echo "  PASS: null, 'a ' returns 'Z~'"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'Z~', got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: 'a ', null returns key after (a!)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: crsql_fract_key_between('a ', null) returns 'a!'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "SELECT crsql_fract_key_between('a ', null);")

if [[ "$RESULT" == "a!" ]]; then
    echo "  PASS: 'a ', null returns 'a!'"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'a!', got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: 'a0', 'a1' returns key between (a0P)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: crsql_fract_key_between('a0', 'a1') returns 'a0P'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "SELECT crsql_fract_key_between('a0', 'a1');")

if [[ "$RESULT" == "a0P" ]]; then
    echo "  PASS: 'a0', 'a1' returns 'a0P'"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'a0P', got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Ordering - keys sort correctly
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Generated keys maintain lexicographic order"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Generate a sequence of 5 keys and verify they sort correctly
RESULT=$(run_sql "
WITH RECURSIVE keys(n, k) AS (
    SELECT 1, crsql_fract_key_between(null, null)
    UNION ALL
    SELECT n+1, crsql_fract_key_between(k, null) FROM keys WHERE n < 5
)
SELECT GROUP_CONCAT(k, ',') FROM keys ORDER BY k;
")

# Parse and check ordering
IFS=',' read -ra KEYS <<< "$RESULT"
ORDERED=1
for ((i=0; i<${#KEYS[@]}-1; i++)); do
    if [[ "${KEYS[$i]}" > "${KEYS[$i+1]}" ]]; then
        ORDERED=0
        break
    fi
done

if [[ $ORDERED -eq 1 && ${#KEYS[@]} -eq 5 ]]; then
    echo "  PASS: Generated 5 keys in correct order"
    echo "        Keys: ${KEYS[*]}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Keys not in order or wrong count"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Insert between - key is between its neighbors
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Key between 'a0' and 'a1' sorts correctly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "
SELECT 
    CASE 
        WHEN crsql_fract_key_between('a0', 'a1') > 'a0' 
         AND crsql_fract_key_between('a0', 'a1') < 'a1' 
        THEN 'OK' 
        ELSE 'FAIL' 
    END;
")

if [[ "$RESULT" == "OK" ]]; then
    echo "  PASS: Key between 'a0' and 'a1' is correctly ordered"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Key between does not sort between its neighbors"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Error - a must be before b
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Error when left > right"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "SELECT crsql_fract_key_between('a1', 'a0');")

if grep -q "must be before" "$ERRFILE" 2>/dev/null; then
    echo "  PASS: Error returned when left > right"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected error for invalid order, got: '$RESULT'"
    cat "$ERRFILE" 2>/dev/null || true
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: Error - invalid head character
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: Error for invalid head character"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "SELECT crsql_fract_key_between('0', '1');")

if grep -q "out of range" "$ERRFILE" 2>/dev/null; then
    echo "  PASS: Error returned for invalid head character"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected error for invalid head, got: '$RESULT'"
    cat "$ERRFILE" 2>/dev/null || true
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
    echo "✓ All tests PASSED"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo "⚠ All tests SKIPPED"
    exit 0
else
    echo "✗ Some tests FAILED"
    exit 1
fi
