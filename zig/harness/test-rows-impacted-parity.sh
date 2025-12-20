#!/usr/bin/env bash
# Oracle Parity Test: rows_impacted counter reset timing
#
# Compares crsql_rows_impacted() behavior between the Rust/C implementation
# (oracle) and the Zig implementation.
#
# The counter reset timing matters for sync clients that batch changes:
#   - If Zig resets on COMMIT but Rust/C resets on statement completion
#     (or vice versa), clients will get wrong counts.
#
# Reset semantics (documented here based on C tests and Rust code):
#   - Counter is per-connection (thread-local in C, global in Zig MVP)
#   - Counter resets to 0 on COMMIT (via xCommit hook in Rust, commit_hook in Zig)
#   - Counter resets to 0 on ROLLBACK
#   - Counter accumulates within a transaction across multiple statements
#
# Test scenarios:
#   1. Single INSERT via crsql_changes -> count should be 1
#   2. Two more INSERTs -> count should be 3 total (accumulated)
#   3. COMMIT transaction -> count should be 0 (reset on commit)
#   4. New transaction, insert -> count should be 1
#   5. ROLLBACK transaction -> count is NOT reset (Rust/C has xRollback=NULL)
#
# IMPORTANT: Rust/C does NOT reset rows_impacted on ROLLBACK!
# The xRollback method is NULL in changes-vtab.c:173. The Zig implementation
# incorrectly resets the counter on rollback via rollback_hook.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================================================="
echo "Oracle Parity Test: rows_impacted counter reset timing"
echo "============================================================================="
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
    echo "Zig extension not found at $ZIG_EXT"
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

# NOTE: The sqlite3_close() returns 5 warning is harmless and expected.
SQLITE="nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Temp files for output
TMPDIR="${REPO_ROOT}/.tmp"
mkdir -p "$TMPDIR"
RUST_OUT=$(mktemp "$TMPDIR/rows-rust.XXXXXX")
ZIG_OUT=$(mktemp "$TMPDIR/rows-zig.XXXXXX")
ERRFILE=$(mktemp "$TMPDIR/rows-err.XXXXXX")
trap "rm -f $RUST_OUT $ZIG_OUT $ERRFILE" EXIT

PASS=0
FAIL=0
DIVERGE=0

# Helper to run SQL and capture rows_impacted checkpoints
# For Rust/C oracle, use local binary; for Zig, use explicit extension load
run_test() {
    local ext="$1"
    local sql="$2"
    local out="$3"
    if [[ "$ext" == "RUST_ORACLE" ]]; then
        # Rust/C oracle via local binary
        $SQLITE :memory: -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" | grep "CHECKPOINT=" > "$out" || true
    else
        # Zig extension with explicit load
        $SQLITE :memory: -cmd ".load $ext" "$sql" 2>"$ERRFILE" | grep "CHECKPOINT=" > "$out" || true
    fi
}

# Compare results between implementations
compare_results() {
    local test_name="$1"
    local rust_file="$2"
    local zig_file="$3"
    
    if ! diff -q "$rust_file" "$zig_file" > /dev/null 2>&1; then
        echo "  DIVERGENCE DETECTED:"
        echo "  Rust/C (oracle):"
        sed 's/^/    /' "$rust_file"
        echo "  Zig (candidate):"
        sed 's/^/    /' "$zig_file"
        return 1
    fi
    return 0
}

# =============================================================================
# Test 1: Single INSERT via crsql_changes
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 1: Single INSERT via crsql_changes -> count should be 1"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=after_single_insert:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_rows_impacted() not available in Rust/C extension"
    exit 2
fi

run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_rows_impacted() not available in Zig extension"
    exit 2
fi

echo "  Rust/C: $(cat "$RUST_OUT")"
echo "  Zig:    $(cat "$ZIG_OUT")"

# Check value is 1
RUST_VAL=$(grep "after_single_insert" "$RUST_OUT" | cut -d: -f2)
if [[ "$RUST_VAL" == "1" ]]; then
    echo "  PASS: Rust/C reports 1 after single insert"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C expected 1, got $RUST_VAL"
    FAIL=$((FAIL + 1))
fi

