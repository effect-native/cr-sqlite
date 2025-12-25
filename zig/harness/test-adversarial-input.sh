#!/usr/bin/env bash
# Adversarial Input Fuzzing Tests for Zig CR-SQLite (TASK-195)
#
# This test suite feeds malformed/adversarial inputs to crsql_changes
# to find divergent error handling between Zig and Rust/C implementations.
#
# FINDINGS SUMMARY:
# =================
# CRASHES (Rust/C only):
#   - A3: Empty PK blob (X'') - SIGTRAP
#   - A7: NULL PK blob       - SIGTRAP
#
# DIVERGENCES (different behavior, no crash):
#   - B5: Oversized site_id (32 bytes) - Zig accepts, Rust rejects
#
# PARITY (both error or both succeed):
#   - A1: Truncated PK       - both error
#   - A2: Wrong col count    - both error  
#   - A4: Zero col count     - both handle gracefully
#   - A5: Invalid type       - both error
#   - A6: Corrupt length     - both accept (!)
#   - B1-B4, B6: Metadata    - both accept
#   - C1-C6: Invalid names   - both error
#   - D1-D7: Edge cases      - mostly parity
#
# Context: TASK-195 (adversarial input fuzzing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Adversarial Input Fuzzing Tests (Zig vs Rust/C Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Goal: Verify Zig handles malformed inputs gracefully (no crashes)."
echo "      Compare error handling with Rust/C oracle for parity."
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

# Check for Zig extension
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "BLOCKED: Zig extension not found at $ZIG_EXT"
    echo "Run: cd zig && zig build"
    exit 2
fi

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/adversarial-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0
DIVERGE=0
RUST_CRASH=0
ZIG_CRASH=0

# SQLITE command (use nix for proper extension loading support)
run_sql() {
    local ext="$1"
    local db="$2"
    local sql="$3"
    local init_func=""
    
    # Rust extension needs explicit init function
    if [[ "$ext" == "$RUST_EXT" ]]; then
        init_func="sqlite3_crsqlite_init"
    fi
    
    set +e
    if [[ -n "$init_func" ]]; then
        output=$(timeout 10s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ext $init_func" "$sql" 2>&1)
    else
        output=$(timeout 10s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ext" "$sql" 2>&1)
    fi
    local exit_code=$?
    set -e
    
    echo "$output"
    return $exit_code
}

# Test a single adversarial input
test_adversarial() {
    local name="$1"
    local malformed_sql="$2"
    local setup_sql="${3:-CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b); SELECT crsql_as_crr('foo');}"
    
    local db_zig="$TMPDIR/${name}_zig.db"
    local db_rust="$TMPDIR/${name}_rust.db"
    rm -f "$db_zig" "$db_rust"
    
    # Run Zig
    local zig_out zig_exit
    set +e
    zig_out=$(run_sql "$ZIG_EXT" "$db_zig" "$setup_sql $malformed_sql" 2>&1)
    zig_exit=$?
    set -e
    
    # Run Rust
    local rust_out rust_exit
    set +e
    rust_out=$(run_sql "$RUST_EXT" "$db_rust" "$setup_sql $malformed_sql" 2>&1)
    rust_exit=$?
    set -e
    
    # Check for errors in output
    local zig_errored=0
    local rust_errored=0
    if echo "$zig_out" | grep -qiE "^Error:" 2>/dev/null; then
        zig_errored=1
    fi
    if echo "$rust_out" | grep -qiE "^Error:" 2>/dev/null; then
        rust_errored=1
    fi
    
    # Analyze results
    local result=""
    local zig_status=""
    local rust_status=""
    
    # Check Zig crash
    if [[ $zig_exit -ge 128 ]]; then
        zig_status="CRASH(signal $((zig_exit - 128)))"
        ZIG_CRASH=$((ZIG_CRASH + 1))
    elif [[ $zig_exit -ne 0 || $zig_errored -eq 1 ]]; then
        zig_status="ERROR"
    else
        zig_status="OK"
    fi
    
    # Check Rust crash
    if [[ $rust_exit -ge 128 ]]; then
        rust_status="CRASH(signal $((rust_exit - 128)))"
        RUST_CRASH=$((RUST_CRASH + 1))
    elif [[ $rust_exit -ne 0 || $rust_errored -eq 1 ]]; then
        rust_status="ERROR"
    else
        rust_status="OK"
    fi
    
    # Determine test result
    if [[ "$zig_status" == "CRASH"* ]]; then
        result="FAIL"
        FAIL=$((FAIL + 1))
    elif [[ "$rust_status" == "CRASH"* ]]; then
        # Rust crashed but Zig didn't - this is actually good for Zig
        result="PASS (Rust crashed, Zig handled gracefully)"
        PASS=$((PASS + 1))
    elif [[ "$zig_status" == "$rust_status" ]]; then
        result="PASS (parity)"
        PASS=$((PASS + 1))
    else
        result="DIVERGENCE"
        DIVERGE=$((DIVERGE + 1))
    fi
    
    # Output
    printf "  %-25s Zig: %-8s Rust: %-16s %s\n" "$name" "$zig_status" "$rust_status" "$result"
}

# ══════════════════════════════════════════════════════════════════════════════
# CATEGORY A: Invalid PK Blobs
# ══════════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║ CATEGORY A: Invalid PK Blobs                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

test_adversarial "A1_truncated_pk" \
    "INSERT INTO crsql_changes VALUES ('foo', X'0109', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "A2_wrong_col_count" \
    "INSERT INTO crsql_changes VALUES ('foo', X'03090102', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "A3_empty_pk" \
    "INSERT INTO crsql_changes VALUES ('foo', X'', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "A4_zero_cols" \
    "INSERT INTO crsql_changes VALUES ('foo', X'00', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "A5_invalid_type" \
    "INSERT INTO crsql_changes VALUES ('foo', X'01FF01', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "A6_corrupt_length" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010DFFFF', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "A7_null_pk" \
    "INSERT INTO crsql_changes VALUES ('foo', NULL, 'b', 42, 1, 1, NULL, 1, 1);"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# CATEGORY B: Invalid Metadata
# ══════════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║ CATEGORY B: Invalid Metadata                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

test_adversarial "B1_neg_col_version" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, -1, 1, NULL, 1, 1);"

test_adversarial "B2_neg_db_version" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, -1, NULL, 1, 1);"

test_adversarial "B3_short_siteid" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, 1, X'0102030405060708', 1, 1);"

test_adversarial "B4_empty_siteid" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, 1, X'', 1, 1);"

