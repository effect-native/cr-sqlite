#!/usr/bin/env bash
# Oracle Parity Test: db_version advancement timing
# 
# Compares crsql_db_version() and crsql_next_db_version() behavior between
# the Rust/C implementation (oracle) and the Zig implementation.
#
# db_version is critical for sync protocols - if implementations increment it
# at different moments (per-statement vs per-transaction), sync will break.
#
# Test operations:
#   1. Initial state (should be 0 or 1)
#   2. Single INSERT -> record version
#   3. Single UPDATE -> record version
#   4. Multiple INSERTs in one transaction -> record at COMMIT
#   5. DELETE -> record version
#   6. No-op UPDATE (same value) -> version should NOT change
#   7. Merge from remote via crsql_changes INSERT -> record version
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Oracle Parity Test: db_version advancement timing"
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
RUST_OUT=$(mktemp "$TMPDIR/dbver-rust.XXXXXX")
ZIG_OUT=$(mktemp "$TMPDIR/dbver-zig.XXXXXX")
ERRFILE=$(mktemp "$TMPDIR/dbver-err.XXXXXX")
trap "rm -f $RUST_OUT $ZIG_OUT $ERRFILE" EXIT

PASS=0
FAIL=0
DIVERGE=0

# Helper to run SQL and capture db_version and next_db_version
# For Rust/C oracle, use local binary; for Zig, use explicit extension load
run_test() {
    local ext="$1"
    local sql="$2"
    local out="$3"
    if [[ "$ext" == "RUST_ORACLE" ]]; then
        # Rust/C oracle via local binary
        $SQLITE :memory: -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" | grep "VERSION=" > "$out" || true
    else
        # Zig extension with explicit load
        $SQLITE :memory: -cmd ".load $ext" "$sql" 2>"$ERRFILE" | grep "VERSION=" > "$out" || true
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

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Initial state
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 1: Initial db_version state"
SQL="
SELECT 'DB_VERSION=' || crsql_db_version();
SELECT 'NEXT_DB_VERSION=' || crsql_next_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_db_version() not available in Rust/C extension"
    exit 2
fi

run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_db_version() not available in Zig extension"
    exit 2
fi

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "Initial state" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Initial db_version matches"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Initial db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi

# Verify next_db_version = db_version + 1
RUST_DB=$(grep "DB_VERSION=" "$RUST_OUT" | head -1 | cut -d= -f2 | tr -d '\n')
RUST_NEXT=$(grep "NEXT_DB_VERSION=" "$RUST_OUT" | head -1 | cut -d= -f2 | tr -d '\n')
if [[ "$((RUST_DB + 1))" == "$RUST_NEXT" ]]; then
    echo "  PASS: next_db_version = db_version + 1 (Rust/C)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: next_db_version != db_version + 1 (Rust/C: $RUST_DB + 1 != $RUST_NEXT)"
    FAIL=$((FAIL + 1))
fi

ZIG_DB=$(grep "DB_VERSION=" "$ZIG_OUT" | head -1 | cut -d= -f2 | tr -d '\n')
ZIG_NEXT=$(grep "NEXT_DB_VERSION=" "$ZIG_OUT" | head -1 | cut -d= -f2 | tr -d '\n')
if [[ "$((ZIG_DB + 1))" == "$ZIG_NEXT" ]]; then
    echo "  PASS: next_db_version = db_version + 1 (Zig)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: next_db_version != db_version + 1 (Zig: $ZIG_DB + 1 != $ZIG_NEXT)"
    FAIL=$((FAIL + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Single INSERT
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 2: Single INSERT -> db_version"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
SELECT 'BEFORE_INSERT_VERSION=' || crsql_db_version();
INSERT INTO foo VALUES (1, 'hello');
SELECT 'AFTER_INSERT_VERSION=' || crsql_db_version();
SELECT 'NEXT_DB_VERSION=' || crsql_next_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "Single INSERT" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Single INSERT db_version matches"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Single INSERT db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Single UPDATE
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 3: Single UPDATE -> db_version"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
SELECT 'BEFORE_UPDATE_VERSION=' || crsql_db_version();
UPDATE foo SET b = 'world' WHERE a = 1;
SELECT 'AFTER_UPDATE_VERSION=' || crsql_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "Single UPDATE" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Single UPDATE db_version matches"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Single UPDATE db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Multiple INSERTs in one transaction
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 4: Multiple INSERTs in transaction -> db_version at COMMIT"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
SELECT 'BEFORE_TX_VERSION=' || crsql_db_version();
BEGIN;
INSERT INTO foo VALUES (1, 'one');
SELECT 'AFTER_INSERT_1_VERSION=' || crsql_db_version();
INSERT INTO foo VALUES (2, 'two');
SELECT 'AFTER_INSERT_2_VERSION=' || crsql_db_version();
INSERT INTO foo VALUES (3, 'three');
SELECT 'AFTER_INSERT_3_VERSION=' || crsql_db_version();
COMMIT;
SELECT 'AFTER_COMMIT_VERSION=' || crsql_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "Multiple INSERTs in TX" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Multiple INSERTs in TX db_version matches"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Multiple INSERTs in TX db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: DELETE
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 5: DELETE -> db_version"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
SELECT 'BEFORE_DELETE_VERSION=' || crsql_db_version();
DELETE FROM foo WHERE a = 1;
SELECT 'AFTER_DELETE_VERSION=' || crsql_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "DELETE" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: DELETE db_version matches"
    PASS=$((PASS + 1))
else
    echo "  FAIL: DELETE db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: No-op UPDATE (same value) - version should NOT change
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 6: No-op UPDATE (same value) -> db_version should NOT change"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
SELECT 'BEFORE_NOOP_VERSION=' || crsql_db_version();
UPDATE foo SET b = 'hello' WHERE a = 1;
SELECT 'AFTER_NOOP_VERSION=' || crsql_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "No-op UPDATE" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: No-op UPDATE db_version matches"
    PASS=$((PASS + 1))
    
    # Additional check: version should NOT have changed
    RUST_BEFORE=$(grep "BEFORE_NOOP_VERSION=" "$RUST_OUT" | cut -d= -f2)
    RUST_AFTER=$(grep "AFTER_NOOP_VERSION=" "$RUST_OUT" | cut -d= -f2)
    if [[ "$RUST_BEFORE" == "$RUST_AFTER" ]]; then
        echo "  PASS: No-op UPDATE correctly did not advance db_version"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: No-op UPDATE incorrectly advanced db_version ($RUST_BEFORE -> $RUST_AFTER)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: No-op UPDATE db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Merge from remote via crsql_changes INSERT
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 7: Merge from remote (crsql_changes INSERT) -> db_version"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'local');
SELECT 'BEFORE_MERGE_VERSION=' || crsql_db_version();
-- Simulate receiving a remote change with higher col_version
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 'remote', 2, 2, X'00000000000000000000000000000001', 1, 0);
SELECT 'AFTER_MERGE_VERSION=' || crsql_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "Merge from remote" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: Merge from remote db_version matches"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Merge from remote db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi

# Check that db_version advanced (merge should update)
RUST_BEFORE=$(grep "BEFORE_MERGE_VERSION=" "$RUST_OUT" | cut -d= -f2)
RUST_AFTER=$(grep "AFTER_MERGE_VERSION=" "$RUST_OUT" | cut -d= -f2)
if [[ -n "$RUST_BEFORE" && -n "$RUST_AFTER" && "$RUST_AFTER" -gt "$RUST_BEFORE" ]]; then
    echo "  PASS: Merge correctly advanced db_version (Rust/C: $RUST_BEFORE -> $RUST_AFTER)"
    PASS=$((PASS + 1))
else
    echo "  INFO: Merge db_version behavior (Rust/C: $RUST_BEFORE -> $RUST_AFTER)"
fi

ZIG_BEFORE=$(grep "BEFORE_MERGE_VERSION=" "$ZIG_OUT" | cut -d= -f2 || echo "")
ZIG_AFTER=$(grep "AFTER_MERGE_VERSION=" "$ZIG_OUT" | cut -d= -f2 || echo "")
if [[ -n "$ZIG_BEFORE" && -n "$ZIG_AFTER" && "$ZIG_AFTER" -gt "$ZIG_BEFORE" ]]; then
    echo "  PASS: Merge correctly advanced db_version (Zig: $ZIG_BEFORE -> $ZIG_AFTER)"
    PASS=$((PASS + 1))
else
    echo "  INFO: Merge db_version behavior (Zig: $ZIG_BEFORE -> $ZIG_AFTER)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: No-op merge (losing merge) should NOT advance db_version
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 8: No-op merge (lower col_version) -> db_version should NOT change"
SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'local');
UPDATE foo SET b = 'updated_local';
UPDATE foo SET b = 'updated_again';
SELECT 'BEFORE_NOOP_MERGE_VERSION=' || crsql_db_version();
-- Simulate receiving a remote change with LOWER col_version (should lose)
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 'stale_remote', 1, 1, X'00000000000000000000000000000001', 1, 0);
SELECT 'AFTER_NOOP_MERGE_VERSION=' || crsql_db_version();
"

