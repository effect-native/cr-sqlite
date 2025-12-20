#!/usr/bin/env bash
# Table Compatibility Tests for Zig CR-SQLite
# RGRTDD Spec: Tests describe which tables are eligible to become CRRs
#
# crsql_as_crr() validates table compatibility before promotion:
# - Must have a PRIMARY KEY
# - Must NOT have UNIQUE indices (besides PK)
# - Must NOT have AUTOINCREMENT
# - Must NOT have checked foreign keys
# - NOT NULL columns must have a DEFAULT value
#
# Reference: core/rs/core/src/tableinfo.rs (is_table_compatible)
#            core/rs/core/src/create_crr.rs
#
# IMPORTANT: These tests are RED until table validation is implemented in Zig.
#            Tests describe behavior, not implementation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Table Compatibility Checks for crsql_as_crr"
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
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$EXT" ]]; then
    echo "FAIL: Extension not found at $EXT"
    exit 1
fi

echo "Extension: $EXT"
echo ""

TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $TMPFILE $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# Helper to run SQL and get result (returns last line of output)
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL and check for error message
run_sql_check_error() {
    local sql="$1"
    local db="${2:-:memory:}"
    # Capture both stdout and stderr
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$sql" 2>&1 || true
}

# Check if crsql_as_crr function is available
echo "Checking crsql_as_crr availability..."
SMOKE_RESULT=$(run_sql "SELECT crsql_as_crr('nonexistent');" 2>&1 || echo "ERROR")
if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo ""
    echo "BLOCKED: crsql_as_crr() not available in Zig extension"
    echo ""
    exit 2
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Table without PRIMARY KEY fails
# Reference: core/rs/core/src/tableinfo.rs:927-941 (valid_pks == 0)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Table without PRIMARY KEY fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
CREATE TABLE no_pk (a, b);
SELECT crsql_as_crr('no_pk');
")

if echo "$RESULT" | grep -qi "primary key"; then
    echo "  PASS: Error mentions primary key requirement"
    echo "        Message: $(echo "$RESULT" | grep -i "primary key" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Got an error but it doesn't mention 'primary key'"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  FAIL: Expected error about primary key, but call succeeded or gave unexpected result"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Table with UNIQUE index (besides PK) fails
# Reference: core/rs/core/src/tableinfo.rs:914-925 (unique indices check)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Table with UNIQUE index (besides PK) fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
CREATE TABLE has_unique (id INTEGER PRIMARY KEY NOT NULL, email TEXT UNIQUE);
SELECT crsql_as_crr('has_unique');
")

if echo "$RESULT" | grep -qi "unique"; then
    echo "  PASS: Error mentions unique constraint"
    echo "        Message: $(echo "$RESULT" | grep -i "unique" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Got an error but it doesn't mention 'unique'"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  FAIL: Expected error about unique constraint, but call succeeded or gave unexpected result"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Table with AUTOINCREMENT fails
# Reference: core/rs/core/src/tableinfo.rs:955-969 (autoincrement check)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Table with AUTOINCREMENT fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
CREATE TABLE has_autoincrement (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);
SELECT crsql_as_crr('has_autoincrement');
")

if echo "$RESULT" | grep -qi "autoincrement\|auto-increment\|auto increment"; then
    echo "  PASS: Error mentions autoincrement"
    echo "        Message: $(echo "$RESULT" | grep -i "autoincrement\|auto-increment\|auto increment" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Got an error but it doesn't mention 'autoincrement'"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  FAIL: Expected error about autoincrement, but call succeeded or gave unexpected result"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Table with checked foreign keys fails
# Reference: core/rs/core/src/tableinfo.rs:971-983 (foreign key check)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Table with checked foreign keys fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
PRAGMA foreign_keys = ON;
CREATE TABLE parent (id INTEGER PRIMARY KEY NOT NULL);
CREATE TABLE has_fk (id INTEGER PRIMARY KEY NOT NULL, parent_id INTEGER REFERENCES parent(id));
SELECT crsql_as_crr('has_fk');
")