if compare_results "Single INSERT" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 2: Multiple INSERTs accumulate within transaction
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 2: Three INSERTs -> count should accumulate to 3"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=after_first:' || crsql_rows_impacted();
INSERT INTO crsql_changes VALUES ('foo', X'010902', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=after_second:' || crsql_rows_impacted();
INSERT INTO crsql_changes VALUES ('foo', X'010903', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=after_third:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C:"
sed 's/^/    /' "$RUST_OUT"
echo "  Zig:"
sed 's/^/    /' "$ZIG_OUT"

# Check progressive accumulation
RUST_FIRST=$(grep "after_first" "$RUST_OUT" | cut -d: -f2)
RUST_SECOND=$(grep "after_second" "$RUST_OUT" | cut -d: -f2)
RUST_THIRD=$(grep "after_third" "$RUST_OUT" | cut -d: -f2)

if [[ "$RUST_FIRST" == "1" && "$RUST_SECOND" == "2" && "$RUST_THIRD" == "3" ]]; then
    echo "  PASS: Rust/C accumulates correctly (1 -> 2 -> 3)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C accumulation incorrect ($RUST_FIRST -> $RUST_SECOND -> $RUST_THIRD)"
    FAIL=$((FAIL + 1))
fi

if compare_results "Multiple INSERTs" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 3: COMMIT resets counter to 0
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 3: COMMIT -> counter should reset to 0"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=before_commit:' || crsql_rows_impacted();
COMMIT;
SELECT 'CHECKPOINT=after_commit:' || crsql_rows_impacted();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C:"
sed 's/^/    /' "$RUST_OUT"
echo "  Zig:"
sed 's/^/    /' "$ZIG_OUT"

RUST_BEFORE=$(grep "before_commit" "$RUST_OUT" | cut -d: -f2)
RUST_AFTER=$(grep "after_commit" "$RUST_OUT" | cut -d: -f2)

if [[ "$RUST_BEFORE" == "1" && "$RUST_AFTER" == "0" ]]; then
    echo "  PASS: Rust/C resets to 0 after COMMIT"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C COMMIT reset incorrect (before=$RUST_BEFORE, after=$RUST_AFTER)"
    FAIL=$((FAIL + 1))
fi

if compare_results "COMMIT reset" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 4: New transaction after COMMIT starts fresh
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 4: New transaction after COMMIT -> counter starts at 0, then 1"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
COMMIT;
SELECT 'CHECKPOINT=after_first_commit:' || crsql_rows_impacted();
BEGIN;
SELECT 'CHECKPOINT=start_new_tx:' || crsql_rows_impacted();
INSERT INTO crsql_changes VALUES ('foo', X'010902', 'b', 3, 2, 2, NULL, 1, 1);
SELECT 'CHECKPOINT=after_new_insert:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C:"
sed 's/^/    /' "$RUST_OUT"
echo "  Zig:"
sed 's/^/    /' "$ZIG_OUT"

RUST_AFTER_FIRST=$(grep "after_first_commit" "$RUST_OUT" | cut -d: -f2)
RUST_START_NEW=$(grep "start_new_tx" "$RUST_OUT" | cut -d: -f2)
RUST_AFTER_NEW=$(grep "after_new_insert" "$RUST_OUT" | cut -d: -f2)

if [[ "$RUST_AFTER_FIRST" == "0" && "$RUST_START_NEW" == "0" && "$RUST_AFTER_NEW" == "1" ]]; then
    echo "  PASS: Rust/C new transaction works correctly (0 -> 0 -> 1)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C new transaction incorrect ($RUST_AFTER_FIRST -> $RUST_START_NEW -> $RUST_AFTER_NEW)"
    FAIL=$((FAIL + 1))
fi

if compare_results "New transaction" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 5: ROLLBACK does NOT reset counter (Rust/C behavior!)
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 5: ROLLBACK -> counter is NOT reset (Rust/C xRollback=NULL)"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
INSERT INTO crsql_changes VALUES ('foo', X'010902', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=before_rollback:' || crsql_rows_impacted();
ROLLBACK;
SELECT 'CHECKPOINT=after_rollback:' || crsql_rows_impacted();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C:"
sed 's/^/    /' "$RUST_OUT"
echo "  Zig:"
sed 's/^/    /' "$ZIG_OUT"

RUST_BEFORE=$(grep "before_rollback" "$RUST_OUT" | cut -d: -f2)
RUST_AFTER=$(grep "after_rollback" "$RUST_OUT" | cut -d: -f2)

# Rust/C does NOT reset on ROLLBACK (xRollback is NULL in changes-vtab.c:173)
# The counter persists across rollback - this is the intended behavior
if [[ "$RUST_BEFORE" == "2" && "$RUST_AFTER" == "2" ]]; then
    echo "  PASS: Rust/C does NOT reset after ROLLBACK (counter stays at 2)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C ROLLBACK behavior unexpected (before=$RUST_BEFORE, after=$RUST_AFTER)"
    FAIL=$((FAIL + 1))
fi

if compare_results "ROLLBACK behavior" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge - Zig incorrectly resets counter on ROLLBACK"
    echo "        BUG: Zig should NOT have a rollback_hook that resets rows_impacted"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 6: No-op merge (value already exists) -> counter should NOT increment
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 6: No-op merge (same value) -> counter should NOT increment"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
-- Try to merge the exact same value with same clock - should be a no-op
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
SELECT 'CHECKPOINT=after_noop_merge:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT")"
echo "  Zig:    $(cat "$ZIG_OUT")"

RUST_VAL=$(grep "after_noop_merge" "$RUST_OUT" | cut -d: -f2)
if [[ "$RUST_VAL" == "0" ]]; then
    echo "  PASS: Rust/C reports 0 for no-op merge (no actual change)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C expected 0 for no-op, got $RUST_VAL"
    FAIL=$((FAIL + 1))
fi

if compare_results "No-op merge" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 7: Losing merge (lower clock) -> counter should NOT increment
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 7: Losing merge (lower col_version) -> counter should NOT increment"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
-- Try to merge with lower col_version (0 vs 1) - should lose and not count
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 999, 0, 0, NULL, 1, 1);
SELECT 'CHECKPOINT=after_losing_merge:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT")"
echo "  Zig:    $(cat "$ZIG_OUT")"

RUST_VAL=$(grep "after_losing_merge" "$RUST_OUT" | cut -d: -f2)
if [[ "$RUST_VAL" == "0" ]]; then
    echo "  PASS: Rust/C reports 0 for losing merge"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C expected 0 for losing merge, got $RUST_VAL"
    FAIL=$((FAIL + 1))
fi

if compare_results "Losing merge" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 8: Winning merge (higher clock) -> counter SHOULD increment
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 8: Winning merge (higher col_version) -> counter SHOULD increment"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
-- Merge with higher col_version (2 vs 1) - should win and count
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 999, 2, 2, NULL, 1, 1);
SELECT 'CHECKPOINT=after_winning_merge:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT")"
echo "  Zig:    $(cat "$ZIG_OUT")"

RUST_VAL=$(grep "after_winning_merge" "$RUST_OUT" | cut -d: -f2)
if [[ "$RUST_VAL" == "1" ]]; then
    echo "  PASS: Rust/C reports 1 for winning merge"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C expected 1 for winning merge, got $RUST_VAL"
    FAIL=$((FAIL + 1))
fi

if compare_results "Winning merge" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Test 9: Delete operation -> counter SHOULD increment
# =============================================================================
echo "-----------------------------------------------------------------------------"
echo "Test 9: Delete operation via merge -> counter SHOULD increment"
echo "-----------------------------------------------------------------------------"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
-- Delete via crsql_changes (col_name = '-1', cl = 2 for causal length)
INSERT INTO crsql_changes VALUES ('foo', X'010901', '-1', NULL, 2, 2, NULL, 2, 1);
SELECT 'CHECKPOINT=after_delete:' || crsql_rows_impacted();
COMMIT;
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT")"
echo "  Zig:    $(cat "$ZIG_OUT")"

RUST_VAL=$(grep "after_delete" "$RUST_OUT" | cut -d: -f2)
if [[ "$RUST_VAL" == "1" ]]; then
    echo "  PASS: Rust/C reports 1 for delete"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Rust/C expected 1 for delete, got $RUST_VAL"
    FAIL=$((FAIL + 1))
fi

if compare_results "Delete operation" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Values match between implementations"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Values diverge"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "============================================================================="
echo "rows_impacted Parity Test Summary"
echo "============================================================================="
printf "  PASSED:      %d\n" "$PASS"
printf "  FAILED:      %d\n" "$FAIL"
printf "  DIVERGENCES: %d (critical - will break sync client batching)\n" "$DIVERGE"
echo "============================================================================="
echo ""

# Document the expected reset semantics
echo "DOCUMENTED RESET SEMANTICS (per Rust/C oracle):"
echo "  - Counter accumulates within a transaction (multiple INSERTs sum up)"
echo "  - Counter resets to 0 on COMMIT (via vtab xCommit)"
echo "  - Counter does NOT reset on ROLLBACK (xRollback is NULL in Rust/C!)"
echo "  - Counter only increments when a row is ACTUALLY changed (not for no-ops)"
echo "  - Losing merges (lower col_version) do NOT increment counter"
echo "  - Winning merges (higher col_version) DO increment counter"
echo ""
echo "KNOWN DIVERGENCE:"
echo "  Zig incorrectly resets rows_impacted on ROLLBACK via rollback_hook."
echo "  This should be removed to match Rust/C behavior (xRollback=NULL)."
echo ""

if [[ $DIVERGE -gt 0 ]]; then
    echo "CRITICAL: rows_impacted timing diverges between implementations!"
    echo "This will cause sync client batching to report incorrect counts."
    exit 1
elif [[ $FAIL -gt 0 ]]; then
    echo "Some rows_impacted tests FAILED"
    exit 1
elif [[ $PASS -gt 0 ]]; then
    echo "All rows_impacted parity tests PASSED"
    exit 0
else
    echo "No tests ran successfully"
    exit 2
fi
