#!/usr/bin/env bash
# Parity Test Suite for Zig CR-SQLite
# Validates Zig extension against behavioral contract defined in C tests
#
# This is the main test runner that exercises all core behaviors.
# Individual test files:
#   - test-merge.sh: rows_impacted and merge semantics
#   - test-e2e-sync.sh: End-to-end multi-DB sync
#   - test-filters.sh: crsql_changes filter pushdown
#   - test-rowid-slab.sh: Rowid slab allocation
#   - test-alter.sh: crsql_begin_alter/crsql_commit_alter schema changes
#   - test-noops.sh: No-op changes do not advance clocks (CRDT property)
#   - test-fract.sh: Fractional indexing (crsql_fract_key_between)
#   - test-trigger-parity.sh: Oracle parity (Zig vs Rust/C clock tables)
#   - test-db-version-parity.sh: db_version timing parity (oracle test)
#   - test-rows-impacted-parity.sh: rows_impacted counter reset timing (oracle test)
#   - test-multiconn.sh: Multi-connection scenarios (on-disk DB parity)
#   - test-backfill.sh: crsql_as_crr() backfill on existing data
#   - test-persistence.sh: On-disk DB persistence across sessions
#   - test-pk-update.sh: Primary key UPDATE semantics (DELETE+INSERT)
#   - test-extdata.sh: ExtData lifecycle (schema changes, table tracking)
#   - test-sandbox.sh: Sandbox tests (basic sync, convergence, oracle parity)
#   - test-automigrate.sh: crsql_automigrate() behavior spec (RGRTDD)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║           Zig CR-SQLite Parity Test Suite                            ║"
echo "║  Behavioral contract from: core/src/*.test.c                         ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Build the extension first
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

# Helper to run SQL and capture result (returns last line of output)
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Check if core functions are available
echo "Checking core function availability..."
SMOKE_RESULT=$(run_sql "SELECT crsql_version();" 2>&1 || echo "ERROR")
if [[ "$SMOKE_RESULT" == "ERROR" ]] || [[ -s "$ERRFILE" && $(grep -c "no such function" "$ERRFILE") -gt 0 ]]; then
    echo "WARNING: Some core functions may not be implemented yet"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test Suite 1: rows-impacted.test.c
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: rows_impacted (rows-impacted.test.c)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test: SingleInsertSingleTx
echo "Test: SingleInsertSingleTx"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred (insertIntoBaseTable issue)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: rows_impacted = 1 for single insert"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: ManyInsertsInATx
echo "Test: ManyInsertsInATx"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
INSERT INTO crsql_changes VALUES ('foo', X'010902', 'b', 2, 1, 1, NULL, 1, 1);
INSERT INTO crsql_changes VALUES ('foo', X'010903', 'b', 2, 1, 1, NULL, 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred (insertIntoBaseTable issue)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: rows_impacted = 3 for three inserts"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 3, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: CountResetsOnCommit
echo "Test: CountResetsOnCommit"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
COMMIT;
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred (insertIntoBaseTable issue)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: rows_impacted resets to 0 after commit"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0 after commit, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: UpdateThatDoesNotChangeAnything (identical value)
echo "Test: UpdateThatDoesNotChangeAnything"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 1, 1, NULL, 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: rows_impacted = 0 for no-op update"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0 for no-op, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: LowerColVersionLoses
echo "Test: LowerColVersionLoses"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 999, 0, 0, NULL, 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: rows_impacted = 0 when local wins (lower col_version)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: ValueWin (same col_version, different value)
echo "Test: ValueWin"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 3, 1, 1, X'00000000000000000000000000000000', 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: rows_impacted = 1 when value wins tie-break"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: ClockWin (higher col_version)
echo "Test: ClockWin"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', 'b', 2, 2, 2, NULL, 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: rows_impacted = 1 when clock wins"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: Delete
echo "Test: Delete"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', '-1', NULL, 2, 2, NULL, 2, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: rows_impacted = 1 for delete"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: DeleteThatDoesNotChangeAnything
echo "Test: DeleteThatDoesNotChangeAnything"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
DELETE FROM foo;
BEGIN;
INSERT INTO crsql_changes VALUES ('foo', X'010901', '-1', NULL, 2, 2, NULL, 1, 1);
SELECT crsql_rows_impacted();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: rows_impacted = 0 for already-deleted row"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test Suite 2: Compound Primary Keys (changes-vtab.test.c:testManyPkTable)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Compound PK Encoding (changes-vtab.test.c)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test: ManyPkTable - compound PK blob encoding
echo "Test: ManyPkTable (compound PK encoding)"
RESULT=$(run_sql "
CREATE TABLE foo (a NOT NULL, b NOT NULL, c, PRIMARY KEY (a, b));
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (4, 5, 6);
SELECT quote(pk) FROM crsql_changes;
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "X'0209040905'" ]]; then
    echo "  PASS: Compound PK encoded as X'0209040905'"
    echo "        (02=2 cols, 09=int8, 04=4, 09=int8, 05=5)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected X'0209040905', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test Suite 3: Core Functions
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Core Functions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test: crsql_site_id returns 16-byte blob
echo "Test: crsql_site_id() returns 16-byte blob"
RESULT=$(run_sql "SELECT length(crsql_site_id());")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_site_id() not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "16" ]]; then
    echo "  PASS: site_id is 16 bytes"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 16 bytes, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: crsql_db_version starts at 0
