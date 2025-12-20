#!/usr/bin/env bash
# clset Virtual Table Module Test Suite
# Validates CREATE VIRTUAL TABLE ... USING clset(...) behavior
#
# Reference: core/rs/core/src/create_cl_set_vtab.rs
# Rust tests: core/rs/integration_check/src/t/test_cl_set_vtab.rs
#
# The clset ("Causal Length Set") module:
#   - Creates a virtual table with _schema suffix
#   - Creates a physical base table (name without _schema suffix)
#   - Converts the base table to a CRR
#   - Creates associated __crsql_clock and __crsql_pks tables
#
# This is a SPEC (RED) test — expects to FAIL until clset module is implemented in Zig.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: clset Virtual Table Module"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Allow override via environment
LIB="${EXT:-$LIB}"

if [[ ! -f "$LIB" ]]; then
    echo "Extension not found at $LIB"
    echo "Run 'nix run nixpkgs#zig -- build' first"
    exit 1
fi

echo "Using extension: $LIB"
echo ""

TMPDIR="${SCRIPT_DIR}/../../.tmp"
mkdir -p "$TMPDIR"
ERRFILE=$(mktemp "$TMPDIR/clset-err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

PASS=0
FAIL=0
SKIP=0

run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_sql_check_error() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>&1 || true
}

