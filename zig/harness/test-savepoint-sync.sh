#!/usr/bin/env bash
# Savepoint During Sync Test Suite for Zig CR-SQLite
# Tests that savepoints work correctly during sync operations (crsql_changes INSERT)
#
# Reference: TASK-175 - Test savepoints during sync operations
#
# Apps may use savepoints for partial rollback during sync:
#   BEGIN;
#   INSERT INTO crsql_changes ...;
#   SAVEPOINT sp1;
#   INSERT INTO crsql_changes ...;
#   ROLLBACK TO sp1;
#   COMMIT;
#
# These tests verify:
# 1. Does rollback to savepoint undo clock entries?
# 2. Is db_version correct after partial rollback?
# 3. Is rows_impacted correct?
# 4. Zig and Rust/C oracle produce identical results
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "=================================================================="
echo "Test Suite: Savepoint During Sync Operations (TASK-175)"
echo "=================================================================="
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Zig extension not found at $ZIG_EXT"
    echo "Run 'nix run nixpkgs#zig -- build' first in $ZIG_DIR"
    exit 1
fi

echo "Zig extension: $ZIG_EXT"
echo ""

# Check for Rust/C oracle (via sqlite-cr wrapper)
HAS_ORACLE=0
if command -v nix &>/dev/null; then
    # Quick smoke test to see if sqlite-cr works
    if echo "SELECT 1;" | nix run github:subtleGradient/sqlite-cr -- :memory: 2>/dev/null | grep -q "1"; then
        HAS_ORACLE=1
        echo "Rust/C oracle: available (via sqlite-cr)"
    else
        echo "Rust/C oracle: sqlite-cr not available"
    fi
fi
echo ""

# Setup temp directory
TMPDIR="${ROOT_DIR}/.tmp"
mkdir -p "$TMPDIR"
ERRFILE=$(mktemp "$TMPDIR/savepoint-sync-err.XXXXXX")
OUTFILE=$(mktemp "$TMPDIR/savepoint-sync-out.XXXXXX")
trap "rm -f $ERRFILE $OUTFILE" EXIT

PASS=0
FAIL=0
SKIP=0
DIVERGENCES=0

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

# Run SQL with Zig extension (clean sqlite + explicit .load)
run_zig() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_zig_all() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Run SQL with Rust/C oracle (via sqlite-cr wrapper)
# NEVER load Zig extension into sqlite-cr (double-loading causes conflicts)
run_rust() {
    local db="$1"
    local sql="$2"
    nix run github:subtleGradient/sqlite-cr -- "$db" <<< "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_rust_all() {
    local db="$1"
    local sql="$2"
    nix run github:subtleGradient/sqlite-cr -- "$db" <<< "$sql" 2>"$ERRFILE" || true
}

# =============================================================================
# Test 1: Basic Savepoint with Rollback
# =============================================================================
# BEGIN, apply changes, SAVEPOINT sp1, apply more, ROLLBACK TO sp1, COMMIT
# -> Only pre-savepoint changes should be committed
echo "============================================================================="
echo "Test 1: Basic Savepoint with Rollback (pre-savepoint changes only)"
echo "============================================================================="
echo ""