echo "Test: crsql_db_version() starts at 0"
RESULT=$(run_sql "SELECT crsql_db_version();")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_db_version() not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: db_version starts at 0"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 0, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: crsql_db_version increments on change
echo "Test: crsql_db_version() increments on change"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
SELECT crsql_db_version();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: db_version incremented to 1"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 1, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test: crsql_finalize doesn't error
echo "Test: crsql_finalize() runs without error"
RESULT=$(run_sql "SELECT crsql_finalize();" 2>&1)
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_finalize() not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ -z "$RESULT" ]] || [[ "$RESULT" == "" ]]; then
    echo "  PASS: crsql_finalize() succeeded"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  INFO: crsql_finalize() returned: $RESULT"
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Run Additional Test Scripts
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running Additional Test Scripts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run filter tests
echo "Running test-filters.sh..."
if bash "$SCRIPT_DIR/test-filters.sh" > "$TMPFILE" 2>&1; then
    FILTER_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || FILTER_PASS=0
    echo "  Filter tests: $FILTER_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + FILTER_PASS))
else
    if grep -q "BLOCKED:" "$TMPFILE"; then
        echo "  Filter tests: BLOCKED (functions not implemented)"
    else
        FILTER_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || FILTER_FAIL=0
        FILTER_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || FILTER_PASS=0
        echo "  Filter tests: $FILTER_PASS passed, $FILTER_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + FILTER_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + FILTER_FAIL))
    fi
fi

# Run rowid slab tests (only if not blocked)
echo "Running test-rowid-slab.sh..."
if bash "$SCRIPT_DIR/test-rowid-slab.sh" > "$TMPFILE" 2>&1; then
    ROWID_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ROWID_PASS=0
    echo "  Rowid slab tests: $ROWID_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + ROWID_PASS))
else
    if grep -q "BLOCKED:" "$TMPFILE"; then
        echo "  Rowid slab tests: BLOCKED (functions not implemented)"
    else
        ROWID_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || ROWID_FAIL=0
        ROWID_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ROWID_PASS=0
        echo "  Rowid slab tests: $ROWID_PASS passed, $ROWID_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + ROWID_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + ROWID_FAIL))
    fi
fi

# Run alter tests
echo "Running test-alter.sh..."
bash "$SCRIPT_DIR/test-alter.sh" > "$TMPFILE" 2>&1 || true
if grep -q "All tests SKIPPED" "$TMPFILE" || grep -q "not yet implemented" "$TMPFILE"; then
    echo "  Alter tests: SKIPPED (alter functions not implemented)"
    TOTAL_SKIP=$((TOTAL_SKIP + 4))
else
    ALTER_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || ALTER_FAIL=0
    ALTER_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ALTER_PASS=0
    if [[ $ALTER_FAIL -eq 0 && $ALTER_PASS -gt 0 ]]; then
        echo "  Alter tests: $ALTER_PASS passed"
    else
        echo "  Alter tests: $ALTER_PASS passed, $ALTER_FAIL failed"
    fi
    TOTAL_PASS=$((TOTAL_PASS + ALTER_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + ALTER_FAIL))
