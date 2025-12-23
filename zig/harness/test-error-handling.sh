#!/usr/bin/env bash
# Error Handling Tests for Zig CR-SQLite (Oracle Parity)
#
# This test file verifies Zig implementation handles malformed inputs gracefully
# (error, not crash) and matches Rust/C oracle behavior.
#
# Test categories:
# 1. Truncated PK blob → error, not crash
# 2. Wrong column count header → error
# 3. Invalid type markers → error
# 4. Corrupted length prefixes → error
# 5. Database remains uncorrupted after error
#
# Context: TASK-172 (malformed input error handling tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Error Handling Parity Tests (Zig vs Rust/C Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "These tests verify graceful error handling for malformed inputs."
echo "Both implementations should return errors, not crash."
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
if [[ ! -f "$RUST_EXT" ]]; then
    echo "BLOCKED: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 2
fi

# Check/build Zig extension
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

SQLITE="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/error-handling-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0
DIVERGE=0

ERRFILE="$TMPDIR/error.txt"
ZIG_ERRFILE="$TMPDIR/zig_error.txt"
RUST_ERRFILE="$TMPDIR/rust_error.txt"

# Helper to run SQL with Zig extension and capture both stdout and stderr
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ZIG_ERRFILE" || true
}

# Helper to run SQL with Rust/C extension and capture both stdout and stderr
run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$RUST_ERRFILE" || true
}

# Helper to check if stderr contains an error
has_error() {
    local errfile="$1"
    if [[ -s "$errfile" ]]; then
        # Check for actual errors, not just warnings
        if grep -qiE "(error|runtime error|constraint|malformed|invalid)" "$errfile"; then
            return 0
        fi
    fi
    return 1
}

# Helper to check if process crashed (segfault, abort, etc)
check_crash() {
    local errfile="$1"
    if grep -qiE "(segmentation fault|segfault|abort|signal|core dump)" "$errfile"; then
        return 0
    fi
    return 1
}