# =============================================================================
# Test 1: Module exists and can create virtual table with _schema suffix
# =============================================================================
# Reference: create_cl_set_vtab.rs:create_impl() lines 49-73
echo "Test 1: CREATE VIRTUAL TABLE foo_schema USING clset(...) succeeds"
RESULT=$(run_sql_check_error "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
SELECT count(*) FROM sqlite_master WHERE name='foo_schema';
")
if echo "$RESULT" | grep -qi "no such module"; then
    echo "  FAIL: clset module not found (expected for RED phase)"
    echo "        Error: $RESULT"
    FAIL=$((FAIL + 1))
elif echo "$RESULT" | grep -qi "stepping.*error\|Error:.*stepping"; then
    # Check for actual CREATE error, not close-time cleanup errors
    echo "  FAIL: CREATE VIRTUAL TABLE failed"
    echo "        Error: $RESULT"
    FAIL=$((FAIL + 1))
elif echo "$RESULT" | grep -q "^1$"; then
    # sqlite3_close errors during cleanup are known issue with Rust ext, ignore them
    echo "  PASS: Virtual table creation succeeded"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Virtual table 'foo_schema' not found after CREATE"
    echo "        Output: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 2: Creating without _schema suffix fails with clear error
# =============================================================================
# Reference: create_cl_set_vtab.rs:create_impl() lines 58-64
# Error message: "MUST end with _schema"
echo "Test 2: CREATE VIRTUAL TABLE foo USING clset(...) fails without _schema suffix"
RESULT=$(run_sql_check_error "CREATE VIRTUAL TABLE foo USING clset (a PRIMARY KEY NOT NULL, b);")
if echo "$RESULT" | grep -qi "no such module"; then
    echo "  SKIP: clset module not found (cannot test naming validation)"
    SKIP=$((SKIP + 1))
elif echo "$RESULT" | grep -qi "_schema"; then
    echo "  PASS: Error message mentions _schema requirement"
    PASS=$((PASS + 1))
elif echo "$RESULT" | grep -qi "error"; then
    echo "  PARTIAL: Got an error, but message doesn't mention _schema requirement"
    echo "           Error: $RESULT"
    FAIL=$((FAIL + 1))
else
    echo "  FAIL: Expected an error for missing _schema suffix"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 3: After create, physical base table exists
# =============================================================================
# Reference: create_cl_set_vtab.rs:create_clset_storage() lines 75-95
echo "Test 3: Physical base table 'foo' exists after CREATE VIRTUAL TABLE foo_schema"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
SELECT count(*) FROM sqlite_master WHERE type='table' AND name='foo';
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Base table 'foo' exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Base table 'foo' not found (got count=$RESULT)"
    cat "$ERRFILE" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 4: After create, foo__crsql_clock table exists
# =============================================================================
# Reference: create_cl_set_vtab.rs:destroy() shows these tables are expected
echo "Test 4: Clock table 'foo__crsql_clock' exists"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
SELECT count(*) FROM sqlite_master WHERE type='table' AND name='foo__crsql_clock';
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Clock table 'foo__crsql_clock' exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Clock table 'foo__crsql_clock' not found (got count=$RESULT)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 5: After create, foo__crsql_pks table exists
# =============================================================================
echo "Test 5: PKs table 'foo__crsql_pks' exists"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
SELECT count(*) FROM sqlite_master WHERE type='table' AND name='foo__crsql_pks';
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: PKs table 'foo__crsql_pks' exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL: PKs table 'foo__crsql_pks' not found (got count=$RESULT)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 6: Base table is a CRR (has CRDT triggers)
# =============================================================================
# Reference: create_cl_set_vtab.rs:create_impl() line 72 calls create_crr()
# Note: We verify by checking for CRDT triggers since crsql_is_crr is Zig-only
echo "Test 6: Base table 'foo' is a CRR (has foo__crsql_* triggers)"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'foo__crsql%';
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" -ge "3" ]]; then
    echo "  PASS: Base table 'foo' is a CRR (has $RESULT CRDT triggers)"
    PASS=$((PASS + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  FAIL: Base table 'foo' has no CRDT triggers (not a CRR)"
    FAIL=$((FAIL + 1))
else
    echo "  FAIL: Expected >=3 CRDT triggers, got $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 7: Inserting into base table works and creates change records
# =============================================================================
# Reference: test_cl_set_vtab.rs:create_crr_via_vtab() lines 14-25
echo "Test 7: INSERT into base table creates change records"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
INSERT INTO foo VALUES (1, 2);
SELECT count(*) FROM crsql_changes;
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" -ge "1" ]]; then
    echo "  PASS: Change records created (count=$RESULT)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No change records found (count=$RESULT)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 8: DROP TABLE foo_schema cleans up all tables
# =============================================================================
# Reference: create_cl_set_vtab.rs:destroy() lines 166-178
echo "Test 8: DROP TABLE foo_schema removes all related tables"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
DROP TABLE foo_schema;
SELECT count(*) FROM sqlite_master WHERE name LIKE '%foo%';
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: All foo-related tables removed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Some foo-related tables remain (count=$RESULT)"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 9: Primary key validation - table without PK fails
# =============================================================================
# Reference: test_cl_set_vtab.rs:create_invalid_crr() lines 40-52
echo "Test 9: CREATE without PRIMARY KEY fails with clear error"
RESULT=$(run_sql_check_error "CREATE VIRTUAL TABLE bar_schema USING clset (a, b);")
if echo "$RESULT" | grep -qi "no such module"; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif echo "$RESULT" | grep -qi "primary key"; then
    echo "  PASS: Error message mentions primary key requirement"
    PASS=$((PASS + 1))
elif echo "$RESULT" | grep -qi "error"; then
    echo "  PARTIAL: Got an error, but doesn't mention primary key"
    echo "           Error: $RESULT"
    FAIL=$((FAIL + 1))
else
    echo "  FAIL: Expected an error for missing primary key"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test 10: CREATE IF NOT EXISTS is idempotent
# =============================================================================
# Reference: test_cl_set_vtab.rs:create_if_not_exists() lines 54-76
echo "Test 10: CREATE IF NOT EXISTS is idempotent"
RESULT=$(run_sql "
CREATE VIRTUAL TABLE IF NOT EXISTS foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
INSERT INTO foo VALUES (1, 2);
CREATE VIRTUAL TABLE IF NOT EXISTS foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
SELECT count(*) FROM foo;
")
if grep -qi "no such module" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: clset module not found"
    SKIP=$((SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Second CREATE IF NOT EXISTS is a no-op, data preserved"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 1 row after idempotent creates, got $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "clset Virtual Table Tests Summary: $PASS passed, $FAIL failed, $SKIP skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All clset tests passed!"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All clset tests SKIPPED (module not implemented)"
    # Exit 2 indicates tests skipped due to missing implementation
    # This is expected for RED phase of RGRTDD
    exit 2
else
    echo "Some clset tests FAILED"
    exit 1
fi
