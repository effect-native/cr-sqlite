#!/usr/bin/env bash
# is_crr Test Suite for Zig CR-SQLite
# Validates crsql_is_crr() detection from core/src/is-crr.test.c
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ZIG_DIR"

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    LIB="./zig-out/lib/libcrsqlite.dylib"
else
    LIB="./zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$LIB" ]]; then
    echo "Extension not found at $LIB, building..."
    nix run nixpkgs#zig -- build
fi

run_test() {
    local name="$1"
    local sql="$2"
    local expected="$3"
    echo -n "Testing $name... "
    result=$(nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>&1)
    if [ "$result" = "$expected" ]; then
        echo "PASS"
    else
        echo "FAIL"
        echo "  Expected: $expected"
        echo "  Got: $result"
        exit 1
    fi
}

# Test 1: Plain table is not CRR (testTableIsNotCrr)
run_test "tableIsNotCrr" \
    "CREATE TABLE foo (a PRIMARY KEY NOT NULL, b); SELECT crsql_is_crr('foo');" \
    "0"

# Test 2: After as_crr, table is CRR (testCrrIsCrr)
run_test "crrIsCrr" \
    "CREATE TABLE foo (a PRIMARY KEY NOT NULL, b); SELECT crsql_as_crr('foo'); SELECT crsql_is_crr('foo');" \
    "1"

# Test 3: After as_table, table is no longer CRR (testDestroyedCrrIsNotCrr)
run_test "destroyedCrrIsNotCrr" \
    "CREATE TABLE foo (a PRIMARY KEY NOT NULL, b); SELECT crsql_as_crr('foo'); SELECT crsql_as_table('foo'); SELECT crsql_is_crr('foo');" \
    "0"

echo "All is_crr tests passed!"