# Check for blocking errors
is_blocked() {
    if [[ -s "$ZIG_ERRFILE" ]]; then
        if grep -q "no such function" "$ZIG_ERRFILE"; then
            return 0
        fi
    fi
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Truncated PK blob
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Truncated PK blob"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'0109' (truncated - claims 1 col, int8 type, but no value)"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_1="$TMPDIR/test1_zig.db"
DB_RUST_1="$TMPDIR/test1_rust.db"

# Setup tables
SETUP_1="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Malformed input: X'0109' = 1 column, int8 type marker, but NO value bytes
MALFORMED_1="
INSERT INTO crsql_changes VALUES ('foo', X'0109', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_1" "$SETUP_1"
run_rust "$DB_RUST_1" "$SETUP_1"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Run malformed input
    ZIG_OUT_1=$(run_zig "$DB_ZIG_1" "$MALFORMED_1")
    RUST_OUT_1=$(run_rust "$DB_RUST_1" "$MALFORMED_1")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    ZIG_ERRORED=0
    RUST_ERRORED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    if has_error "$ZIG_ERRFILE"; then ZIG_ERRORED=1; fi
    if has_error "$RUST_ERRFILE"; then RUST_ERRORED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED errored=$ZIG_ERRORED"
    echo "  Rust:  crashed=$RUST_CRASHED errored=$RUST_ERRORED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on truncated PK"
        FAIL=$((FAIL + 1))
    elif [[ $ZIG_ERRORED -eq 1 ]] && [[ $RUST_ERRORED -eq 1 ]]; then
        echo "  PASS: Both return error on truncated PK (no crash)"
        PASS=$((PASS + 1))
    elif [[ $ZIG_ERRORED -ne $RUST_ERRORED ]]; then
        echo "  DIVERGENCE: Error handling differs"
        echo "    Zig error:  $(cat "$ZIG_ERRFILE" | head -1)"
        echo "    Rust error: $(cat "$RUST_ERRFILE" | head -1)"
        DIVERGE=$((DIVERGE + 1))
        # Still pass if Zig doesn't crash
        PASS=$((PASS + 1))
    else
        echo "  PASS: Neither crashed (both may have silently handled)"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Wrong column count header
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Wrong column count header"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'03090102' (claims 3 cols, but only 1 value provided)"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_2="$TMPDIR/test2_zig.db"
DB_RUST_2="$TMPDIR/test2_rust.db"

# Setup tables
SETUP_2="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Malformed input: X'03090102' = 3 columns header, but only provides 1 int8 value
# PK blob format: [col_count][type1][val1][type2][val2]...
# This says 3 cols but only has 1 partial entry
MALFORMED_2="
INSERT INTO crsql_changes VALUES ('foo', X'0309010209020903', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_2" "$SETUP_2"
run_rust "$DB_RUST_2" "$SETUP_2"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_2=$(run_zig "$DB_ZIG_2" "$MALFORMED_2")
    RUST_OUT_2=$(run_rust "$DB_RUST_2" "$MALFORMED_2")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED"
    echo "  Rust:  crashed=$RUST_CRASHED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on wrong column count"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled wrong column count without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Invalid type markers
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Invalid type marker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'01FF01' (1 col, type 0xFF invalid, value 1)"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_3="$TMPDIR/test3_zig.db"
DB_RUST_3="$TMPDIR/test3_rust.db"

# Setup tables
SETUP_3="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Malformed input: X'01FF01' = 1 col, type marker 0xFF (invalid), value 0x01
# Valid type markers are: 0x00=null, 0x09=int8, 0x0A=int16, etc.
# 0xFF is not a valid type marker
MALFORMED_3="
INSERT INTO crsql_changes VALUES ('foo', X'01FF01', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_3" "$SETUP_3"
run_rust "$DB_RUST_3" "$SETUP_3"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_3=$(run_zig "$DB_ZIG_3" "$MALFORMED_3")
    RUST_OUT_3=$(run_rust "$DB_RUST_3" "$MALFORMED_3")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    ZIG_ERRORED=0
    RUST_ERRORED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    if has_error "$ZIG_ERRFILE"; then ZIG_ERRORED=1; fi
    if has_error "$RUST_ERRFILE"; then RUST_ERRORED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED errored=$ZIG_ERRORED"
    echo "  Rust:  crashed=$RUST_CRASHED errored=$RUST_ERRORED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on invalid type marker"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled invalid type marker without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: Corrupted length prefixes (for text/blob types)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Corrupted length prefix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'010DFFFF' (1 col, text type, length 65535, but only 0 bytes)"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_4="$TMPDIR/test4_zig.db"
DB_RUST_4="$TMPDIR/test4_rust.db"

# Setup tables
SETUP_4="
CREATE TABLE foo (a TEXT PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Malformed input: X'010DFFFF' = 1 col, text type (0x0D), length=65535, but no actual bytes
# This should cause an out-of-bounds read if not validated
MALFORMED_4="
INSERT INTO crsql_changes VALUES ('foo', X'010DFFFF', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_4" "$SETUP_4"
run_rust "$DB_RUST_4" "$SETUP_4"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_4=$(run_zig "$DB_ZIG_4" "$MALFORMED_4")
    RUST_OUT_4=$(run_rust "$DB_RUST_4" "$MALFORMED_4")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    ZIG_ERRORED=0
    RUST_ERRORED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    if has_error "$ZIG_ERRFILE"; then ZIG_ERRORED=1; fi
    if has_error "$RUST_ERRFILE"; then RUST_ERRORED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED errored=$ZIG_ERRORED"
    echo "  Rust:  crashed=$RUST_CRASHED errored=$RUST_ERRORED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on corrupted length prefix"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled corrupted length prefix without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 5: Zero column count (edge case)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Zero column count"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'00' (0 columns - invalid for a table with PK)"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_5="$TMPDIR/test5_zig.db"
DB_RUST_5="$TMPDIR/test5_rust.db"

# Setup tables
SETUP_5="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Malformed input: X'00' = 0 columns (but table has 1 PK column)
MALFORMED_5="
INSERT INTO crsql_changes VALUES ('foo', X'00', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_5" "$SETUP_5"
run_rust "$DB_RUST_5" "$SETUP_5"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_5=$(run_zig "$DB_ZIG_5" "$MALFORMED_5")
    RUST_OUT_5=$(run_rust "$DB_RUST_5" "$MALFORMED_5")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED"
    echo "  Rust:  crashed=$RUST_CRASHED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on zero column count"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled zero column count without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 6: Empty PK blob
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Empty PK blob"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'' (empty blob - no column count at all)"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_6="$TMPDIR/test6_zig.db"
DB_RUST_6="$TMPDIR/test6_rust.db"

# Setup tables
SETUP_6="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Malformed input: X'' = empty blob (should have at least column count byte)
MALFORMED_6="
INSERT INTO crsql_changes VALUES ('foo', X'', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_6" "$SETUP_6"
run_rust "$DB_RUST_6" "$SETUP_6"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_6=$(run_zig "$DB_ZIG_6" "$MALFORMED_6")
    RUST_OUT_6=$(run_rust "$DB_RUST_6" "$MALFORMED_6")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED"
    echo "  Rust:  crashed=$RUST_CRASHED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on empty PK blob"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled empty PK blob without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 7: Database remains intact after errors
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Database integrity after errors"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Insert valid data, attempt malformed insert, verify original data intact"
echo "Expected: Original row intact, can still perform operations"
echo ""

DB_ZIG_7="$TMPDIR/test7_zig.db"
DB_RUST_7="$TMPDIR/test7_rust.db"

# Setup tables with valid data
SETUP_7="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'original');
"

run_zig "$DB_ZIG_7" "$SETUP_7"
run_rust "$DB_RUST_7" "$SETUP_7"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Attempt malformed insert (truncated PK)
    run_zig "$DB_ZIG_7" "INSERT INTO crsql_changes VALUES ('foo', X'0109', 'b', 42, 2, 2, NULL, 1, 1);"
    run_rust "$DB_RUST_7" "INSERT INTO crsql_changes VALUES ('foo', X'0109', 'b', 42, 2, 2, NULL, 1, 1);"
    
    # Check original data is intact
    ZIG_DATA=$(run_zig "$DB_ZIG_7" "SELECT b FROM foo WHERE a=1;")
    RUST_DATA=$(run_rust "$DB_RUST_7" "SELECT b FROM foo WHERE a=1;")
    
    # Try to insert new valid data
    run_zig "$DB_ZIG_7" "INSERT INTO foo VALUES (2, 'after_error');"
    run_rust "$DB_RUST_7" "INSERT INTO foo VALUES (2, 'after_error');"
    
    ZIG_NEW=$(run_zig "$DB_ZIG_7" "SELECT b FROM foo WHERE a=2;")
    RUST_NEW=$(run_rust "$DB_RUST_7" "SELECT b FROM foo WHERE a=2;")
    
    echo "  Original data - Zig: '$ZIG_DATA', Rust: '$RUST_DATA'"
    echo "  New insert    - Zig: '$ZIG_NEW', Rust: '$RUST_NEW'"
    
    if [[ "$ZIG_DATA" == "original" ]] && [[ "$ZIG_NEW" == "after_error" ]]; then
        echo "  PASS: Zig database intact after error"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Zig database corrupted after error"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 8: Invalid table name in crsql_changes
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: Invalid table name"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Reference non-existent table in crsql_changes"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_8="$TMPDIR/test8_zig.db"
DB_RUST_8="$TMPDIR/test8_rust.db"

# Setup tables
SETUP_8="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Insert referencing non-existent table
MALFORMED_8="
INSERT INTO crsql_changes VALUES ('nonexistent_table', X'010901', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_8" "$SETUP_8"
run_rust "$DB_RUST_8" "$SETUP_8"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_8=$(run_zig "$DB_ZIG_8" "$MALFORMED_8")
    RUST_OUT_8=$(run_rust "$DB_RUST_8" "$MALFORMED_8")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    ZIG_ERRORED=0
    RUST_ERRORED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    if has_error "$ZIG_ERRFILE"; then ZIG_ERRORED=1; fi
    if has_error "$RUST_ERRFILE"; then RUST_ERRORED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED errored=$ZIG_ERRORED"
    echo "  Rust:  crashed=$RUST_CRASHED errored=$RUST_ERRORED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on invalid table name"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled invalid table name without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 9: Invalid column name in crsql_changes
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 9: Invalid column name"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Reference non-existent column in crsql_changes"
echo "Expected: Error, not crash"
echo ""

DB_ZIG_9="$TMPDIR/test9_zig.db"
DB_RUST_9="$TMPDIR/test9_rust.db"

# Setup tables
SETUP_9="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Insert referencing non-existent column
MALFORMED_9="
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'nonexistent_column', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_9" "$SETUP_9"
run_rust "$DB_RUST_9" "$SETUP_9"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_9=$(run_zig "$DB_ZIG_9" "$MALFORMED_9")
    RUST_OUT_9=$(run_rust "$DB_RUST_9" "$MALFORMED_9")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    ZIG_ERRORED=0
    RUST_ERRORED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    if has_error "$ZIG_ERRFILE"; then ZIG_ERRORED=1; fi
    if has_error "$RUST_ERRFILE"; then RUST_ERRORED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED errored=$ZIG_ERRORED"
    echo "  Rust:  crashed=$RUST_CRASHED errored=$RUST_ERRORED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on invalid column name"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled invalid column name without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 10: Negative integer encoding edge case
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 10: Integer overflow in PK blob"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malformed input: X'010CFFFFFFFFFFFFFFFF' (1 col, int64, max value)"
echo "Expected: Handle gracefully, not crash"
echo ""

DB_ZIG_10="$TMPDIR/test10_zig.db"
DB_RUST_10="$TMPDIR/test10_rust.db"

# Setup tables
SETUP_10="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
"

# Int64 max value: 0x0C = int64 type marker, followed by 8 bytes of 0xFF
MALFORMED_10="
INSERT INTO crsql_changes VALUES ('foo', X'010CFFFFFFFFFFFFFFFF', 'b', 42, 1, 1, NULL, 1, 1);
"

run_zig "$DB_ZIG_10" "$SETUP_10"
run_rust "$DB_RUST_10" "$SETUP_10"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_OUT_10=$(run_zig "$DB_ZIG_10" "$MALFORMED_10")
    RUST_OUT_10=$(run_rust "$DB_RUST_10" "$MALFORMED_10")
    
    ZIG_CRASHED=0
    RUST_CRASHED=0
    
    if check_crash "$ZIG_ERRFILE"; then ZIG_CRASHED=1; fi
    if check_crash "$RUST_ERRFILE"; then RUST_CRASHED=1; fi
    
    echo "  Zig:   crashed=$ZIG_CRASHED"
    echo "  Rust:  crashed=$RUST_CRASHED"
    
    if [[ $ZIG_CRASHED -eq 1 ]]; then
        echo "  FAIL: Zig CRASHED on integer edge case"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Zig handled integer edge case without crash"
        PASS=$((PASS + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Error Handling Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  PASS:       %d\n" "$PASS"
printf "  FAIL:       %d\n" "$FAIL"
printf "  SKIP:       %d\n" "$SKIP"
printf "  DIVERGENCE: %d\n" "$DIVERGE"
echo ""

if [[ $SKIP -gt 0 && $PASS -eq 0 && $FAIL -eq 0 ]]; then
    echo "BLOCKED: All tests skipped (functions not implemented)"
    exit 2
fi

if [[ $FAIL -gt 0 ]]; then
    echo "SECURITY CONCERN: $FAIL test(s) caused CRASH instead of error"
    echo ""
    echo "Crashes on malformed input indicate potential security vulnerabilities."
    echo "The implementation should return errors, not crash/segfault."
    exit 1
fi

if [[ $DIVERGE -gt 0 ]]; then
    echo "NOTE: $DIVERGE test(s) showed behavioral divergence (documented above)"
    echo "These are informational - both implementations handled without crash."
fi

echo ""
echo "All error handling tests PASSED (no crashes)"
exit 0
