#!/usr/bin/env bash
# Oracle Parity Test: crsql_get_seq() function
#
# Tests the crsql_get_seq() function which returns the current seq value
# without incrementing it. This is a read-only version of crsql_increment_and_get_seq().
#
# Used by sync clients to observe the current seq without side effects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Oracle Parity Test: crsql_get_seq() function"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Check for Rust/C oracle
HAVE_ORACLE=true
if [[ ! -f "$RUST_EXT" ]]; then
    echo "NOTE: Rust/C oracle not found at $RUST_EXT"
    echo "      Oracle parity tests will be skipped"
    HAVE_ORACLE=false
fi

# Check for Zig extension
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Zig extension not found at $ZIG_EXT"
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

SQLITE="nix run nixpkgs#sqlite --"

echo "Zig extension: $ZIG_EXT"
if [[ "$HAVE_ORACLE" == "true" ]]; then
    echo "Rust/C oracle: $RUST_EXT"
fi
echo ""

# Temp files for output
TMPDIR="${REPO_ROOT}/.tmp"
mkdir -p "$TMPDIR"
RUST_OUT=$(mktemp "$TMPDIR/get-seq-rust.XXXXXX")
ZIG_OUT=$(mktemp "$TMPDIR/get-seq-zig.XXXXXX")
ERRFILE=$(mktemp "$TMPDIR/get-seq-err.XXXXXX")
trap "rm -f $RUST_OUT $ZIG_OUT $ERRFILE" EXIT

PASS=0
FAIL=0
SKIP=0

# Helper to run SQL
run_zig() {
    local sql="$1"
    $SQLITE :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE"
}

run_rust() {
    local sql="$1"
    $SQLITE :memory: -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE"
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: crsql_get_seq() exists and returns 0 initially
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 1: crsql_get_seq() exists and returns 0 initially"
result=$(run_zig "SELECT crsql_get_seq();" 2>&1) || true
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: crsql_get_seq() function not found in Zig extension"
    FAIL=$((FAIL + 1))
elif [[ "$result" == "0" ]]; then
    echo "  PASS: crsql_get_seq() returns 0 initially"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 0, got: $result"
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Multiple calls return same value (no increment)
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 2: Multiple calls return same value (no increment)"
result=$(run_zig "SELECT crsql_get_seq(); SELECT crsql_get_seq(); SELECT crsql_get_seq();") || true
# All three should be 0
count_zeros=$(echo "$result" | grep -c "^0$" || echo "0")
if [[ "$count_zeros" == "3" ]]; then
    echo "  PASS: crsql_get_seq() returns 0 three times without incrementing"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected three 0s, got: $result"
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: crsql_get_seq() matches crsql_increment_and_get_seq() before increment
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 3: crsql_get_seq() matches crsql_increment_and_get_seq() before increment"
result=$(run_zig "
SELECT 'BEFORE=' || (crsql_get_seq() = 0);
SELECT 'INCR=' || crsql_increment_and_get_seq();
SELECT 'AFTER=' || (crsql_get_seq() = 1);
SELECT 'INCR2=' || crsql_increment_and_get_seq();
SELECT 'AFTER2=' || (crsql_get_seq() = 2);
") || true

before=$(echo "$result" | grep "BEFORE=" | cut -d= -f2)
after=$(echo "$result" | grep "^AFTER=" | cut -d= -f2)
after2=$(echo "$result" | grep "AFTER2=" | cut -d= -f2)

if [[ "$before" == "1" && "$after" == "1" && "$after2" == "1" ]]; then
    echo "  PASS: crsql_get_seq() correctly reflects seq after increment_and_get_seq()"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected all 1s (true), got: before=$before after=$after after2=$after2"
    echo "  Full result: $result"
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: crsql_get_seq() takes no arguments
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 4: crsql_get_seq() takes no arguments"
result=$(run_zig "SELECT crsql_get_seq(1);" 2>&1) || true
# SQLite itself may reject the wrong number of arguments before our function runs
if grep -qi "wrong number of arguments\|takes no arguments" "$ERRFILE" 2>/dev/null; then
    echo "  PASS: crsql_get_seq() correctly rejects arguments"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected error about wrong number of arguments, got: $result"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Oracle parity (if available)
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 5: Oracle parity"
if [[ "$HAVE_ORACLE" == "true" ]]; then
    zig_result=$(run_zig "SELECT crsql_get_seq();") || true
    rust_result=$(run_rust "SELECT crsql_get_seq();") || true
    
    if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  SKIP: crsql_get_seq() not available in Rust/C oracle"
        SKIP=$((SKIP + 1))
    elif [[ "$zig_result" == "$rust_result" ]]; then
        echo "  PASS: Zig ($zig_result) matches Rust/C oracle ($rust_result)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Zig ($zig_result) != Rust/C oracle ($rust_result)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SKIP: Rust/C oracle not available"
    SKIP=$((SKIP + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Oracle parity - seq after operations
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 6: Oracle parity - seq behavior after operations"
if [[ "$HAVE_ORACLE" == "true" ]]; then
    SQL="
SELECT 'GET1=' || crsql_get_seq();
SELECT 'INCR1=' || crsql_increment_and_get_seq();
SELECT 'GET2=' || crsql_get_seq();
SELECT 'INCR2=' || crsql_increment_and_get_seq();
SELECT 'GET3=' || crsql_get_seq();
"
    zig_result=$(run_zig "$SQL") || true
    rust_result=$(run_rust "$SQL" 2>/dev/null) || true
    
    if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  SKIP: crsql_get_seq() not available in Rust/C oracle"
        SKIP=$((SKIP + 1))
    elif [[ "$zig_result" == "$rust_result" ]]; then
        echo "  PASS: Zig matches Rust/C oracle for seq operations"
        echo "  Zig:   $(echo "$zig_result" | tr '\n' ' ')"
        echo "  Rust:  $(echo "$rust_result" | tr '\n' ' ')"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Zig != Rust/C oracle"
        echo "  Zig:   $(echo "$zig_result" | tr '\n' ' ')"
        echo "  Rust:  $(echo "$rust_result" | tr '\n' ' ')"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SKIP: Rust/C oracle not available"
    SKIP=$((SKIP + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "crsql_get_seq() Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  PASSED:  %d\n" "$PASS"
printf "  FAILED:  %d\n" "$FAIL"
printf "  SKIPPED: %d\n" "$SKIP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "FAIL: Some crsql_get_seq() tests failed"
    exit 1
elif [[ $PASS -gt 0 ]]; then
    echo "SUCCESS: All crsql_get_seq() tests passed"
    exit 0
else
    echo "No tests ran successfully"
    exit 2
fi