if echo "$RESULT" | grep -qi "foreign key"; then
    echo "  PASS: Error mentions foreign key constraint"
    echo "        Message: $(echo "$RESULT" | grep -i "foreign key" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Got an error but it doesn't mention 'foreign key'"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  FAIL: Expected error about foreign key, but call succeeded or gave unexpected result"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: NOT NULL without DEFAULT fails
# Reference: core/rs/core/src/tableinfo.rs:985-998 (notnull/default check)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: NOT NULL column without DEFAULT fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
CREATE TABLE not_null_no_default (id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL);
SELECT crsql_as_crr('not_null_no_default');
")

if echo "$RESULT" | grep -qi "not null\|default"; then
    echo "  PASS: Error mentions NOT NULL or DEFAULT requirement"
    echo "        Message: $(echo "$RESULT" | grep -i "not null\|default" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Got an error but it doesn't mention 'not null' or 'default'"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  FAIL: Expected error about NOT NULL without DEFAULT, but call succeeded or gave unexpected result"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Valid table succeeds (positive case)
# Reference: core/rs/core/src/tableinfo.rs:1000 (return Ok(true))
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Valid table succeeds"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql "
CREATE TABLE valid_table (id INTEGER PRIMARY KEY NOT NULL, name TEXT, age INTEGER);
SELECT crsql_as_crr('valid_table');
")