test_adversarial "B5_long_siteid" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, 1, X'0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20', 1, 1);"

test_adversarial "B6_huge_col_version" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 4611686018427387904, 1, NULL, 1, 1);"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# CATEGORY C: Invalid Table/Column Names
# ══════════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║ CATEGORY C: Invalid Table/Column Names                              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

test_adversarial "C1_nonexist_table" \
    "INSERT INTO crsql_changes VALUES ('nonexistent', X'010901', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "C2_nonexist_column" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'nonexistent', 42, 1, 1, NULL, 1, 1);"

test_adversarial "C3_empty_table" \
    "INSERT INTO crsql_changes VALUES ('', X'010901', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "C4_empty_column" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', '', 42, 1, 1, NULL, 1, 1);"

test_adversarial "C5_null_table" \
    "INSERT INTO crsql_changes VALUES (NULL, X'010901', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "C6_null_column" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', NULL, 42, 1, 1, NULL, 1, 1);"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# CATEGORY D: Edge Cases
# ══════════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║ CATEGORY D: Edge Cases                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

test_adversarial "D1_int64_max_pk" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010CFFFFFFFFFFFFFFFF', 'b', 42, 1, 1, NULL, 1, 1);"

test_adversarial "D2_sentinel_with_val" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', '-1', 42, 1, 1, NULL, 2, 1);"

test_adversarial "D3_sentinel_seq0" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', '-1', NULL, 1, 1, NULL, 0, 1);"

test_adversarial "D4_float_col_ver" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1.5, 1, NULL, 1, 1);"

test_adversarial "D5_string_db_ver" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, 'one', NULL, 1, 1);"

test_adversarial "D6_too_few_cols" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, 1, NULL, 1);"

test_adversarial "D7_too_many_cols" \
    "INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 42, 1, 1, NULL, 1, 1, 'extra');"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Adversarial Input Fuzzing Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  PASS:         %d\n" "$PASS"
printf "  FAIL:         %d\n" "$FAIL"
printf "  SKIP:         %d\n" "$SKIP"
printf "  DIVERGENCE:   %d\n" "$DIVERGE"
printf "  Zig crashes:  %d\n" "$ZIG_CRASH"
printf "  Rust crashes: %d\n" "$RUST_CRASH"
echo ""

if [[ $ZIG_CRASH -gt 0 ]]; then
    echo "SECURITY CONCERN: Zig implementation crashed $ZIG_CRASH time(s)"
    echo "Crashes on malformed input indicate potential security vulnerabilities."
    exit 1
fi

if [[ $FAIL -gt 0 ]]; then
    echo "FAILURES: $FAIL test(s) failed"
    exit 1
fi

if [[ $RUST_CRASH -gt 0 ]]; then
    echo "NOTE: Rust/C oracle crashed $RUST_CRASH time(s) but Zig handled gracefully."
    echo "This is a POSITIVE finding - Zig has better error handling on these inputs."
fi

if [[ $DIVERGE -gt 0 ]]; then
    echo ""
    echo "DIVERGENCE: $DIVERGE test(s) showed different error handling behavior."
    echo "Review divergences to determine if alignment is needed."
fi

echo ""
echo "All adversarial input tests PASSED (no Zig crashes)"
exit 0
