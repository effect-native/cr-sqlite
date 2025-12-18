#!/usr/bin/env bash
# Oracle Parity Test: crsql_fract_key_between()
# Verifies Zig and Rust/C implementations produce byte-identical output
#
# TASK-091: Oracle Parity — Fractional index algorithm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Extension paths
RUST_EXT="$PROJECT_ROOT/lib/crsqlite.dylib"
ZIG_EXT="$PROJECT_ROOT/lib/crsqlite-zig-darwin-aarch64.dylib"

# Cache sqlite path to avoid repeated nix run overhead
SQLITE_PATH=$(nix build nixpkgs#sqlite --print-out-paths --no-link 2>/dev/null | grep -v man | head -1)
SQLITE_BIN="$SQLITE_PATH/bin/sqlite3"

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║       Fractional Index Oracle Parity Test                            ║"
echo "║  Compares Rust/C vs Zig implementation of crsql_fract_key_between    ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Check extensions exist
if [[ ! -f "$RUST_EXT" ]]; then
    echo "ERROR: Rust/C extension not found at $RUST_EXT"
    exit 1
fi
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "ERROR: Zig extension not found at $ZIG_EXT"
    exit 1
fi

echo "Rust/C extension: $RUST_EXT"
echo "Zig extension:    $ZIG_EXT"
echo "SQLite binary:    $SQLITE_BIN"
echo ""

ERRFILE=$(mktemp)
trap "rm -f $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0

# Helper to run SQL on an extension and return quoted result
run_sql_rust() {
    local sql="$1"
    "$SQLITE_BIN" :memory: -cmd ".load $RUST_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_sql_zig() {
    local sql="$1"
    "$SQLITE_BIN" :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to get hex dump of result
get_hex_rust() {
    local sql="$1"
    "$SQLITE_BIN" :memory: -cmd ".load $RUST_EXT" "SELECT hex(crsql_fract_key_between($sql));" 2>/dev/null | tail -1 || echo "ERROR"
}

get_hex_zig() {
    local sql="$1"
    "$SQLITE_BIN" :memory: -cmd ".load $ZIG_EXT" "SELECT hex(crsql_fract_key_between($sql));" 2>/dev/null | tail -1 || echo "ERROR"
}

# Run a parity test
# Args: test_name, sql_args (for crsql_fract_key_between)
run_parity_test() {
    local test_name="$1"
    local sql_args="$2"
    local expected_ordering="$3"  # "a<r<b", "r>a", "r<b", "none"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: $test_name"
    echo "Input: crsql_fract_key_between($sql_args)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local rust_hex=$(get_hex_rust "$sql_args")
    local zig_hex=$(get_hex_zig "$sql_args")
    local rust_val=$(run_sql_rust "SELECT quote(crsql_fract_key_between($sql_args));")
    local zig_val=$(run_sql_zig "SELECT quote(crsql_fract_key_between($sql_args));")
    
    echo "  Rust/C: $rust_val (hex: $rust_hex)"
    echo "  Zig:    $zig_val (hex: $zig_hex)"
    
    # Check byte-identical
    if [[ "$rust_hex" == "$zig_hex" ]]; then
        echo "  ✓ Byte-identical: YES"
        
        # Check lexicographic ordering if applicable
        if [[ "$expected_ordering" == "a<r<b" ]]; then
            local order_check=$(run_sql_zig "
                SELECT CASE 
                    WHEN crsql_fract_key_between($sql_args) > (SELECT $sql_args LIMIT 1 OFFSET 0)
                     AND crsql_fract_key_between($sql_args) < (SELECT $sql_args LIMIT 1 OFFSET 1)
                    THEN 'OK' ELSE 'FAIL' END;
            " 2>/dev/null || echo "SKIP")
            # Simpler ordering check using direct comparison
            local a_val=$(echo "$sql_args" | cut -d',' -f1 | tr -d "' ")
            local b_val=$(echo "$sql_args" | cut -d',' -f2 | tr -d "' ")
            local result_val=$(run_sql_zig "SELECT crsql_fract_key_between($sql_args);")
            order_check=$(run_sql_zig "SELECT CASE WHEN '$result_val' > '$a_val' AND '$result_val' < '$b_val' THEN 'OK' ELSE 'FAIL' END;")
            if [[ "$order_check" == "OK" ]]; then
                echo "  ✓ Ordering: a < result < b"
            else
                echo "  ✗ Ordering FAIL: expected a < result < b"
                TOTAL_FAIL=$((TOTAL_FAIL + 1))
                return
            fi
        fi
        
        echo "  PASS"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  ✗ Byte-identical: NO - DIVERGENCE DETECTED!"
        echo "  FAIL"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# Test Cases
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "Running parity tests..."
echo ""

# Test 1: (NULL, NULL) — first key
run_parity_test "(NULL, NULL) — first key" "null, null" "none"

# Test 2: ('a ', NULL) — key after 'a '
run_parity_test "('a ', NULL) — key after 'a '" "'a ', null" "none"

# Test 3: (NULL, 'a ') — key before 'a '
run_parity_test "(NULL, 'a ') — key before 'a '" "null, 'a '" "none"

# Test 4: ('a0', 'a1') — key between
run_parity_test "('a0', 'a1') — key between" "'a0', 'a1'" "a<r<b"

# Test 5: ('aaa', 'aab') — close values
run_parity_test "('aaa', 'aab') — close values" "'aaa', 'aab'" "a<r<b"

# Test 6: ('a0P', 'a0Q') — very close values
run_parity_test "('a0P', 'a0Q') — very close values" "'a0P', 'a0Q'" "a<r<b"

# Test 7: Long string (100+ chars)
LONG_KEY="a$(printf 'P%.0s' {1..100})"
run_parity_test "Long string (101 chars)" "'$LONG_KEY', null" "none"

# Test 8: Negative integer region
run_parity_test "(NULL, 'Z~') — negative integer" "null, 'Z~'" "none"

# Test 9: Decrementing from Z~
run_parity_test "('Z}', 'Z~') — between negative integers" "'Z}', 'Z~'" "a<r<b"

# Test 10: Multiple insertions - generate sequence and verify ordering
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test: Sequential key generation maintains ordering"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RUST_SEQ=$(run_sql_rust "
WITH RECURSIVE keys(n, k) AS (
    SELECT 1, crsql_fract_key_between(null, null)
    UNION ALL
    SELECT n+1, crsql_fract_key_between(k, null) FROM keys WHERE n < 5
)
SELECT GROUP_CONCAT(hex(k), ',') FROM keys ORDER BY k;
")

ZIG_SEQ=$(run_sql_zig "
WITH RECURSIVE keys(n, k) AS (
    SELECT 1, crsql_fract_key_between(null, null)
    UNION ALL
    SELECT n+1, crsql_fract_key_between(k, null) FROM keys WHERE n < 5
)
SELECT GROUP_CONCAT(hex(k), ',') FROM keys ORDER BY k;
")

echo "  Rust/C sequence (hex): $RUST_SEQ"
echo "  Zig sequence (hex):    $ZIG_SEQ"

if [[ "$RUST_SEQ" == "$ZIG_SEQ" ]]; then
    echo "  ✓ Byte-identical: YES"
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  ✗ Byte-identical: NO - DIVERGENCE DETECTED!"
    echo "  FAIL"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Error case parity - both should reject invalid inputs
# Note: Error message format may differ, but both should not produce valid output
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test: Error case parity - empty string"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get the actual value (not error message)
RUST_VAL=$("$SQLITE_BIN" :memory: -cmd ".load $RUST_EXT" "SELECT quote(crsql_fract_key_between('', 'a '));" 2>/dev/null | tail -1 || echo "ERROR")
ZIG_VAL=$("$SQLITE_BIN" :memory: -cmd ".load $ZIG_EXT" "SELECT quote(crsql_fract_key_between('', 'a '));" 2>/dev/null | tail -1 || echo "ERROR")
# Also capture stderr
RUST_ERR=$("$SQLITE_BIN" :memory: -cmd ".load $RUST_EXT" "SELECT crsql_fract_key_between('', 'a ');" 2>&1 | tail -1 || echo "")
ZIG_ERR=$("$SQLITE_BIN" :memory: -cmd ".load $ZIG_EXT" "SELECT crsql_fract_key_between('', 'a ');" 2>&1 | tail -1 || echo "")

echo "  Rust/C value: $RUST_VAL"
echo "  Zig value:    $ZIG_VAL"
echo "  Rust/C msg:   ${RUST_ERR:-<empty>}"
echo "  Zig msg:      ${ZIG_ERR:-<empty>}"

# Both should either error or return NULL (not a valid key)
RUST_INVALID=0
ZIG_INVALID=0
if [[ "$RUST_VAL" == "NULL" || "$RUST_VAL" == "ERROR" || -z "$RUST_VAL" || "$RUST_ERR" == *"rror"* ]]; then
    RUST_INVALID=1
fi
if [[ "$ZIG_VAL" == "NULL" || "$ZIG_VAL" == "ERROR" || -z "$ZIG_VAL" || "$ZIG_ERR" == *"rror"* ]]; then
    ZIG_INVALID=1
fi

if [[ $RUST_INVALID -eq 1 && $ZIG_INVALID -eq 1 ]]; then
    echo "  ✓ Both reject invalid input (empty string)"
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  ✗ Error handling differs"
    echo "  FAIL"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test: Error case parity - a > b (invalid order)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RUST_ERR=$("$SQLITE_BIN" :memory: -cmd ".load $RUST_EXT" "SELECT crsql_fract_key_between('a1', 'a0');" 2>&1 | tail -1 || echo "")
ZIG_ERR=$("$SQLITE_BIN" :memory: -cmd ".load $ZIG_EXT" "SELECT crsql_fract_key_between('a1', 'a0');" 2>&1 | tail -1 || echo "")

echo "  Rust/C: $RUST_ERR"
echo "  Zig:    $ZIG_ERR"

if [[ "$RUST_ERR" == *"error"* || "$RUST_ERR" == *"Error"* || "$RUST_ERR" == *"must be before"* ]] && \
   [[ "$ZIG_ERR" == *"error"* || "$ZIG_ERR" == *"Error"* || "$ZIG_ERR" == *"must be before"* ]]; then
    echo "  ✓ Both produce error on invalid order"
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  ✗ Error handling differs"
    echo "  FAIL"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                     PARITY TEST SUMMARY                              ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$TOTAL_PASS"
printf "║  FAILED:  %-58d ║\n" "$TOTAL_FAIL"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo "✓ All parity tests PASSED - Zig and Rust/C are byte-identical"
    exit 0
else
    echo "✗ PARITY FAILURE - Zig and Rust/C produce different outputs!"
    exit 1
fi