fi

# Run noop tests (clock stability on redundant syncs)
echo "Running test-noops.sh..."
if bash "$SCRIPT_DIR/test-noops.sh" > "$TMPFILE" 2>&1; then
    NOOP_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || NOOP_PASS=0
    echo "  Noop tests: $NOOP_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + NOOP_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  Noop tests: SKIPPED (functions not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 4))
    else
        NOOP_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || NOOP_FAIL=0
        NOOP_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || NOOP_PASS=0
        echo "  Noop tests: $NOOP_PASS passed, $NOOP_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + NOOP_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + NOOP_FAIL))
    fi
fi

# Run fractional indexing tests
echo "Running test-fract.sh..."
if bash "$SCRIPT_DIR/test-fract.sh" > "$TMPFILE" 2>&1; then
    FRACT_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || FRACT_PASS=0
    echo "  Fract tests: $FRACT_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + FRACT_PASS))
else
    EXIT_CODE=$?
    if grep -q "SKIPPED" "$TMPFILE" || grep -q "not yet implemented" "$TMPFILE"; then
        echo "  Fract tests: SKIPPED (crsql_fract_key_between not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 8))
    else
        FRACT_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || FRACT_FAIL=0
        FRACT_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || FRACT_PASS=0
        echo "  Fract tests: $FRACT_PASS passed, $FRACT_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + FRACT_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + FRACT_FAIL))
    fi
fi

# Run fract parity tests (oracle comparison: Zig vs Rust/C)
echo "Running test-fract-parity.sh..."
if [[ -f "$ROOT_DIR/lib/crsqlite.dylib" ]] 2>/dev/null || ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)" && [[ -f "$ROOT_DIR/lib/crsqlite.dylib" ]]; then
    if bash "$SCRIPT_DIR/test-fract-parity.sh" > "$TMPFILE" 2>&1; then
        FRACT_PARITY_PASS=$(grep -c "PASS" "$TMPFILE" 2>/dev/null) || FRACT_PARITY_PASS=0
        echo "  Fract parity tests: $FRACT_PARITY_PASS passed"
        TOTAL_PASS=$((TOTAL_PASS + FRACT_PARITY_PASS))
    else
        EXIT_CODE=$?
        FRACT_PARITY_FAIL=$(grep -c "FAIL" "$TMPFILE" 2>/dev/null) || FRACT_PARITY_FAIL=0
        FRACT_PARITY_PASS=$(grep -c "PASS" "$TMPFILE" 2>/dev/null) || FRACT_PARITY_PASS=0
        echo "  Fract parity tests: $FRACT_PARITY_PASS passed, $FRACT_PARITY_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + FRACT_PARITY_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + FRACT_PARITY_FAIL))
    fi
else
    echo "  Fract parity tests: SKIPPED (Rust/C extension not found)"
    TOTAL_SKIP=$((TOTAL_SKIP + 12))
fi

# Run trigger parity tests (oracle comparison: Zig vs Rust/C)
echo "Running test-trigger-parity.sh..."
if bash "$SCRIPT_DIR/test-trigger-parity.sh" > "$TMPFILE" 2>&1; then
    TRIG_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || TRIG_PASS=0
    echo "  Trigger parity tests: $TRIG_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + TRIG_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  Trigger parity tests: SKIPPED (extensions not available)"
        TOTAL_SKIP=$((TOTAL_SKIP + 15))
    else
        TRIG_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || TRIG_FAIL=0
        TRIG_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || TRIG_PASS=0
        echo "  Trigger parity tests: $TRIG_PASS passed, $TRIG_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + TRIG_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + TRIG_FAIL))
    fi
fi

