#!/usr/bin/env bash
# crsql_sha() Test Suite for Zig CR-SQLite
# Validates that crsql_sha() returns a git commit SHA string
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "================================================================"
echo "Test Suite: crsql_sha() function"
echo "================================================================"
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
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Extension not found at $ZIG_EXT"
    exit 1
fi

echo "Zig Extension: $ZIG_EXT"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0

# Helper to run SQL and get last line
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" "$sql" 2>&1 | tail -1 || true
}

# ================================================================
# Test 1: Function exists
# ================================================================
echo "Test 1: crsql_sha() exists"
result=$(run_sql "SELECT crsql_sha()")
echo "  Result: $result"
if [[ -n "$result" ]] && [[ "$result" != *"no such function"* ]]; then
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Function not found"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ================================================================
# Test 2: Returns a string (text type)
# ================================================================
echo "Test 2: crsql_sha() returns text type"
result=$(run_sql "SELECT typeof(crsql_sha())")
echo "  Type: $result"
if [[ "$result" == "text" ]]; then
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'text', got '$result'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ================================================================
# Test 3: Deterministic - same result every time
# ================================================================
echo "Test 3: crsql_sha() is deterministic"
result=$(run_sql "SELECT crsql_sha() = crsql_sha()")
echo "  Same result: $result"
if [[ "$result" == "1" ]]; then
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got '$result'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ================================================================
# Test 4: Returns non-empty string
# ================================================================
echo "Test 4: crsql_sha() returns non-empty string"
result=$(run_sql "SELECT length(crsql_sha()) > 0")
echo "  Has length: $result"
if [[ "$result" == "1" ]]; then
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got '$result'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ================================================================
# Test 5: No arguments required (error on args)
# ================================================================
echo "Test 5: crsql_sha() rejects arguments"
result=$(nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" "SELECT crsql_sha(1)" 2>&1 || true)
echo "  Result: $result"
if [[ "$result" == *"takes no arguments"* ]] || [[ "$result" == *"wrong number of arguments"* ]]; then
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected error about arguments, got '$result'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ================================================================
# Test 6: Oracle parity - function exists in both
# ================================================================
echo "Test 6: crsql_sha() oracle parity"
zig_result=$(run_sql "SELECT typeof(crsql_sha())")
rust_result=$(nix run github:subtleGradient/sqlite-cr -- :memory: "SELECT typeof(crsql_sha())" 2>/dev/null || echo "SKIP")
echo "  Zig type: $zig_result"
echo "  Rust type: $rust_result"
if [[ "$rust_result" == "SKIP" ]]; then
    echo "  SKIP: Oracle not available"
elif [[ "$zig_result" == "$rust_result" ]]; then
    echo "  PASS"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Type mismatch"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi
echo ""

# ================================================================
# Summary
# ================================================================
echo "================================================================"
echo "                        SUMMARY"
echo "================================================================"
echo "  PASSED: $TOTAL_PASS"
echo "  FAILED: $TOTAL_FAIL"
echo "================================================================"

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo "All tests PASSED"
    exit 0
else
    echo "Some tests FAILED"
    exit 1
fi
