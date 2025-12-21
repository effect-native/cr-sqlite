#!/usr/bin/env bash
# Wire Format Edge Case Parity Tests (Zig vs Rust/C Oracle)
#
# Tests crsql_pack_columns encoding for edge case values:
# - WF-007: Empty string
# - WF-009: Zero
# - WF-010: Negative one
# - WF-011: MAX_INT64 (9223372036854775807)
# - WF-012: MIN_INT64 (-9223372036854775808)
# - WF-013: MAX_FLOAT (1.7976931348623157e+308)
# - WF-014: Unicode/emoji
#
# Context: TASK-132, research/zig-cr/96-ideal-parity-experiments.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Wire Format Edge Case Parity Tests (Zig vs Rust/C Oracle)"
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
TMPDIR="${REPO_ROOT}/.tmp/wire-format-edge-cases-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0

ERRFILE="$TMPDIR/error.txt"

# Helper to run SQL with Zig extension
run_zig() {
    local sql="$1"
    $SQLITE ":memory:" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Helper to run SQL with Rust/C extension
run_rust() {
    local sql="$1"
    $SQLITE ":memory:" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

# Check for blocking errors
is_blocked() {
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function" "$ERRFILE"; then
            return 0
        fi
    fi
    return 1
}

# Compare helper
compare() {
    local zig_result="$1"
    local rust_result="$2"
    local test_name="$3"
    
    if is_blocked; then
        echo "  SKIP: crsql_pack_columns not implemented"
        SKIP=$((SKIP + 1))
    elif [[ "$zig_result" == "$rust_result" ]]; then
        echo "  PASS: $test_name"
        echo "    Both return: $zig_result"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "    Zig returns:    '$zig_result'"
        echo "    Oracle returns: '$rust_result'"
        FAIL=$((FAIL + 1))
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# WF-007: Empty string encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-007: Empty string encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(''));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(''));")
compare "$ZIG_RESULT" "$RUST_RESULT" "Empty string encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-009: Zero encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-009: Zero encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(0));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(0));")
compare "$ZIG_RESULT" "$RUST_RESULT" "Zero encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-010: Negative one encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-010: Negative one encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(-1));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(-1));")
compare "$ZIG_RESULT" "$RUST_RESULT" "Negative one encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-011: MAX_INT64 encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-011: MAX_INT64 (9223372036854775807) encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(9223372036854775807));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(9223372036854775807));")
compare "$ZIG_RESULT" "$RUST_RESULT" "MAX_INT64 encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-012: MIN_INT64 encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-012: MIN_INT64 (-9223372036854775808) encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(-9223372036854775808));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(-9223372036854775808));")
compare "$ZIG_RESULT" "$RUST_RESULT" "MIN_INT64 encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-013: MAX_FLOAT encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-013: MAX_FLOAT (1.7976931348623157e+308) encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(1.7976931348623157e+308));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(1.7976931348623157e+308));")
compare "$ZIG_RESULT" "$RUST_RESULT" "MAX_FLOAT encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-014: Unicode/emoji encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-014: Unicode/emoji encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test with party popper emoji (U+1F389)
ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns('🎉'));")
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns('🎉'));")
compare "$ZIG_RESULT" "$RUST_RESULT" "Emoji (🎉) encoding"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Wire Format Edge Case Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  PASS:    %d\n" "$PASS"
printf "  FAIL:    %d\n" "$FAIL"
printf "  SKIP:    %d\n" "$SKIP"
echo ""

if [[ $SKIP -gt 0 && $PASS -eq 0 && $FAIL -eq 0 ]]; then
    echo "BLOCKED: All tests skipped (crsql_pack_columns not implemented)"
    exit 2
fi

if [[ $FAIL -gt 0 ]]; then
    echo "PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation of crsql_pack_columns differs from the Rust/C oracle"
    echo "for $FAIL edge case value(s). This may cause sync incompatibility."
    exit 1
fi

echo "All wire format edge case parity tests PASSED"
echo ""
echo "Verified parity for:"
echo "  - WF-007: Empty string"
echo "  - WF-009: Zero"
echo "  - WF-010: Negative one"
echo "  - WF-011: MAX_INT64"
echo "  - WF-012: MIN_INT64"
echo "  - WF-013: MAX_FLOAT"
echo "  - WF-014: Unicode/emoji"
exit 0
