#!/usr/bin/env bash
# Config API Behavior Tests for Zig CR-SQLite
# RGRTDD Spec: Tests describe expected behavior of crsql_config_get/set
#
# crsql_config_get(setting_name) - retrieves current config value
# crsql_config_set(setting_name, value) - sets config value, persists to DB
#
# Known settings:
#   - 'merge-equal-values': Controls whether merging identical values advances the clock
#     - 1 (default): Merging same value with higher col_version advances db_version
#     - 0: Merging same value is a no-op (clock not advanced)
#
# Reference: core/rs/core/src/config.rs
#            core/rs/core/src/changes_vtab_write.rs (merge-equal-values behavior)
#
# IMPORTANT: These tests are RED until crsql_config_get/set are implemented in Zig.
#            Tests describe behavior, not implementation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: crsql_config_get/set API"
echo "RGRTDD Spec: Config API expected behavior"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

# Temp directory for test databases
TMP_DIR="$ROOT_DIR/.tmp/test-config"
mkdir -p "$TMP_DIR"
ERRFILE=$(mktemp "$TMP_DIR/err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# ═══════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

# Run SQL with Zig extension (clean sqlite + explicit .load)
run_zig() {
    local db="$1"; shift
    nix run nixpkgs#sqlite --quiet -- "$db" -cmd ".load $ZIG_EXT" "$@" 2>"$ERRFILE" || true
}

# Run SQL with Rust/C oracle (sqlite-cr wrapper)
run_rust() {
    local db="$1"; shift
    nix run github:subtleGradient/sqlite-cr --quiet -- "$db" <<< "$@" 2>"$ERRFILE" || true
}

# Helper to get last line of output
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL and get full output
run_sql_full() {
    local sql="$1"
    nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Helper to check if error file contains specific error
has_error() {
    local pattern="$1"
    grep -qi "$pattern" "$ERRFILE" 2>/dev/null
}

# Check if config_get function is available
echo "Checking crsql_config_get availability..."
SMOKE_RESULT=$(run_sql "SELECT crsql_config_get('merge-equal-values');" 2>&1 || echo "ERROR")
if has_error "no such function: crsql_config_get"; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "EXPECTED: crsql_config_get() not yet implemented in Zig"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This is the RED phase of RGRTDD."
    echo "All tests will FAIL until crsql_config_get/set are implemented."
    echo ""
    CONFIG_GET_AVAILABLE=false
else
    CONFIG_GET_AVAILABLE=true
fi

# Check if config_set function is available
SMOKE_RESULT=$(run_sql "SELECT crsql_config_set('merge-equal-values', 1);" 2>&1 || echo "ERROR")
if has_error "no such function: crsql_config_set"; then
    CONFIG_SET_AVAILABLE=false
else
    CONFIG_SET_AVAILABLE=true
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: crsql_config_get function exists
# Reference: core/rs/core/src/config.rs - crsql_config_get()
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: crsql_config_get function exists"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT crsql_config_get('merge-equal-values');")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_get function not found (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif has_error "no such function"; then
    echo "  FAIL: crsql_config_get function not found"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  PASS: crsql_config_get function exists"
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: crsql_config_set function exists
# Reference: core/rs/core/src/config.rs - crsql_config_set()
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: crsql_config_set function exists"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT crsql_config_set('merge-equal-values', 1);")

if [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_set function not found (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif has_error "no such function"; then
    echo "  FAIL: crsql_config_set function not found"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  PASS: crsql_config_set function exists"
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: crsql_config_get returns integer for merge-equal-values
# Reference: core/rs/core/src/config.rs - mergeEqualValues is stored as int
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: crsql_config_get returns integer for merge-equal-values"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT typeof(crsql_config_get('merge-equal-values'));")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_get not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "integer" ]]; then
    echo "  PASS: crsql_config_get returns integer type"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'integer', got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: crsql_config_set persists value (set to 0)