run_test "RUST_ORACLE" "$SQL" "$RUST_OUT"
run_test "$ZIG_EXT" "$SQL" "$ZIG_OUT"

echo "  Rust/C: $(cat "$RUST_OUT" | tr '\n' ' ')"
echo "  Zig:    $(cat "$ZIG_OUT" | tr '\n' ' ')"

if compare_results "No-op merge" "$RUST_OUT" "$ZIG_OUT"; then
    echo "  PASS: No-op merge db_version matches"
    PASS=$((PASS + 1))
    
    # Additional check: version should NOT have changed
    RUST_BEFORE=$(grep "BEFORE_NOOP_MERGE_VERSION=" "$RUST_OUT" | cut -d= -f2)
    RUST_AFTER=$(grep "AFTER_NOOP_MERGE_VERSION=" "$RUST_OUT" | cut -d= -f2)
    if [[ "$RUST_BEFORE" == "$RUST_AFTER" ]]; then
        echo "  PASS: No-op merge correctly did not advance db_version"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: No-op merge incorrectly advanced db_version ($RUST_BEFORE -> $RUST_AFTER)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: No-op merge db_version diverges"
    FAIL=$((FAIL + 1))
    DIVERGE=$((DIVERGE + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "db_version Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  PASSED:     %d\n" "$PASS"
printf "  FAILED:     %d\n" "$FAIL"
printf "  DIVERGENCES: %d (critical - will break sync)\n" "$DIVERGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $DIVERGE -gt 0 ]]; then
    echo "CRITICAL: db_version timing diverges between implementations!"
    echo "This will cause sync protocol failures."
    exit 1
elif [[ $FAIL -gt 0 ]]; then
    echo "Some db_version tests FAILED"
    exit 1
elif [[ $PASS -gt 0 ]]; then
    echo "All db_version parity tests PASSED"
    exit 0
else
    echo "No tests ran successfully"
    exit 2
fi