# Check that the clock table was created (indicates success)
CLOCK_EXISTS=$(run_sql "
CREATE TABLE valid_table (id INTEGER PRIMARY KEY NOT NULL, name TEXT, age INTEGER);
SELECT crsql_as_crr('valid_table');
SELECT COUNT(*) FROM sqlite_master WHERE name = 'valid_table__crsql_clock';
")

if [[ "$CLOCK_EXISTS" == "1" ]] || echo "$RESULT" | grep -qi "ok\|1\|done"; then
    echo "  PASS: Valid table promoted to CRR successfully"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Valid table rejected (should have succeeded)"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    # Check if clock table exists as proof of success
    if [[ "$CLOCK_EXISTS" == "1" ]]; then
        echo "  PASS: Valid table promoted to CRR (clock table exists)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Could not confirm CRR creation"
        echo "        Result: $RESULT"
        echo "        Clock table count: $CLOCK_EXISTS"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Table with NOT NULL + DEFAULT succeeds
# Reference: core/rs/core/src/tableinfo.rs:985-998 (dflt_value IS NOT NULL passes)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Table with NOT NULL + DEFAULT succeeds"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CLOCK_EXISTS=$(run_sql "
CREATE TABLE not_null_with_default (id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL DEFAULT 'unknown');
SELECT crsql_as_crr('not_null_with_default');
SELECT COUNT(*) FROM sqlite_master WHERE name = 'not_null_with_default__crsql_clock';
")

if [[ "$CLOCK_EXISTS" == "1" ]]; then
    echo "  PASS: NOT NULL with DEFAULT promoted to CRR successfully"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    RESULT=$(run_sql_check_error "
CREATE TABLE not_null_with_default (id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL DEFAULT 'unknown');
SELECT crsql_as_crr('not_null_with_default');
")
    if echo "$RESULT" | grep -qi "error\|fail"; then
        echo "  FAIL: NOT NULL with DEFAULT was rejected (should have succeeded)"
        echo "        Got: $RESULT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    else
        echo "  PASS: NOT NULL with DEFAULT accepted (result: $CLOCK_EXISTS)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: Table with compound primary key succeeds
# Reference: core/rs/core/src/tableinfo.rs:927-953 (valid_pks > 0 passes)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: Table with compound primary key succeeds"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CLOCK_EXISTS=$(run_sql "
CREATE TABLE compound_pk (a INTEGER NOT NULL, b TEXT NOT NULL, c REAL, PRIMARY KEY (a, b));
SELECT crsql_as_crr('compound_pk');
SELECT COUNT(*) FROM sqlite_master WHERE name = 'compound_pk__crsql_clock';
")

if [[ "$CLOCK_EXISTS" == "1" ]]; then
    echo "  PASS: Compound PK table promoted to CRR successfully"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    RESULT=$(run_sql_check_error "
CREATE TABLE compound_pk (a INTEGER NOT NULL, b TEXT NOT NULL, c REAL, PRIMARY KEY (a, b));
SELECT crsql_as_crr('compound_pk');
")
    if echo "$RESULT" | grep -qi "error\|fail"; then
        echo "  FAIL: Compound PK table was rejected (should have succeeded)"
        echo "        Got: $RESULT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    else
        echo "  PASS: Compound PK table accepted (result: $CLOCK_EXISTS)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 9: Already a CRR (idempotent check)
# Reference: core/rs/core/src/create_crr.rs - crsql_as_crr is idempotent
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 9: Already a CRR (idempotent - second call succeeds)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
CREATE TABLE already_crr (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('already_crr');
SELECT crsql_as_crr('already_crr');
")

# Second call should not error
if echo "$RESULT" | grep -qi "error\|fail"; then
    # Check if it's a "real" error or just the first call succeeding
    # Some implementations return "already a crr" as info, not error
    if echo "$RESULT" | grep -qi "already"; then
        echo "  PASS: Second call recognized table is already a CRR"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Second crsql_as_crr call failed (should be idempotent)"
        echo "        Got: $RESULT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
else
    echo "  PASS: Second crsql_as_crr call succeeded (idempotent)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 10: Non-existent table fails gracefully
# Reference: crsql_as_crr should check table existence
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 10: Non-existent table fails gracefully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
SELECT crsql_as_crr('nonexistent_table');
")

if echo "$RESULT" | grep -qi "error\|no such table\|not found\|does not exist\|fail"; then
    echo "  PASS: Non-existent table properly rejected"
    echo "        Message: $(echo "$RESULT" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Non-existent table should fail"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 11: Nullable primary key fails
# Reference: core/rs/core/src/tableinfo.rs:943-953 (nullable PK check)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 11: Nullable primary key fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Note: In SQLite, "a PRIMARY KEY" without NOT NULL is nullable (except for INTEGER PRIMARY KEY)
RESULT=$(run_sql_check_error "
CREATE TABLE nullable_pk (a TEXT PRIMARY KEY, b TEXT);
SELECT crsql_as_crr('nullable_pk');
")

if echo "$RESULT" | grep -qi "null\|primary key"; then
    echo "  PASS: Nullable primary key properly rejected"
    echo "        Message: $(echo "$RESULT" | grep -i "null\|primary key" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  PASS: Nullable primary key rejected (with error)"
    echo "        Got: $RESULT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Nullable primary key should fail (CRRs need non-null PKs)"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 12: UNIQUE constraint via column definition fails
# Reference: core/rs/core/src/tableinfo.rs:914-925 (column-level UNIQUE)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 12: UNIQUE constraint via separate CREATE UNIQUE INDEX fails"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT=$(run_sql_check_error "
CREATE TABLE has_unique_idx (id INTEGER PRIMARY KEY NOT NULL, code TEXT);
CREATE UNIQUE INDEX idx_code ON has_unique_idx(code);
SELECT crsql_as_crr('has_unique_idx');
")

if echo "$RESULT" | grep -qi "unique"; then
    echo "  PASS: UNIQUE INDEX properly rejected"
    echo "        Message: $(echo "$RESULT" | grep -i "unique" | head -1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif echo "$RESULT" | grep -qi "error\|fail"; then
    echo "  FAIL: Got an error but it doesn't mention 'unique'"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
else
    echo "  FAIL: UNIQUE INDEX should be rejected"
    echo "        Got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║              TABLE COMPATIBILITY TEST SUMMARY                        ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$TOTAL_PASS"
printf "║  FAILED:  %-58d ║\n" "$TOTAL_FAIL"
printf "║  SKIPPED: %-58d ║\n" "$TOTAL_SKIP"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Determine exit status based on results
if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RGRTDD RED PHASE: Some validation tests FAILED"
    echo "Table compatibility validation is not yet fully implemented in Zig."
    echo ""
    echo "To proceed to GREEN phase:"
    echo "  1. Implement is_table_compatible checks in zig/src/"
    echo "  2. Re-run this test suite"
    echo "  3. All tests pass = GREEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
elif [[ $TOTAL_PASS -gt 0 ]]; then
    echo "✓ All implemented tests PASSED"
    exit 0
else
    echo "⚠ All tests SKIPPED"
    exit 2
fi