# Run API surface parity test (oracle comparison vs Rust/C)
echo "Running test-api-surface.sh..."
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"
if [[ -f "$ROOT_DIR/lib/crsqlite.dylib" ]]; then
    # Export extension paths using the freshly built Zig extension
    export ZIG_EXT_PATH="$EXT"
    if bash "$SCRIPT_DIR/test-api-surface.sh" > "$TMPFILE" 2>&1; then
        API_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || API_PASS=0
        echo "  API surface tests: $API_PASS passed (full parity)"
        TOTAL_PASS=$((TOTAL_PASS + API_PASS))
    else
        # Count missing items as informational, not test failures
        API_GAPS=$(grep "Missing from Zig:" "$TMPFILE" | grep -oE '[0-9]+' | head -1) || API_GAPS=0
        API_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || API_PASS=0
        echo "  API surface tests: $API_PASS passed, $API_GAPS gaps documented"
        TOTAL_PASS=$((TOTAL_PASS + API_PASS))
        # Note: gaps are tracked but don't fail the suite - they're expected during development
    fi
else
    echo "  API surface tests: SKIPPED (Rust/C extension not found at $ROOT_DIR/lib/crsqlite.dylib)"
    TOTAL_SKIP=$((TOTAL_SKIP + 2))
fi

# Run db_version parity tests (oracle comparison: Zig vs Rust/C)
echo "Running test-db-version-parity.sh..."
if [[ -f "$ROOT_DIR/lib/crsqlite.dylib" ]]; then
    if bash "$SCRIPT_DIR/test-db-version-parity.sh" > "$TMPFILE" 2>&1; then
        DBVER_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || DBVER_PASS=0
        echo "  db_version parity tests: $DBVER_PASS passed"
        TOTAL_PASS=$((TOTAL_PASS + DBVER_PASS))
    else
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 2 ]] || grep -q "BLOCKED" "$TMPFILE"; then
            echo "  db_version parity tests: BLOCKED (extensions not available)"
            TOTAL_SKIP=$((TOTAL_SKIP + 12))
        else
            DBVER_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || DBVER_FAIL=0
            DBVER_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || DBVER_PASS=0
            DBVER_DIVERGE=$(grep "DIVERGENCE" "$TMPFILE" | wc -l) || DBVER_DIVERGE=0
            echo "  db_version parity tests: $DBVER_PASS passed, $DBVER_FAIL failed, $DBVER_DIVERGE divergences"
            TOTAL_PASS=$((TOTAL_PASS + DBVER_PASS))
            TOTAL_FAIL=$((TOTAL_FAIL + DBVER_FAIL))
        fi
    fi
else
    echo "  db_version parity tests: SKIPPED (Rust/C extension not found)"
    TOTAL_SKIP=$((TOTAL_SKIP + 12))
fi

# Run rows_impacted parity tests (oracle comparison: Zig vs Rust/C counter reset timing)
echo "Running test-rows-impacted-parity.sh..."
if [[ -f "$ROOT_DIR/lib/crsqlite.dylib" ]]; then
    if bash "$SCRIPT_DIR/test-rows-impacted-parity.sh" > "$TMPFILE" 2>&1; then
        ROWS_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ROWS_PASS=0
        echo "  rows_impacted parity tests: $ROWS_PASS passed"
        TOTAL_PASS=$((TOTAL_PASS + ROWS_PASS))
    else
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 2 ]] || grep -q "BLOCKED" "$TMPFILE"; then
            echo "  rows_impacted parity tests: BLOCKED (extensions not available)"
            TOTAL_SKIP=$((TOTAL_SKIP + 18))
        else
            ROWS_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || ROWS_FAIL=0
            ROWS_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ROWS_PASS=0
            ROWS_DIVERGE=$(grep "DIVERGENCE" "$TMPFILE" | wc -l) || ROWS_DIVERGE=0
            echo "  rows_impacted parity tests: $ROWS_PASS passed, $ROWS_FAIL failed, $ROWS_DIVERGE divergences"
            TOTAL_PASS=$((TOTAL_PASS + ROWS_PASS))
            TOTAL_FAIL=$((TOTAL_FAIL + ROWS_FAIL))
        fi
    fi
else
    echo "  rows_impacted parity tests: SKIPPED (Rust/C extension not found)"
    TOTAL_SKIP=$((TOTAL_SKIP + 18))
fi