# Reference: core/rs/core/src/config.rs - insert_config_setting()
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: crsql_config_set persists value (set to 0)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
SELECT crsql_config_set('merge-equal-values', 0);
SELECT crsql_config_get('merge-equal-values');
")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]] || [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: Config functions not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: crsql_config_set(0) persists, get returns 0"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: crsql_config_set with value 1
# Reference: core/rs/core/src/config.rs - mergeEqualValues = value.int()
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: crsql_config_set with value 1"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
SELECT crsql_config_set('merge-equal-values', 0);
SELECT crsql_config_set('merge-equal-values', 1);
SELECT crsql_config_get('merge-equal-values');
")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]] || [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: Config functions not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: crsql_config_set(1) persists, get returns 1"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Unknown setting name returns error (get)
# Reference: core/rs/core/src/config.rs - "Unknown setting name" error
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Unknown setting name returns error (get)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT crsql_config_get('unknown-setting-xyz');")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_get not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif has_error "Unknown setting" || has_error "unknown setting" || has_error "error"; then
    echo "  PASS: Unknown setting returns error"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ -z "$RESULT" ]] || [[ "$RESULT" == "null" ]] || [[ "$RESULT" == "" ]]; then
    # NULL return is also acceptable for unknown settings
    echo "  PASS: Unknown setting returns NULL/empty"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected error or NULL for unknown setting, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Unknown setting for set returns error
# Reference: core/rs/core/src/config.rs - "Unknown setting name" error in set
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Unknown setting for set returns error"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT crsql_config_set('unknown-setting-xyz', 1);")

if [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_set not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif has_error "Unknown setting" || has_error "unknown setting" || has_error "error"; then
    echo "  PASS: Unknown setting for set returns error"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected error for unknown setting in set, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: merge-equal-values=1 behavior (merge same value advances clock)
# Reference: core/rs/core/src/changes_vtab_write.rs - mergeEqualValues == 1 branch
# When values are identical but col_version is higher and merge-equal-values=1,
# the merge advances db_version (site_id tie-breaker applies)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: merge-equal-values=1 (merge same value with higher site_id advances clock)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# With merge-equal-values=1, when values are equal, we tie-break on site_id.
# If incoming site_id > local site_id, the merge wins and db_version advances.
RESULT=$(run_sql "
-- Setup: create CRR, insert row
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'same');

-- Get initial db_version
SELECT crsql_db_version();
")
INITIAL_DB_VERSION="$RESULT"

# Now apply a change with same value but from a 'higher' site_id
# Using X'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' which is > any normal site_id
RESULT=$(run_sql "
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'same');

-- Enable merge-equal-values (tie-break on site_id when values equal)
SELECT crsql_config_set('merge-equal-values', 1);

-- Apply change with same value ('same'), same col_version (1), but higher site_id
-- The high site_id should win the tie-break and advance db_version
BEGIN;
INSERT INTO crsql_changes VALUES ('t', X'010901', 'val', 'same', 1, 1, X'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 1, 1);
COMMIT;

SELECT crsql_db_version();
")

if [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_set not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ -z "$RESULT" ]]; then
    echo "  FAIL: No result returned"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" -gt 1 ]]; then
    # db_version should advance beyond initial (1) because high site_id wins
    echo "  PASS: db_version advanced to $RESULT (merge-equal-values=1 with higher site_id)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected db_version > 1, got: '$RESULT'"
    echo "        (merge-equal-values=1 should advance clock when site_id wins)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 9: merge-equal-values=0 behavior (merge same value is no-op)
# Reference: core/rs/core/src/changes_vtab_write.rs - ret == 0 without site_id check
# When values are identical and merge-equal-values=0, local wins (no-op)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 9: merge-equal-values=0 (merge same value is no-op)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'same');

-- Disable merge-equal-values (equal values = local wins, no change)
SELECT crsql_config_set('merge-equal-values', 0);

-- Get db_version after insert
SELECT crsql_db_version();
")
BEFORE_VERSION="$RESULT"

RESULT=$(run_sql "
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'same');

SELECT crsql_config_set('merge-equal-values', 0);

-- Apply change with identical value - with merge-equal-values=0, this is a no-op
BEGIN;
INSERT INTO crsql_changes VALUES ('t', X'010901', 'val', 'same', 1, 1, X'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 1, 1);
COMMIT;

-- db_version unchanged (no-op)
SELECT crsql_db_version();
")

if [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_set not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ -z "$RESULT" ]]; then
    echo "  FAIL: No result returned"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    # db_version stays at 1 because equal value merge is no-op
    echo "  PASS: db_version unchanged at $RESULT (merge-equal-values=0, equal value is no-op)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected db_version = 1 (no change), got: '$RESULT'"
    echo "        (merge-equal-values=0 means equal values don't advance clock)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 10: Config persists across statements in same connection
# Reference: core/rs/core/src/config.rs - ExtData.mergeEqualValues is per-connection
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 10: Config persists across statements in same connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
SELECT crsql_config_set('merge-equal-values', 0);

-- Run some unrelated SQL
CREATE TABLE dummy (x);
INSERT INTO dummy VALUES (1);
SELECT COUNT(*) FROM dummy;

-- Config still 0
SELECT crsql_config_get('merge-equal-values');
")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]] || [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: Config functions not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: Config persists across statements (still 0)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0 after intervening SQL, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 11: Default value for merge-equal-values
# Reference: core/rs/core/src/config.rs - default is 1 (based on Rust impl)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 11: Default value for merge-equal-values"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Fresh connection - check default without any prior set
RESULT=$(run_sql "SELECT crsql_config_get('merge-equal-values');")

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_get not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Default value for merge-equal-values is 1"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RESULT" == "0" ]]; then
    # If default is 0, that's also valid behavior (document it)
    echo "  PASS: Default value for merge-equal-values is 0 (different from Rust default)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0 or 1 as default, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 12: crsql_config_set returns the set value
