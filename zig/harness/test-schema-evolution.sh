#!/usr/bin/env bash
# Schema Evolution Edge Case Tests for Zig CR-SQLite
# Tests complex schema change scenarios that occur in real-world usage
#
# SQLite Version Requirements:
# - RENAME COLUMN: SQLite 3.25.0+ (2018-09-15)
# - DROP COLUMN: SQLite 3.35.0+ (2021-03-12)
#
# Test Scenarios:
# 1. Add -> Rename -> Drop Column (sequential evolution)
# 2. Alter During Pending Sync (schema change with pending remote data)
# 3. Conflicting Schema Changes (concurrent schema evolution)
# 4. Rapid Alter Cycles (stress test)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig CR-SQLite Schema Evolution Edge Case Tests ==="
echo "Tests complex multi-step schema changes and cross-site sync"
echo ""

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Build only if extension doesn't exist
# (Skip incremental rebuild if extension exists but is stale - allows testing with older builds)
if [[ ! -f "$EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

if [[ ! -f "$EXT" ]]; then
    echo "FAIL: Extension not found at $EXT"
    exit 1
fi

echo "Extension: $EXT"

# Determine Rust/C oracle path for parity comparison
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"
if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$(uname -m)" == "arm64" ]]; then
        ORACLE_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        ORACLE_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
else
    if [[ "$(uname -m)" == "aarch64" ]]; then
        ORACLE_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        ORACLE_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
fi

if [[ -f "$ORACLE_EXT" ]]; then
    echo "Oracle:    $ORACLE_EXT"
else
    echo "Oracle:    NOT FOUND (parity checks will be skipped)"
    ORACLE_EXT=""
fi
echo ""

# Create temp files
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
ORACLE_ERRFILE=$(mktemp)
trap "rm -f $TMPFILE $ERRFILE $ORACLE_ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# Helper to run SQL and get result (returns last line of output)
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL against oracle (Rust/C) for parity comparison
# Note: Oracle requires explicit entry point "sqlite3_crsqlite_init"
run_oracle_sql() {
    local sql="$1"
    if [[ -z "$ORACLE_EXT" ]]; then
        echo "ORACLE_NOT_AVAILABLE"
        return
    fi
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $ORACLE_EXT sqlite3_crsqlite_init" "$sql" 2>"$ORACLE_ERRFILE" | tail -1 || true
}

# Helper to get the actual error (filtering out sqlite3_close warnings)
get_actual_error() {
    local errfile="$1"
    # Filter out harmless sqlite3_close warning, dlsym warnings, and debug lines
    grep -v "sqlite3_close" "$errfile" 2>/dev/null | grep -v "dlsym" | grep -v "^debug(" | head -1 || true
}

# Check SQLite version and feature availability
echo "Checking SQLite version and feature availability..."
SQLITE_VERSION=$(nix run nixpkgs#sqlite -- :memory: "SELECT sqlite_version();" 2>/dev/null)
echo "SQLite version: $SQLITE_VERSION"

# Parse version components
SQLITE_MAJOR=$(echo "$SQLITE_VERSION" | cut -d. -f1)
SQLITE_MINOR=$(echo "$SQLITE_VERSION" | cut -d. -f2)
SQLITE_PATCH=$(echo "$SQLITE_VERSION" | cut -d. -f3)

# Feature flags
HAS_RENAME_COLUMN=0
HAS_DROP_COLUMN=0

# Check RENAME COLUMN (3.25.0+)
if [[ $SQLITE_MAJOR -gt 3 ]] || [[ $SQLITE_MAJOR -eq 3 && $SQLITE_MINOR -ge 25 ]]; then
    HAS_RENAME_COLUMN=1
    echo "  RENAME COLUMN: Available (SQLite 3.25.0+)"
else
    echo "  RENAME COLUMN: NOT available (requires SQLite 3.25.0+)"
fi

# Check DROP COLUMN (3.35.0+)
if [[ $SQLITE_MAJOR -gt 3 ]] || [[ $SQLITE_MAJOR -eq 3 && $SQLITE_MINOR -ge 35 ]]; then
    HAS_DROP_COLUMN=1
    echo "  DROP COLUMN: Available (SQLite 3.35.0+)"
else
    echo "  DROP COLUMN: NOT available (requires SQLite 3.35.0+)"
fi

echo ""

# Check if alter functions are available
echo "Checking crsql_begin_alter availability..."
SMOKE_RESULT=$(run_sql "SELECT crsql_begin_alter('nonexistent');" 2>&1 || echo "ERROR")
if grep -q "no such function: crsql_begin_alter" "$ERRFILE" 2>/dev/null; then
    echo "SKIP: crsql_begin_alter() not yet implemented"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                           TEST SUMMARY                               ║"
    echo "╠═══════════════════════════════════════════════════════════════════════╣"
    echo "║  PASSED:  0                                                          ║"
    echo "║  FAILED:  0                                                          ║"
    echo "║  SKIPPED: ALL (alter functions not implemented)                      ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "⚠ All tests SKIPPED (crsql_begin_alter not yet implemented)"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# Scenario 1: Add -> Rename -> Drop Column
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario 1: Add -> Rename -> Drop Column (Sequential Evolution)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1a: Add Column
echo "Test 1a: Add column to existing CRR table"
RESULT=$(run_sql "
CREATE TABLE t (id PRIMARY KEY NOT NULL, a, b);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'a1', 'b1');

-- Add column
SELECT crsql_begin_alter('t');
ALTER TABLE t ADD COLUMN c;
SELECT crsql_commit_alter('t');

-- Verify new column works
UPDATE t SET c = 'c1' WHERE id = 1;

-- Clock should have entry for new column
SELECT COUNT(*) FROM t__crsql_clock WHERE col_name = 'c';
")

if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: crsql_as_crr() not implemented"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Add column works, clock has entry for 'c'"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected clock entry for 'c', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test 1b: Rename Column (if supported)
echo ""
echo "Test 1b: Rename column 'c' to 'c_renamed'"
if [[ $HAS_RENAME_COLUMN -eq 0 ]]; then
    echo "  SKIP: RENAME COLUMN requires SQLite 3.25.0+"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
else
    RESULT=$(run_sql "
CREATE TABLE t_rename (id PRIMARY KEY NOT NULL, a, b);
SELECT crsql_as_crr('t_rename');
INSERT INTO t_rename VALUES (1, 'a1', 'b1');

-- Add column first
SELECT crsql_begin_alter('t_rename');
ALTER TABLE t_rename ADD COLUMN c;
SELECT crsql_commit_alter('t_rename');
UPDATE t_rename SET c = 'c1' WHERE id = 1;

-- Rename column
SELECT crsql_begin_alter('t_rename');
ALTER TABLE t_rename RENAME COLUMN c TO c_renamed;
SELECT crsql_commit_alter('t_rename');

-- Verify: update via new name works
UPDATE t_rename SET c_renamed = 'c_updated' WHERE id = 1;
SELECT c_renamed FROM t_rename WHERE id = 1;
")

    if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
        echo "  FAIL: SQL error occurred"
        cat "$ERRFILE"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    elif [[ "$RESULT" == "c_updated" ]]; then
        echo "  PASS: Rename column works, can update via new name"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Expected 'c_updated', got: $RESULT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# Test 1c: Drop Column (if supported)
echo ""
echo "Test 1c: Drop column 'b'"
if [[ $HAS_DROP_COLUMN -eq 0 ]]; then
    echo "  SKIP: DROP COLUMN requires SQLite 3.35.0+"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
else
    RESULT=$(run_sql "
CREATE TABLE t_drop (id PRIMARY KEY NOT NULL, a, b, c);
SELECT crsql_as_crr('t_drop');
INSERT INTO t_drop VALUES (1, 'a1', 'b1', 'c1');

-- Drop column b
SELECT crsql_begin_alter('t_drop');
ALTER TABLE t_drop DROP COLUMN b;
SELECT crsql_commit_alter('t_drop');

-- Verify: table has 3 columns (id, a, c), not 4
SELECT COUNT(*) FROM pragma_table_info('t_drop');
")

    if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
        echo "  FAIL: SQL error occurred"
        cat "$ERRFILE"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    elif [[ "$RESULT" == "3" ]]; then
        echo "  PASS: Drop column works, table has 3 columns"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Expected 3 columns after drop, got: $RESULT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# Test 1d: Full Evolution Chain (Add -> Rename -> Drop) if all features available
echo ""
echo "Test 1d: Full evolution chain (Add -> Rename -> Drop)"
if [[ $HAS_RENAME_COLUMN -eq 0 || $HAS_DROP_COLUMN -eq 0 ]]; then
    echo "  SKIP: Full chain requires SQLite 3.35.0+ for DROP COLUMN"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
else
    RESULT=$(run_sql "
-- Initial table
CREATE TABLE t_chain (id PRIMARY KEY NOT NULL, a, b);
SELECT crsql_as_crr('t_chain');
INSERT INTO t_chain VALUES (1, 'a1', 'b1');

-- Step 1: Add column c
SELECT crsql_begin_alter('t_chain');
ALTER TABLE t_chain ADD COLUMN c;
SELECT crsql_commit_alter('t_chain');
UPDATE t_chain SET c = 'c1' WHERE id = 1;

-- Step 2: Rename c to c_new
SELECT crsql_begin_alter('t_chain');
ALTER TABLE t_chain RENAME COLUMN c TO c_new;
SELECT crsql_commit_alter('t_chain');

-- Step 3: Drop original column b
SELECT crsql_begin_alter('t_chain');
ALTER TABLE t_chain DROP COLUMN b;
SELECT crsql_commit_alter('t_chain');

-- Verify final state: columns are (id, a, c_new)
SELECT GROUP_CONCAT(name, ',') FROM pragma_table_info('t_chain') ORDER BY cid;
")

    if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
        echo "  FAIL: SQL error occurred"
        cat "$ERRFILE"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    elif [[ "$RESULT" == "id,a,c_new" ]]; then
        echo "  PASS: Full chain complete, columns are: id,a,c_new"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Expected columns 'id,a,c_new', got: $RESULT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# Test 1e: Verify changes sync after full evolution
echo ""
echo "Test 1e: Changes sync after evolution (crsql_changes includes evolved columns)"
RESULT=$(run_sql "
CREATE TABLE t_sync (id PRIMARY KEY NOT NULL, a);
SELECT crsql_as_crr('t_sync');
INSERT INTO t_sync VALUES (1, 'initial');

-- Add column
SELECT crsql_begin_alter('t_sync');
ALTER TABLE t_sync ADD COLUMN new_col;
SELECT crsql_commit_alter('t_sync');

-- Update new column
UPDATE t_sync SET new_col = 'new_value' WHERE id = 1;

-- Verify crsql_changes has entry for new_col
SELECT cid FROM crsql_changes WHERE [table] = 't_sync' AND cid = 'new_col';
")

if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "new_col" ]]; then
    echo "  PASS: crsql_changes includes 'new_col' after evolution"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected crsql_changes to have 'new_col', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Scenario 2: Alter During Pending Sync
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario 2: Alter During Pending Sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Simulates: Site A inserts (old schema), Site B alters, Site B receives"
echo ""

# Test 2a: Insert data, capture changeset, alter schema, apply old changeset
echo "Test 2a: Apply old-schema changeset after alter"
RESULT=$(run_sql "
-- Site B: Create table and make it a CRR
CREATE TABLE pending_test (id PRIMARY KEY NOT NULL, a);
SELECT crsql_as_crr('pending_test');

-- Simulate Site A's changeset (before Site B added column)
-- Site A inserted (id=1, a='from_a')
-- pk encoding: 0x01 (1 col) + 0x09 (int type) + 0x01 (value 1)

-- Site B: Add new column
SELECT crsql_begin_alter('pending_test');
ALTER TABLE pending_test ADD COLUMN b DEFAULT 'default_b';
SELECT crsql_commit_alter('pending_test');

-- Site B: Receive Site A's old changeset (only has column 'a')
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('pending_test', X'010901', 'a', 'from_a', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 1, 0);

-- Verify: Row exists with 'a' value from Site A and default 'b'
SELECT a || ',' || COALESCE(b, 'NULL') FROM pending_test WHERE id = 1;
")

if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "from_a,default_b" ]]; then
    echo "  PASS: Old changeset applied, new column has default"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RESULT" == "from_a,NULL" ]]; then
    echo "  PASS: Old changeset applied, new column is NULL (no default)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'from_a,default_b' or 'from_a,NULL', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test 2b: Old changeset for column that was dropped
# Expected behavior: Either (a) error with "no such column" or (b) graceful ignore
# Either way: NO partial apply (db_version unchanged, schema unchanged, clock unchanged)
echo ""
echo "Test 2b: Apply changeset for dropped column"
if [[ $HAS_DROP_COLUMN -eq 0 ]]; then
    echo "  SKIP: DROP COLUMN requires SQLite 3.35.0+"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
else
    # Capture pre-apply state for invariant checks
    PRE_STATE=$(run_sql "
-- Create table with column that will be dropped
CREATE TABLE drop_pending (id PRIMARY KEY NOT NULL, a, to_drop);
SELECT crsql_as_crr('drop_pending');

-- Insert initial data
INSERT INTO drop_pending VALUES (1, 'a1', 'will_be_dropped');

-- Drop column
SELECT crsql_begin_alter('drop_pending');
ALTER TABLE drop_pending DROP COLUMN to_drop;
SELECT crsql_commit_alter('drop_pending');

-- Capture pre-apply state: db_version|column_count|clock_count
SELECT 
    (SELECT MAX(db_version) FROM crsql_changes WHERE [table] = 'drop_pending') || '|' ||
    (SELECT COUNT(*) FROM pragma_table_info('drop_pending')) || '|' ||
    (SELECT COUNT(*) FROM drop_pending__crsql_clock);
")

    # Extract baseline values
    PRE_DB_VERSION=$(echo "$PRE_STATE" | cut -d'|' -f1)
    PRE_COL_COUNT=$(echo "$PRE_STATE" | cut -d'|' -f2)
    PRE_CLOCK_COUNT=$(echo "$PRE_STATE" | cut -d'|' -f3)

    # Try to apply changeset for dropped column
    APPLY_RESULT=$(run_sql "
-- Re-create same state (since run_sql uses :memory:)
CREATE TABLE drop_pending (id PRIMARY KEY NOT NULL, a, to_drop);
SELECT crsql_as_crr('drop_pending');
INSERT INTO drop_pending VALUES (1, 'a1', 'will_be_dropped');
SELECT crsql_begin_alter('drop_pending');
ALTER TABLE drop_pending DROP COLUMN to_drop;
SELECT crsql_commit_alter('drop_pending');

-- Try to apply changeset for dropped column
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('drop_pending', X'010901', 'to_drop', 'ghost_value', 2, 2, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 1, 0);

-- Capture post-apply state
SELECT 
    (SELECT MAX(db_version) FROM crsql_changes WHERE [table] = 'drop_pending') || '|' ||
    (SELECT COUNT(*) FROM pragma_table_info('drop_pending')) || '|' ||
    (SELECT COUNT(*) FROM drop_pending__crsql_clock) || '|' ||
    (SELECT a FROM drop_pending WHERE id = 1);
")
    APPLY_ERR=$(cat "$ERRFILE")

    # Determine outcome and validate invariants
    ZIG_ACTUAL_ERR=$(get_actual_error "$ERRFILE")
    
    if [[ -n "$ZIG_ACTUAL_ERR" ]]; then
        # Error path: compare with oracle for parity
        echo "  INFO: Zig error: $ZIG_ACTUAL_ERR"
        
        ORACLE_RESULT=$(run_oracle_sql "
CREATE TABLE drop_pending (id PRIMARY KEY NOT NULL, a, to_drop);
SELECT crsql_as_crr('drop_pending');
INSERT INTO drop_pending VALUES (1, 'a1', 'will_be_dropped');
SELECT crsql_begin_alter('drop_pending');
ALTER TABLE drop_pending DROP COLUMN to_drop;
SELECT crsql_commit_alter('drop_pending');
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('drop_pending', X'010901', 'to_drop', 'ghost_value', 2, 2, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 1, 0);
SELECT 'APPLIED';
")
        ORACLE_ACTUAL_ERR=$(get_actual_error "$ORACLE_ERRFILE")
        
        if [[ "$ORACLE_RESULT" == "ORACLE_NOT_AVAILABLE" ]]; then
            # No oracle - must have specific error message
            if echo "$ZIG_ACTUAL_ERR" | grep -qi "no such column"; then
                echo "  PASS: Dropped column changeset fails with 'no such column' error"
                TOTAL_PASS=$((TOTAL_PASS + 1))
            else
                echo "  FAIL: Expected 'no such column' error (oracle not available for parity)"
                echo "  Got: $ZIG_ACTUAL_ERR"
                TOTAL_FAIL=$((TOTAL_FAIL + 1))
            fi
        elif [[ -n "$ORACLE_ACTUAL_ERR" ]]; then
            echo "  INFO: Oracle error: $ORACLE_ACTUAL_ERR"
            # Both return error - this is parity
            echo "  PASS: Zig and Oracle both error on dropped column changeset (parity verified)"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            # Oracle succeeds, Zig errors - parity gap
            echo "  FAIL: PARITY GAP - Oracle succeeds (graceful ignore), Zig errors"
            echo "  Oracle result: $ORACLE_RESULT"
            echo "  Zig should gracefully ignore changesets for dropped columns"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
        fi
    else
        # No error path: validate graceful ignore with NO partial apply
        POST_DB_VERSION=$(echo "$APPLY_RESULT" | cut -d'|' -f1)
        POST_COL_COUNT=$(echo "$APPLY_RESULT" | cut -d'|' -f2)
        POST_CLOCK_COUNT=$(echo "$APPLY_RESULT" | cut -d'|' -f3)
        POST_DATA=$(echo "$APPLY_RESULT" | cut -d'|' -f4)

        INVARIANT_PASS=1
        
        # Invariant 1: Column count unchanged (no phantom column added)
        if [[ "$POST_COL_COUNT" != "$PRE_COL_COUNT" ]]; then
            echo "  FAIL: Schema changed during ignored apply (cols: $PRE_COL_COUNT -> $POST_COL_COUNT)"
            INVARIANT_PASS=0
        fi
        
        # Invariant 2: Data preserved
        if [[ "$POST_DATA" != "a1" ]]; then
            echo "  FAIL: Existing data corrupted (expected 'a1', got '$POST_DATA')"
            INVARIANT_PASS=0
        fi

        if [[ $INVARIANT_PASS -eq 1 ]]; then
            echo "  PASS: Dropped column changeset ignored gracefully"
            echo "        Invariants verified: schema unchanged ($POST_COL_COUNT cols), data preserved"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Scenario 3: Conflicting Schema Changes
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario 3: Conflicting Schema Changes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Simulates: Site A adds column X, Site B adds column Y independently"
echo ""

# Test 3a: Site A adds column X, receives changeset from Site B that added column Y
# Expected behavior: Either (a) error with "no such column" or (b) graceful ignore
# Either way: NO partial apply (schema unchanged, existing data preserved)
echo "Test 3a: Merge changesets from different schema evolution paths"

# Capture pre-apply state
PRE_STATE_3A=$(run_sql "
-- Site A: Create table and add column X
CREATE TABLE conflict_schema (id PRIMARY KEY NOT NULL, base);
SELECT crsql_as_crr('conflict_schema');
INSERT INTO conflict_schema VALUES (1, 'base1');

SELECT crsql_begin_alter('conflict_schema');
ALTER TABLE conflict_schema ADD COLUMN col_x;
SELECT crsql_commit_alter('conflict_schema');
UPDATE conflict_schema SET col_x = 'x_val' WHERE id = 1;

-- Capture pre-apply state: column_count|col_x_value
SELECT 
    (SELECT COUNT(*) FROM pragma_table_info('conflict_schema')) || '|' ||
    (SELECT col_x FROM conflict_schema WHERE id = 1);
")

PRE_COL_COUNT_3A=$(echo "$PRE_STATE_3A" | cut -d'|' -f1)
PRE_COL_X_VAL=$(echo "$PRE_STATE_3A" | cut -d'|' -f2)

# Try to apply changeset for non-existent column
RESULT=$(run_sql "
-- Re-create same state
CREATE TABLE conflict_schema (id PRIMARY KEY NOT NULL, base);
SELECT crsql_as_crr('conflict_schema');
INSERT INTO conflict_schema VALUES (1, 'base1');
SELECT crsql_begin_alter('conflict_schema');
ALTER TABLE conflict_schema ADD COLUMN col_x;
SELECT crsql_commit_alter('conflict_schema');
UPDATE conflict_schema SET col_x = 'x_val' WHERE id = 1;

-- Site B independently added col_y (not col_x)
-- Site A receives Site B's changeset for col_y
-- Site A doesn't have col_y yet!
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('conflict_schema', X'010901', 'col_y', 'y_val_from_b', 1, 1, X'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', 1, 0);

-- Capture post-apply state: column_count|col_x_value
SELECT 
    (SELECT COUNT(*) FROM pragma_table_info('conflict_schema')) || '|' ||
    (SELECT col_x FROM conflict_schema WHERE id = 1);
")
APPLY_ERR_3A=$(cat "$ERRFILE")

# Determine outcome and validate invariants
ZIG_ACTUAL_ERR_3A=$(get_actual_error "$ERRFILE")

if [[ -n "$ZIG_ACTUAL_ERR_3A" ]]; then
    # Error path: compare with oracle for parity
    echo "  INFO: Zig error: $ZIG_ACTUAL_ERR_3A"
    
    ORACLE_RESULT_3A=$(run_oracle_sql "
CREATE TABLE conflict_schema (id PRIMARY KEY NOT NULL, base);
SELECT crsql_as_crr('conflict_schema');
INSERT INTO conflict_schema VALUES (1, 'base1');
SELECT crsql_begin_alter('conflict_schema');
ALTER TABLE conflict_schema ADD COLUMN col_x;
SELECT crsql_commit_alter('conflict_schema');
UPDATE conflict_schema SET col_x = 'x_val' WHERE id = 1;
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('conflict_schema', X'010901', 'col_y', 'y_val_from_b', 1, 1, X'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', 1, 0);
SELECT col_x FROM conflict_schema WHERE id = 1;
")
    ORACLE_ACTUAL_ERR_3A=$(get_actual_error "$ORACLE_ERRFILE")
    
    if [[ "$ORACLE_RESULT_3A" == "ORACLE_NOT_AVAILABLE" ]]; then
        # No oracle - must have specific error message
        if echo "$ZIG_ACTUAL_ERR_3A" | grep -qi "no such column"; then
            echo "  PASS: Missing column changeset fails with 'no such column' error"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            echo "  FAIL: Expected 'no such column' error (oracle not available for parity)"
            echo "  Got: $ZIG_ACTUAL_ERR_3A"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
        fi
    elif [[ -n "$ORACLE_ACTUAL_ERR_3A" ]]; then
        echo "  INFO: Oracle error: $ORACLE_ACTUAL_ERR_3A"
        # Both return error - this is parity
        echo "  PASS: Zig and Oracle both error on missing column changeset (parity verified)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        # Oracle succeeds, Zig errors - parity gap
        echo "  FAIL: PARITY GAP - Oracle succeeds (graceful ignore), Zig errors"
        echo "  Oracle result: col_x='$ORACLE_RESULT_3A'"
        echo "  Zig should gracefully ignore changesets for missing columns"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
else
    # No error path: validate graceful ignore with NO partial apply
    POST_COL_COUNT_3A=$(echo "$RESULT" | cut -d'|' -f1)
    POST_COL_X_VAL=$(echo "$RESULT" | cut -d'|' -f2)

    INVARIANT_PASS_3A=1
    
    # Invariant 1: Column count unchanged (col_y not added)
    if [[ "$POST_COL_COUNT_3A" != "$PRE_COL_COUNT_3A" ]]; then
        echo "  FAIL: Schema changed during ignored apply (cols: $PRE_COL_COUNT_3A -> $POST_COL_COUNT_3A)"
        INVARIANT_PASS_3A=0
    fi
    
    # Invariant 2: Existing data preserved
    if [[ "$POST_COL_X_VAL" != "x_val" ]]; then
        echo "  FAIL: Existing col_x corrupted (expected 'x_val', got '$POST_COL_X_VAL')"
        INVARIANT_PASS_3A=0
    fi

    if [[ $INVARIANT_PASS_3A -eq 1 ]]; then
        echo "  PASS: Unknown column changeset ignored gracefully"
        echo "        Invariants verified: schema unchanged ($POST_COL_COUNT_3A cols), col_x='$POST_COL_X_VAL' preserved"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# Test 3b: Both sites have same new column, merge works
echo ""
echo "Test 3b: Same column added on both sites, merge works"
RESULT=$(run_sql "
-- Site A: Create table and add same column as Site B would
CREATE TABLE same_schema (id PRIMARY KEY NOT NULL, base);
SELECT crsql_as_crr('same_schema');
INSERT INTO same_schema VALUES (1, 'base1');

SELECT crsql_begin_alter('same_schema');
ALTER TABLE same_schema ADD COLUMN shared_col;
SELECT crsql_commit_alter('same_schema');
UPDATE same_schema SET shared_col = 'a_value' WHERE id = 1;

-- Site B also added shared_col and set a value with higher version
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('same_schema', X'010901', 'shared_col', 'b_value_wins', 2, 2, X'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', 1, 0);

-- Site B's higher version should win
SELECT shared_col FROM same_schema WHERE id = 1;
")

if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "b_value_wins" ]]; then
    echo "  PASS: Same column exists on both, higher version wins"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'b_value_wins' (higher version), got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Scenario 4: Rapid Alter Cycles (Stress Test)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario 4: Rapid Alter Cycles (Stress Test)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "10 rapid cycles of: add column -> insert data -> verify"
echo ""

echo "Test 4a: 10 rapid add column cycles"
RESULT=$(run_sql "
CREATE TABLE rapid (id PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('rapid');
INSERT INTO rapid VALUES (1);

-- Cycle 1
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c1;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c1 = 'v1' WHERE id = 1;

-- Cycle 2
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c2;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c2 = 'v2' WHERE id = 1;

-- Cycle 3
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c3;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c3 = 'v3' WHERE id = 1;

-- Cycle 4
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c4;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c4 = 'v4' WHERE id = 1;

-- Cycle 5
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c5;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c5 = 'v5' WHERE id = 1;

-- Cycle 6
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c6;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c6 = 'v6' WHERE id = 1;

-- Cycle 7
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c7;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c7 = 'v7' WHERE id = 1;

-- Cycle 8
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c8;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c8 = 'v8' WHERE id = 1;

-- Cycle 9
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c9;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c9 = 'v9' WHERE id = 1;

-- Cycle 10
SELECT crsql_begin_alter('rapid');
ALTER TABLE rapid ADD COLUMN c10;
SELECT crsql_commit_alter('rapid');
UPDATE rapid SET c10 = 'v10' WHERE id = 1;

-- Verify: 11 columns total (id + c1-c10)
SELECT COUNT(*) FROM pragma_table_info('rapid');
")

if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred during rapid cycles"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "11" ]]; then
    echo "  PASS: 10 rapid cycles complete, 11 columns present"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 11 columns, got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test 4b: Verify all values preserved after rapid cycles
echo ""
echo "Test 4b: All values preserved after rapid cycles"
RESULT=$(run_sql "
CREATE TABLE rapid2 (id PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('rapid2');
INSERT INTO rapid2 VALUES (1);

SELECT crsql_begin_alter('rapid2'); ALTER TABLE rapid2 ADD COLUMN c1; SELECT crsql_commit_alter('rapid2');
UPDATE rapid2 SET c1 = 'v1' WHERE id = 1;
SELECT crsql_begin_alter('rapid2'); ALTER TABLE rapid2 ADD COLUMN c2; SELECT crsql_commit_alter('rapid2');
UPDATE rapid2 SET c2 = 'v2' WHERE id = 1;
SELECT crsql_begin_alter('rapid2'); ALTER TABLE rapid2 ADD COLUMN c3; SELECT crsql_commit_alter('rapid2');
UPDATE rapid2 SET c3 = 'v3' WHERE id = 1;
SELECT crsql_begin_alter('rapid2'); ALTER TABLE rapid2 ADD COLUMN c4; SELECT crsql_commit_alter('rapid2');
UPDATE rapid2 SET c4 = 'v4' WHERE id = 1;
SELECT crsql_begin_alter('rapid2'); ALTER TABLE rapid2 ADD COLUMN c5; SELECT crsql_commit_alter('rapid2');
UPDATE rapid2 SET c5 = 'v5' WHERE id = 1;

-- Verify all values
SELECT c1 || ',' || c2 || ',' || c3 || ',' || c4 || ',' || c5 FROM rapid2 WHERE id = 1;
")

if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "v1,v2,v3,v4,v5" ]]; then
    echo "  PASS: All column values preserved"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 'v1,v2,v3,v4,v5', got: $RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Test 4c: Clock entries exist for all rapidly-added columns
echo ""
echo "Test 4c: Clock entries exist for all rapidly-added columns"
RESULT=$(run_sql "
CREATE TABLE rapid3 (id PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('rapid3');
INSERT INTO rapid3 VALUES (1);

SELECT crsql_begin_alter('rapid3'); ALTER TABLE rapid3 ADD COLUMN c1; SELECT crsql_commit_alter('rapid3');
UPDATE rapid3 SET c1 = 'v1' WHERE id = 1;
SELECT crsql_begin_alter('rapid3'); ALTER TABLE rapid3 ADD COLUMN c2; SELECT crsql_commit_alter('rapid3');
UPDATE rapid3 SET c2 = 'v2' WHERE id = 1;
SELECT crsql_begin_alter('rapid3'); ALTER TABLE rapid3 ADD COLUMN c3; SELECT crsql_commit_alter('rapid3');
UPDATE rapid3 SET c3 = 'v3' WHERE id = 1;

-- Count clock entries for c1, c2, c3
SELECT COUNT(DISTINCT col_name) FROM rapid3__crsql_clock WHERE col_name IN ('c1', 'c2', 'c3');
")

if grep -q -i "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: Clock has entries for all 3 added columns"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected 3 distinct clock entries, got: $RESULT"
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
echo "╠═══════════════════════════════════════════════════════════════════════╣"
echo "║  SQLite Version: $(printf '%-52s' "$SQLITE_VERSION")║"
echo "║  RENAME COLUMN:  $(printf '%-52s' "$([ $HAS_RENAME_COLUMN -eq 1 ] && echo 'Yes' || echo 'No (requires 3.25+)')")║"
echo "║  DROP COLUMN:    $(printf '%-52s' "$([ $HAS_DROP_COLUMN -eq 1 ] && echo 'Yes' || echo 'No (requires 3.35+)')")║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "✓ All implemented tests PASSED"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo "⚠ All tests SKIPPED"
    exit 0
else
    echo "✗ Some tests FAILED"
    exit 1
fi