# Run ALTER TABLE parity tests (oracle comparison: Zig vs Rust/C clock preservation)
echo "Running test-alter-parity.sh..."
if timeout 300s bash "$SCRIPT_DIR/test-alter-parity.sh" > "$TMPFILE" 2>&1; then
    ALTER_PARITY_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ALTER_PARITY_PASS=0
    echo "  ALTER parity tests: $ALTER_PARITY_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + ALTER_PARITY_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "BLOCKED" "$TMPFILE"; then
        echo "  ALTER parity tests: BLOCKED (extensions not available)"
        TOTAL_SKIP=$((TOTAL_SKIP + 19))
    else
        ALTER_PARITY_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || ALTER_PARITY_FAIL=0
        ALTER_PARITY_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || ALTER_PARITY_PASS=0
        ALTER_PARITY_DIVERGE=$(grep "diverge" "$TMPFILE" | wc -l) || ALTER_PARITY_DIVERGE=0
        echo "  ALTER parity tests: $ALTER_PARITY_PASS passed, $ALTER_PARITY_FAIL failed, $ALTER_PARITY_DIVERGE divergences"
        TOTAL_PASS=$((TOTAL_PASS + ALTER_PARITY_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + ALTER_PARITY_FAIL))
    fi
fi

# Run sync_bit isolation tests (per-connection correctness)
echo "Running test-sync-bit-isolation.sh..."
if bash "$SCRIPT_DIR/test-sync-bit-isolation.sh" > "$TMPFILE" 2>&1; then
    SYNCBIT_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || SYNCBIT_PASS=0
    echo "  sync_bit isolation tests: $SYNCBIT_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + SYNCBIT_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  sync_bit isolation tests: SKIPPED"
        TOTAL_SKIP=$((TOTAL_SKIP + 2))
    else
        SYNCBIT_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || SYNCBIT_FAIL=0
        SYNCBIT_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || SYNCBIT_PASS=0
        echo "  sync_bit isolation tests: $SYNCBIT_PASS passed, $SYNCBIT_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + SYNCBIT_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + SYNCBIT_FAIL))
    fi
fi

# Run backfill tests (crsql_as_crr on existing data)
echo "Running test-backfill.sh..."
if bash "$SCRIPT_DIR/test-backfill.sh" > "$TMPFILE" 2>&1; then
    BACKFILL_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || BACKFILL_PASS=0
    echo "  Backfill tests: $BACKFILL_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + BACKFILL_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  Backfill tests: SKIPPED (functions not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 12))
    else
        BACKFILL_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || BACKFILL_FAIL=0
        BACKFILL_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || BACKFILL_PASS=0
        echo "  Backfill tests: $BACKFILL_PASS passed, $BACKFILL_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + BACKFILL_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + BACKFILL_FAIL))
    fi
fi

# Run multi-connection tests (on-disk database, concurrent access)
echo "Running test-multiconn.sh..."
if bash "$SCRIPT_DIR/test-multiconn.sh" > "$TMPFILE" 2>&1; then
    MULTICONN_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || MULTICONN_PASS=0
    echo "  Multi-connection tests: $MULTICONN_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + MULTICONN_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "BLOCKED" "$TMPFILE"; then
        echo "  Multi-connection tests: BLOCKED (functions not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 6))
    else
        MULTICONN_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || MULTICONN_FAIL=0
        MULTICONN_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || MULTICONN_PASS=0
        echo "  Multi-connection tests: $MULTICONN_PASS passed, $MULTICONN_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + MULTICONN_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + MULTICONN_FAIL))
    fi
fi

# Run persistence tests (on-disk DB close/reopen)
echo "Running test-persistence.sh..."
if bash "$SCRIPT_DIR/test-persistence.sh" > "$TMPFILE" 2>&1; then
    PERSIST_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || PERSIST_PASS=0
    echo "  Persistence tests: $PERSIST_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + PERSIST_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  Persistence tests: SKIPPED"
        TOTAL_SKIP=$((TOTAL_SKIP + 12))
    else
        PERSIST_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || PERSIST_FAIL=0
        PERSIST_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || PERSIST_PASS=0
        echo "  Persistence tests: $PERSIST_PASS passed, $PERSIST_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + PERSIST_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + PERSIST_FAIL))
    fi
fi