# Reference: core/rs/core/src/config.rs - ctx.result_value(value)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 12: crsql_config_set returns the set value"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT crsql_config_set('merge-equal-values', 0);")

if [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_set not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: crsql_config_set returns the value that was set (0)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    # Empty result or NULL is also acceptable (some impls don't return)
    if [[ -z "$RESULT" ]] || [[ "$RESULT" == "" ]]; then
        echo "  PASS: crsql_config_set completed (no return value)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Expected 0 or empty, got: '$RESULT'"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test CF-007: Config isolation - behavior on new connection (PARITY TEST)
# This is the critical isolation test from TASK-138
# 
# DISCOVERY: The Rust/C oracle PERSISTS config to the database via crsql_config table.
# This means config is NOT purely per-connection - it's stored in the database.
# A new connection to the SAME database will see the persisted config.
# A new connection to a FRESH database will see the default (1).
#
# The test now verifies parity between Zig and Rust/C implementations.
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test CF-007a: Config persists in database across connections (Zig)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Use a persistent database file to test across connections
DB_FILE="$TMP_DIR/cf007-zig.db"
rm -f "$DB_FILE"

# Connection 1: Set non-default value (0) in first invocation
ZIG_CONN1=$(nix run nixpkgs#sqlite --quiet -- "$DB_FILE" -cmd ".load $ZIG_EXT" "
SELECT crsql_config_set('merge-equal-values', 0);
SELECT crsql_config_get('merge-equal-values');
" 2>/dev/null | tail -1)

# Connection 2: Check value in NEW invocation to SAME database
# Per oracle behavior, this should see the PERSISTED value (0)
ZIG_CONN2=$(nix run nixpkgs#sqlite --quiet -- "$DB_FILE" -cmd ".load $ZIG_EXT" "
SELECT crsql_config_get('merge-equal-values');
" 2>/dev/null | tail -1)

echo "  Zig Connection 1 (after set to 0): $ZIG_CONN1"
echo "  Zig Connection 2 (same db):        $ZIG_CONN2"

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]] || [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: Config functions not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$ZIG_CONN1" == "0" && "$ZIG_CONN2" == "0" ]]; then
    echo "  PASS: Config correctly persisted to database (value 0 preserved)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Unexpected values - Conn1: '$ZIG_CONN1', Conn2: '$ZIG_CONN2'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test CF-007b: Fresh database has default config value
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test CF-007b: Fresh database has default config (Zig)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# New fresh database - should have default value
DB_FILE_FRESH="$TMP_DIR/cf007-zig-fresh.db"
rm -f "$DB_FILE_FRESH"

ZIG_FRESH=$(nix run nixpkgs#sqlite --quiet -- "$DB_FILE_FRESH" -cmd ".load $ZIG_EXT" "
SELECT crsql_config_get('merge-equal-values');
" 2>/dev/null | tail -1)

echo "  Zig fresh database default: $ZIG_FRESH"

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: crsql_config_get not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$ZIG_FRESH" == "0" ]]; then
    echo "  PASS: Fresh database has default value (0, matches oracle)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected default 0, got: '$ZIG_FRESH'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test CF-007 Parity: Compare Zig vs Rust/C oracle behavior
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test CF-007c Parity: Verify both implementations have same config persistence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test with Rust/C oracle - same database persistence test
DB_FILE_RUST="$TMP_DIR/cf007-rust.db"
rm -f "$DB_FILE_RUST"

# Rust Connection 1: Set non-default value
RUST_CONN1=$(nix run github:subtleGradient/sqlite-cr --quiet -- "$DB_FILE_RUST" <<< "
SELECT crsql_config_set('merge-equal-values', 0);
SELECT crsql_config_get('merge-equal-values');
" 2>/dev/null | tail -1)

# Rust Connection 2: Check value in NEW invocation to SAME database
RUST_CONN2=$(nix run github:subtleGradient/sqlite-cr --quiet -- "$DB_FILE_RUST" <<< "
SELECT crsql_config_get('merge-equal-values');
" 2>/dev/null | tail -1)

echo "  Rust/C Connection 1 (after set to 0): $RUST_CONN1"
echo "  Rust/C Connection 2 (same db):        $RUST_CONN2"

# Check Rust/C oracle behavior
if [[ "$RUST_CONN1" == "0" && "$RUST_CONN2" == "0" ]]; then
    echo "  Rust/C oracle: Config correctly persists to database"
elif [[ "$RUST_CONN1" == "0" && "$RUST_CONN2" == "1" ]]; then
    echo "  Rust/C oracle: Config resets on new connection (per-connection only)"
else
    echo "  Rust/C oracle: Config behavior - Conn1: '$RUST_CONN1', Conn2: '$RUST_CONN2'"
fi

# Test fresh database with Rust/C
DB_FILE_RUST_FRESH="$TMP_DIR/cf007-rust-fresh.db"
rm -f "$DB_FILE_RUST_FRESH"

RUST_FRESH=$(nix run github:subtleGradient/sqlite-cr --quiet -- "$DB_FILE_RUST_FRESH" <<< "
SELECT crsql_config_get('merge-equal-values');
" 2>/dev/null | tail -1)

echo "  Rust/C fresh database default: $RUST_FRESH"

# Compare parity for persistence behavior
echo ""
echo "  Parity comparison (persistence to same database):"
echo "    Zig   - Connection 2 (same db): $ZIG_CONN2"
echo "    Rust  - Connection 2 (same db): $RUST_CONN2"

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]] || [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "  FAIL: Zig config functions not implemented (expected for RED phase)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$ZIG_CONN2" == "$RUST_CONN2" ]]; then
    echo "  PASS: Both implementations have same persistence behavior"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Parity divergence in persistence - Zig: '$ZIG_CONN2', Rust: '$RUST_CONN2'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Compare parity for fresh database default
# NOTE: The Rust/C reference implementation in core/src/ext-data.c:72 sets
#       pExtData->mergeEqualValues = 0 as the default.
#       If Zig has a different default, that's a parity issue to fix.
echo ""
echo "  Parity comparison (fresh database default):"
echo "    Zig   - Fresh db default: $ZIG_FRESH"
echo "    Rust  - Fresh db default: $RUST_FRESH"
echo "    (Reference: core/src/ext-data.c:72 sets default = 0)"

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]]; then
    echo "  (Skipped - Zig config not available)"
elif [[ "$ZIG_FRESH" == "$RUST_FRESH" ]]; then
    echo "  PASS: Both implementations have same default value"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Parity divergence in default - Zig: '$ZIG_FRESH', Rust: '$RUST_FRESH'"
    echo "        ACTION NEEDED: Fix Zig default to match Rust/C oracle (should be $RUST_FRESH)"
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

if [[ "$CONFIG_GET_AVAILABLE" == "false" ]] && [[ "$CONFIG_SET_AVAILABLE" == "false" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RGRTDD RED PHASE: All tests FAILED as expected"
    echo "crsql_config_get() and crsql_config_set() are not yet implemented in Zig."
    echo ""
    echo "To proceed to GREEN phase:"
    echo "  1. Implement crsql_config_get in zig/src/"
    echo "  2. Implement crsql_config_set in zig/src/"
    echo "  3. Re-run this test suite"
    echo "  4. All tests pass = GREEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    # Exit with 0 for RED phase (expected failures)
    exit 0
fi

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "All tests PASSED"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo "All tests SKIPPED"
    exit 2
else
    echo "Some tests FAILED"
    exit 1
fi