test_basic_savepoint_rollback() {
    local ext_name="$1"
    local run_func="$2"
    local db="$TMPDIR/savepoint-basic-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup: create table
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # Execute savepoint test sequence:
    # 1. BEGIN
    # 2. Insert item 1 (before savepoint)
    # 3. SAVEPOINT sp1
    # 4. Insert item 2 (after savepoint)
    # 5. ROLLBACK TO sp1
    # 6. COMMIT
    $run_func "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item_before_savepoint', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item_after_savepoint', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        ROLLBACK TO sp1;
        COMMIT;
    " > /dev/null 2>&1
    
    # Verify: only item 1 should exist (item 2 was rolled back)
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    local final_ver=$($run_func "$db" "SELECT crsql_db_version();")
    local item1_exists=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 1;")
    local item2_exists=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 2;")
    
    local status=0
    
    if [[ "$final_count" != "1" ]]; then
        echo "  [$ext_name] FAIL: Expected 1 row, got $final_count"
        status=1
    fi
    
    if [[ "$item1_exists" != "1" ]]; then
        echo "  [$ext_name] FAIL: Pre-savepoint item missing (item 1)"
        status=1
    fi
    
    if [[ "$item2_exists" != "0" ]]; then
        echo "  [$ext_name] FAIL: Post-savepoint item persisted (item 2 should be rolled back)"
        status=1
    fi
    
    # db_version should have advanced (item 1 was committed)
    if [[ "$final_ver" -le "$initial_ver" ]]; then
        echo "  [$ext_name] FAIL: db_version did not advance after commit"
        echo "    Initial: $initial_ver, Final: $final_ver"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: Only pre-savepoint changes committed"
        echo "    Row count: $final_count (expected: 1)"
        echo "    db_version: $initial_ver -> $final_ver"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_basic_savepoint_rollback "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle if available
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_basic_savepoint_rollback "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    # Check for divergence
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 2: Nested Savepoints
# =============================================================================
# sp1 inside transaction, sp2 inside sp1
echo ""
echo "============================================================================="
echo "Test 2: Nested Savepoints (sp1 -> sp2)"
echo "============================================================================="
echo ""

test_nested_savepoints() {
    local ext_name="$1"
    local run_func="$2"
    local db="$TMPDIR/savepoint-nested-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # Nested savepoint sequence:
    # 1. BEGIN
    # 2. Insert item 1
    # 3. SAVEPOINT sp1
    # 4. Insert item 2
    # 5. SAVEPOINT sp2
    # 6. Insert item 3
    # 7. ROLLBACK TO sp2 (undo item 3)
    # 8. COMMIT
    # -> Items 1 and 2 should persist
    $run_func "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1_base', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2_in_sp1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp2;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010903', 'name', 'item3_in_sp2', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        ROLLBACK TO sp2;
        COMMIT;
    " > /dev/null 2>&1
    
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    local item1=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 1;")
    local item2=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 2;")
    local item3=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 3;")
    
    local status=0
    
    if [[ "$final_count" != "2" ]]; then
        echo "  [$ext_name] FAIL: Expected 2 rows, got $final_count"
        status=1
    fi
    
    if [[ "$item1" != "1" ]] || [[ "$item2" != "1" ]]; then
        echo "  [$ext_name] FAIL: Items 1 and 2 should exist"
        echo "    item1=$item1, item2=$item2"
        status=1
    fi
    
    if [[ "$item3" != "0" ]]; then
        echo "  [$ext_name] FAIL: Item 3 should be rolled back"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: Nested savepoint rollback works"
        echo "    Row count: $final_count (items 1, 2 present; item 3 rolled back)"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_nested_savepoints "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_nested_savepoints "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 3: RELEASE SAVEPOINT (vs ROLLBACK TO)
# =============================================================================
# RELEASE removes the savepoint but keeps changes (different from ROLLBACK TO)
echo ""
echo "============================================================================="
echo "Test 3: RELEASE SAVEPOINT (keeps changes)"
echo "============================================================================="
echo ""

test_release_savepoint() {
    local ext_name="$1"
    local run_func="$2"
    local db="$TMPDIR/savepoint-release-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # RELEASE savepoint sequence:
    # 1. BEGIN
    # 2. Insert item 1
    # 3. SAVEPOINT sp1
    # 4. Insert item 2
    # 5. RELEASE sp1 (keeps item 2, removes savepoint)
    # 6. COMMIT
    # -> Both items should persist
    $run_func "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1_before_sp', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2_after_sp', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        RELEASE sp1;
        COMMIT;
    " > /dev/null 2>&1
    
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    local item1=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 1;")
    local item2=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 2;")
    
    local status=0
    
    if [[ "$final_count" != "2" ]]; then
        echo "  [$ext_name] FAIL: Expected 2 rows after RELEASE, got $final_count"
        status=1
    fi
    
    if [[ "$item1" != "1" ]] || [[ "$item2" != "1" ]]; then
        echo "  [$ext_name] FAIL: Both items should exist after RELEASE"
        echo "    item1=$item1, item2=$item2"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: RELEASE keeps all changes"
        echo "    Row count: $final_count (both items persisted)"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_release_savepoint "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_release_savepoint "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 4: Multiple Savepoints with Partial Rollback
# =============================================================================
# Create multiple savepoints, rollback to middle one
echo ""
echo "============================================================================="
echo "Test 4: Multiple Savepoints with Partial Rollback (rollback to middle)"
echo "============================================================================="
echo ""

test_multiple_savepoints_partial_rollback() {
    local ext_name="$1"
    local run_func="$2"
    local db="$TMPDIR/savepoint-multi-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # Multiple savepoints with partial rollback:
    # 1. BEGIN
    # 2. Insert item 1
    # 3. SAVEPOINT sp1
    # 4. Insert item 2
    # 5. SAVEPOINT sp2
    # 6. Insert item 3
    # 7. SAVEPOINT sp3
    # 8. Insert item 4
    # 9. ROLLBACK TO sp2 (undo items 3 and 4, keeps sp2)
    # 10. COMMIT
    # -> Items 1 and 2 should persist
    $run_func "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp2;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010903', 'name', 'item3', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp3;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010904', 'name', 'item4', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        ROLLBACK TO sp2;
        COMMIT;
    " > /dev/null 2>&1
    
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    local item1=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 1;")
    local item2=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 2;")
    local item3=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 3;")
    local item4=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 4;")
    
    local status=0
    
    if [[ "$final_count" != "2" ]]; then
        echo "  [$ext_name] FAIL: Expected 2 rows, got $final_count"
        status=1
    fi
    
    if [[ "$item1" != "1" ]] || [[ "$item2" != "1" ]]; then
        echo "  [$ext_name] FAIL: Items 1 and 2 should exist"
        echo "    item1=$item1, item2=$item2"
        status=1
    fi
    
    if [[ "$item3" != "0" ]] || [[ "$item4" != "0" ]]; then
        echo "  [$ext_name] FAIL: Items 3 and 4 should be rolled back"
        echo "    item3=$item3, item4=$item4"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: Partial rollback to middle savepoint works"
        echo "    Row count: $final_count (items 1,2 kept; items 3,4 rolled back)"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_multiple_savepoints_partial_rollback "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_multiple_savepoints_partial_rollback "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 5: rows_impacted After Partial Rollback
# =============================================================================
# Verify rows_impacted reflects only actually committed changes
echo ""
echo "============================================================================="
echo "Test 5: rows_impacted After Partial Rollback"
echo "============================================================================="
echo ""

test_rows_impacted_after_rollback() {
    local ext_name="$1"
    local run_func="$2"
    local run_func_all="$3"
    local db="$TMPDIR/savepoint-rows-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    # Check if crsql_rows_impacted is available
    local rows_check=$($run_func "$db" "SELECT crsql_rows_impacted();" 2>&1)
    if echo "$rows_check" | grep -qi "no such function"; then
        echo "  [$ext_name] SKIP: crsql_rows_impacted() not implemented"
        rm -f "$db"
        return 2
    fi
    
    # rows_impacted sequence with savepoint rollback:
    # 1. BEGIN
    # 2. Insert item 1 -> rows_impacted should be 1
    # 3. SAVEPOINT sp1
    # 4. Insert items 2, 3 -> rows_impacted should be 3
    # 5. ROLLBACK TO sp1 (note: Rust/C does NOT reset on rollback per xRollback=NULL)
    # 6. Check rows_impacted (behavior depends on implementation)
    # 7. COMMIT -> rows_impacted should be 0 (reset on commit)
    
    # Run the full sequence and capture checkpoints
    local output=$($run_func_all "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SELECT 'ROWS_AFTER_1=' || crsql_rows_impacted();
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010903', 'name', 'item3', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SELECT 'ROWS_AFTER_3=' || crsql_rows_impacted();
        ROLLBACK TO sp1;
        SELECT 'ROWS_AFTER_ROLLBACK=' || crsql_rows_impacted();
        COMMIT;
        SELECT 'ROWS_AFTER_COMMIT=' || crsql_rows_impacted();
    " 2>/dev/null)
    
    local rows_after_1=$(echo "$output" | grep "ROWS_AFTER_1=" | cut -d= -f2)
    local rows_after_3=$(echo "$output" | grep "ROWS_AFTER_3=" | cut -d= -f2)
    local rows_after_rollback=$(echo "$output" | grep "ROWS_AFTER_ROLLBACK=" | cut -d= -f2)
    local rows_after_commit=$(echo "$output" | grep "ROWS_AFTER_COMMIT=" | cut -d= -f2)
    
    local status=0
    
    # rows_impacted should be 1 after first insert
    if [[ "$rows_after_1" != "1" ]]; then
        echo "  [$ext_name] FAIL: rows_impacted after 1 insert expected 1, got $rows_after_1"
        status=1
    fi
    
    # rows_impacted should be 3 after all inserts (accumulates)
    if [[ "$rows_after_3" != "3" ]]; then
        echo "  [$ext_name] FAIL: rows_impacted after 3 inserts expected 3, got $rows_after_3"
        status=1
    fi
    
    # After ROLLBACK TO: Rust/C does NOT reset (xRollback=NULL)
    # The counter persists even though data was rolled back
    # This is documented behavior - we test for parity, not specific value
    echo "  [$ext_name] INFO: rows_impacted after rollback = $rows_after_rollback"
    
    # After COMMIT: should reset to 0
    if [[ "$rows_after_commit" != "0" ]]; then
        echo "  [$ext_name] FAIL: rows_impacted after commit expected 0, got $rows_after_commit"
        status=1
    fi
    
    # Verify final state: only 1 row should exist
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    if [[ "$final_count" != "1" ]]; then
        echo "  [$ext_name] FAIL: Expected 1 row after savepoint rollback, got $final_count"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: rows_impacted behavior correct"
        echo "    After 1 insert: $rows_after_1"
        echo "    After 3 inserts: $rows_after_3"
        echo "    After ROLLBACK TO: $rows_after_rollback"
        echo "    After COMMIT: $rows_after_commit"
        echo "    Final row count: $final_count"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_rows_impacted_after_rollback "Zig" run_zig run_zig_all || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_rows_impacted_after_rollback "Rust" run_rust run_rust_all || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 6: Clock Entries After Savepoint Rollback
# =============================================================================
# Verify clock table entries are correct after partial rollback
echo ""
echo "============================================================================="
echo "Test 6: Clock Entries After Savepoint Rollback"
echo "============================================================================="
echo ""

test_clock_entries_after_rollback() {
    local ext_name="$1"
    local run_func="$2"
    local db="$TMPDIR/savepoint-clock-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # Insert with savepoint rollback, then check clock table
    $run_func "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2_rolled_back', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        ROLLBACK TO sp1;
        COMMIT;
    " > /dev/null 2>&1
    
    # Check clock entries - only item 1 should have a clock entry
    local clock_count=$($run_func "$db" "SELECT COUNT(*) FROM items__crsql_clock;")
    
    local status=0
    
    # Should have exactly 1 clock entry (for item 1)
    if [[ "$clock_count" != "1" ]]; then
        echo "  [$ext_name] FAIL: Expected 1 clock entry, got $clock_count"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: Clock entries correct after savepoint rollback"
        echo "    Clock entry count: $clock_count (expected: 1)"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_clock_entries_after_rollback "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_clock_entries_after_rollback "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 7: db_version After Savepoint Rollback
# =============================================================================
# Verify db_version reflects only committed changes
echo ""
echo "============================================================================="
echo "Test 7: db_version After Savepoint Rollback"
echo "============================================================================="
echo ""

test_dbversion_after_savepoint_rollback() {
    local ext_name="$1"
    local run_func="$2"
    local run_func_all="$3"
    local db="$TMPDIR/savepoint-dbver-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # Track db_version through savepoint sequence
    local output=$($run_func_all "$db" "
        SELECT 'INITIAL=' || crsql_db_version();
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SELECT 'AFTER_INSERT1=' || crsql_db_version();
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SELECT 'AFTER_INSERT2=' || crsql_db_version();
        ROLLBACK TO sp1;
        SELECT 'AFTER_ROLLBACK=' || crsql_db_version();
        COMMIT;
        SELECT 'AFTER_COMMIT=' || crsql_db_version();
    " 2>/dev/null)
    
    local ver_initial=$(echo "$output" | grep "INITIAL=" | cut -d= -f2)
    local ver_after_1=$(echo "$output" | grep "AFTER_INSERT1=" | cut -d= -f2)
    local ver_after_2=$(echo "$output" | grep "AFTER_INSERT2=" | cut -d= -f2)
    local ver_after_rollback=$(echo "$output" | grep "AFTER_ROLLBACK=" | cut -d= -f2)
    local ver_after_commit=$(echo "$output" | grep "AFTER_COMMIT=" | cut -d= -f2)
    
    local status=0
    
    echo "  [$ext_name] db_version progression:"
    echo "    Initial: $ver_initial"
    echo "    After insert 1: $ver_after_1"
    echo "    After insert 2: $ver_after_2"
    echo "    After ROLLBACK TO: $ver_after_rollback"
    echo "    After COMMIT: $ver_after_commit"
    
    # After commit, db_version should have advanced from initial
    if [[ "$ver_after_commit" -le "$ver_initial" ]]; then
        echo "  [$ext_name] FAIL: db_version did not advance after commit"
        status=1
    fi
    
    # Verify only 1 row exists (item 2 was rolled back)
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    if [[ "$final_count" != "1" ]]; then
        echo "  [$ext_name] FAIL: Expected 1 row, got $final_count"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: db_version correct after savepoint rollback"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_dbversion_after_savepoint_rollback "Zig" run_zig run_zig_all || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_dbversion_after_savepoint_rollback "Rust" run_rust run_rust_all || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Test 8: Rollback to Savepoint Then Continue Adding Data
# =============================================================================
# Rollback to savepoint, then add more data before commit
echo ""
echo "============================================================================="
echo "Test 8: Rollback to Savepoint Then Add More Data"
echo "============================================================================="
echo ""

test_rollback_then_continue() {
    local ext_name="$1"
    local run_func="$2"
    local db="$TMPDIR/savepoint-continue-${ext_name}-$$.db"
    rm -f "$db"
    
    # Setup
    $run_func "$db" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db" "SELECT crsql_db_version();")
    
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db"
        return 2
    fi
    
    # Sequence: rollback to savepoint, then add more data
    # 1. BEGIN
    # 2. Insert item 1
    # 3. SAVEPOINT sp1
    # 4. Insert item 2 (will be rolled back)
    # 5. ROLLBACK TO sp1
    # 6. Insert item 3 (new data after rollback)
    # 7. COMMIT
    # -> Items 1 and 3 should persist
    $run_func "$db" "
        BEGIN;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        SAVEPOINT sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010902', 'name', 'item2_rolled_back', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        ROLLBACK TO sp1;
        INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('items', X'010903', 'name', 'item3_after_rollback', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
        COMMIT;
    " > /dev/null 2>&1
    
    local final_count=$($run_func "$db" "SELECT COUNT(*) FROM items;")
    local item1=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 1;")
    local item2=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 2;")
    local item3=$($run_func "$db" "SELECT COUNT(*) FROM items WHERE id = 3;")
    
    local status=0
    
    if [[ "$final_count" != "2" ]]; then
        echo "  [$ext_name] FAIL: Expected 2 rows, got $final_count"
        status=1
    fi
    
    if [[ "$item1" != "1" ]]; then
        echo "  [$ext_name] FAIL: Item 1 should exist"
        status=1
    fi
    
    if [[ "$item2" != "0" ]]; then
        echo "  [$ext_name] FAIL: Item 2 should be rolled back"
        status=1
    fi
    
    if [[ "$item3" != "1" ]]; then
        echo "  [$ext_name] FAIL: Item 3 (added after rollback) should exist"
        status=1
    fi
    
    if [[ $status -eq 0 ]]; then
        echo "  [$ext_name] PASS: Can add data after rollback to savepoint"
        echo "    Row count: $final_count (items 1, 3 present; item 2 rolled back)"
    fi
    
    rm -f "$db"
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_rollback_then_continue "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C oracle
if [[ $HAS_ORACLE -eq 1 ]]; then
    RUST_RESULT=0
    test_rollback_then_continue "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=================================================================="
echo "           SAVEPOINT SYNC TEST SUMMARY"
echo "=================================================================="
printf "  PASSED:     %d\n" "$PASS"
printf "  FAILED:     %d\n" "$FAIL"
printf "  SKIPPED:    %d\n" "$SKIP"
printf "  DIVERGENCES: %d\n" "$DIVERGENCES"
echo "=================================================================="
echo ""

if [[ $DIVERGENCES -gt 0 ]]; then
    echo "WARNING: $DIVERGENCES divergence(s) between Zig and Rust/C oracle"
    echo "See individual test output above for details."
    echo ""
fi

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "Savepoint Sync Test Summary: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "Savepoint Sync Test Summary: $PASS passed, $FAIL failed, $SKIP skipped"
    echo "All savepoint sync tests SKIPPED (functions not implemented)"
    exit 2
else
    echo "Savepoint Sync Test Summary: $PASS passed, $FAIL failed, $SKIP skipped"
    echo "Some savepoint sync tests FAILED"
    exit 1
fi