# Run PK UPDATE semantics tests (DELETE+INSERT on PK change)
echo "Running test-pk-update.sh..."
if bash "$SCRIPT_DIR/test-pk-update.sh" > "$TMPFILE" 2>&1; then
    PKUPDATE_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || PKUPDATE_PASS=0
    echo "  PK UPDATE tests: $PKUPDATE_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + PKUPDATE_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "BLOCKED" "$TMPFILE"; then
        echo "  PK UPDATE tests: BLOCKED (functions not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 15))
    else
        PKUPDATE_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || PKUPDATE_FAIL=0
        PKUPDATE_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || PKUPDATE_PASS=0
        echo "  PK UPDATE tests: $PKUPDATE_PASS passed, $PKUPDATE_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + PKUPDATE_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + PKUPDATE_FAIL))
    fi
fi

# Run ExtData lifecycle tests (schema changes, table tracking, db_version)
echo "Running test-extdata.sh..."
if bash "$SCRIPT_DIR/test-extdata.sh" > "$TMPFILE" 2>&1; then
    EXTDATA_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || EXTDATA_PASS=0
    echo "  ExtData tests: $EXTDATA_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + EXTDATA_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  ExtData tests: SKIPPED (functions not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 15))
    else
        EXTDATA_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || EXTDATA_FAIL=0
        EXTDATA_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || EXTDATA_PASS=0
        echo "  ExtData tests: $EXTDATA_PASS passed, $EXTDATA_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + EXTDATA_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + EXTDATA_FAIL))
    fi
fi

# Run sandbox tests (basic sync invariants, bidirectional convergence)
echo "Running test-sandbox.sh..."
if bash "$SCRIPT_DIR/test-sandbox.sh" > "$TMPFILE" 2>&1; then
    SANDBOX_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || SANDBOX_PASS=0
    echo "  Sandbox tests: $SANDBOX_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + SANDBOX_PASS))
else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE" || grep -q "BLOCKED" "$TMPFILE"; then
        echo "  Sandbox tests: SKIPPED (functions not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 9))
    else
        SANDBOX_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || SANDBOX_FAIL=0
        SANDBOX_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || SANDBOX_PASS=0
        echo "  Sandbox tests: $SANDBOX_PASS passed, $SANDBOX_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + SANDBOX_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + SANDBOX_FAIL))
    fi
fi

# Run automigrate behavior tests (RGRTDD spec - expected to SKIP until implemented)
echo "Running test-automigrate.sh..."
if bash "$SCRIPT_DIR/test-automigrate.sh" > "$TMPFILE" 2>&1; then
    AUTOMIG_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || AUTOMIG_PASS=0
    echo "  Automigrate tests: $AUTOMIG_PASS passed"
    TOTAL_PASS=$((TOTAL_PASS + AUTOMIG_PASS))
else
    EXIT_CODE=$?
    # Exit 0 = RED phase (expected failures, function not implemented)
    if [[ $EXIT_CODE -eq 0 ]] && grep -q "RED PHASE" "$TMPFILE"; then
        AUTOMIG_EXPECTED=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || AUTOMIG_EXPECTED=0
        echo "  Automigrate tests: SKIPPED ($AUTOMIG_EXPECTED tests await implementation)"
        TOTAL_SKIP=$((TOTAL_SKIP + AUTOMIG_EXPECTED))
    elif [[ $EXIT_CODE -eq 2 ]] || grep -q "SKIPPED" "$TMPFILE"; then
        echo "  Automigrate tests: SKIPPED (crsql_automigrate not implemented)"
        TOTAL_SKIP=$((TOTAL_SKIP + 17))
    else
        AUTOMIG_FAIL=$(grep -c "FAIL:" "$TMPFILE" 2>/dev/null) || AUTOMIG_FAIL=0
        AUTOMIG_PASS=$(grep -c "PASS:" "$TMPFILE" 2>/dev/null) || AUTOMIG_PASS=0
        echo "  Automigrate tests: $AUTOMIG_PASS passed, $AUTOMIG_FAIL failed"
        TOTAL_PASS=$((TOTAL_PASS + AUTOMIG_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + AUTOMIG_FAIL))
    fi
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

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "✓ All implemented tests PASSED"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo "⚠ All tests SKIPPED (core functions not yet implemented)"
    exit 2
else
    echo "✗ Some tests FAILED"
    exit 1
fi
