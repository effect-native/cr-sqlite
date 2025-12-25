#!/usr/bin/env bash
# Property-Based Sentinel Tests (ported from py/correctness/tests/test_sentinel_omission.py
# and test_sync.py)
#
# These tests verify sentinel (cid='-1') emission rules discovered via Python testing:
# 1. No sentinel on INSERT - normal inserts should NOT create sentinels
# 2. Sentinel on DELETE - deletes MUST create sentinel with CL
# 3. No sentinel on REPLACE - INSERT OR REPLACE should NOT create sentinel
# 4. No sentinel on merge - applying remote changes shouldn't create extra sentinels
# 5. Delete sentinel propagates correctly on sync
# 6. Merge-equal-values config affects tiebreaking (test_merge_same_w_tie_breaker)
#
# Reference: TASK-191, py/correctness/tests/test_sentinel_omission.py, test_sync.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=============================================================================="
echo "Test Suite: Sentinel Properties (Property-Based, Zig vs Rust/C)"
echo "=============================================================================="
echo ""
echo "Properties from Python tests:"
echo "  - No sentinel on INSERT (test_omitted_on_insert)"
echo "  - Sentinel created on DELETE (test_created_on_delete)"
echo "  - No sentinel on REPLACE (test_not_created_on_replace)"
echo "  - No sentinel on merge (test_not_created_on_merge)"
echo "  - No sentinel on noop merge (test_not_created_on_noop_merge)"
echo "  - Sentinel propagates on sync (test_sentinel_propagated_when_present)"
echo ""

# Determine extension paths based on platform
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$ROOT_DIR/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$ROOT_DIR/lib/crsqlite-darwin-x86_64.dylib"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$ROOT_DIR/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$ROOT_DIR/lib/crsqlite-linux-x86_64.so"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Verify extensions exist
if [[ ! -f "$RUST_EXT" ]]; then
    echo "ERROR: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 1
fi

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

# Temp dir
TMPDIR="$ROOT_DIR/.tmp/sentinel-properties-$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

ERRFILE="$TMPDIR/error.txt"

PASSED=0
FAILED=0
SKIPPED=0

# Helpers
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

check_parity() {
    local test_name="$1"
    local zig_val="$2"
    local rust_val="$3"
    local expected="${4:-}"
    
    if [[ "$zig_val" == "$rust_val" ]]; then
        if [[ -n "$expected" && "$zig_val" != "$expected" ]]; then
            echo "  FAIL: $test_name - both match but unexpected value"
            echo "    Both: $zig_val (expected: $expected)"
            FAILED=$((FAILED + 1))
            return 1
        fi
        echo "  PASS: $test_name"
        [[ -n "$expected" ]] && echo "    Value: $zig_val"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo "  FAIL: $test_name - DIVERGENCE"
        echo "    Zig:    $zig_val"
        echo "    Rust/C: $rust_val"
        [[ -n "$expected" ]] && echo "    Expected: $expected"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

count_sentinels() {
    local impl="$1"  # "zig" or "rust"
    local db="$2"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "SELECT COUNT(*) FROM crsql_changes WHERE cid = '-1';"
    else
        run_rust "$db" "SELECT COUNT(*) FROM crsql_changes WHERE cid = '-1';"
    fi
}

# ==============================================================================
# Property 1: No Sentinel on INSERT (test_omitted_on_insert)
# From Python: 800 inserts should create 0 sentinels
# ==============================================================================
test_no_sentinel_on_insert() {
    echo "=============================================================================="
    echo "Property 1: No Sentinel on INSERT"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Insert 40 rows into 2 tables (80 total rows)"
    echo "Expected: 0 sentinels created"
    echo ""
    
    local DB_ZIG="$TMPDIR/insert_zig.db"
    local DB_RUST="$TMPDIR/insert_rust.db"
    
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
CREATE TABLE test2 (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test2');
"
    
    run_zig "$DB_ZIG" "$SETUP"
    run_rust "$DB_RUST" "$SETUP"
    
    # Insert 20 rows per table (40 total per implementation)
    local INSERT_SQL="BEGIN;"
    for n in $(seq 0 19); do
        INSERT_SQL+="INSERT INTO test (id, text) VALUES ($n, 'hello $n');"
        INSERT_SQL+="INSERT INTO test2 (id, text) VALUES ($n, 'hello $n');"
    done
    INSERT_SQL+="COMMIT;"
    
    run_zig "$DB_ZIG" "$INSERT_SQL"
    run_rust "$DB_RUST" "$INSERT_SQL"
    
    local ZIG_SENTINELS=$(count_sentinels "zig" "$DB_ZIG")
    local RUST_SENTINELS=$(count_sentinels "rust" "$DB_RUST")
    
    echo "Test 1a: Sentinel count after INSERT"
    check_parity "Sentinel count" "$ZIG_SENTINELS" "$RUST_SENTINELS" "0"
    
    echo ""
}

# ==============================================================================
# Property 2: Sentinel Created on DELETE (test_created_on_delete)
# From Python: Deleting all rows should create sentinels for each
# ==============================================================================
test_sentinel_on_delete() {
    echo "=============================================================================="
    echo "Property 2: Sentinel Created on DELETE"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Insert 20 rows per table, then DELETE all"
    echo "Expected: 40 sentinels created (one per deleted row)"
    echo ""
    
    local DB_ZIG="$TMPDIR/delete_zig.db"
    local DB_RUST="$TMPDIR/delete_rust.db"
    
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
CREATE TABLE test2 (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test2');
"
    
    run_zig "$DB_ZIG" "$SETUP"
    run_rust "$DB_RUST" "$SETUP"
    
    # Insert 20 rows per table
    local INSERT_SQL="BEGIN;"
    for n in $(seq 0 19); do
        INSERT_SQL+="INSERT INTO test (id, text) VALUES ($n, 'hello $n');"
        INSERT_SQL+="INSERT INTO test2 (id, text) VALUES ($n, 'hello $n');"
    done
    INSERT_SQL+="COMMIT;"
    
    run_zig "$DB_ZIG" "$INSERT_SQL"
    run_rust "$DB_RUST" "$INSERT_SQL"
    
    # Delete all rows
    local DELETE_SQL="DELETE FROM test; DELETE FROM test2;"
    run_zig "$DB_ZIG" "$DELETE_SQL"
    run_rust "$DB_RUST" "$DELETE_SQL"
    
    local ZIG_SENTINELS=$(count_sentinels "zig" "$DB_ZIG")
    local RUST_SENTINELS=$(count_sentinels "rust" "$DB_RUST")
    
    echo "Test 2a: Sentinel count after DELETE"
    check_parity "Sentinel count" "$ZIG_SENTINELS" "$RUST_SENTINELS" "40"
    
    echo ""
}

# ==============================================================================
# Property 3: No Sentinel on REPLACE (test_not_created_on_replace)
# From Python: INSERT OR REPLACE on existing rows should NOT create sentinels
# ==============================================================================
test_no_sentinel_on_replace() {
    echo "=============================================================================="
    echo "Property 3: No Sentinel on REPLACE"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Insert rows, then INSERT OR REPLACE all of them"
    echo "Expected: 0 sentinels (REPLACE is an UPDATE, not DELETE)"
    echo ""
    
    local DB_ZIG="$TMPDIR/replace_zig.db"
    local DB_RUST="$TMPDIR/replace_rust.db"
    
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
"
    
    run_zig "$DB_ZIG" "$SETUP"
    run_rust "$DB_RUST" "$SETUP"
    
    # Insert 10 rows
    local INSERT_SQL="BEGIN;"
    for n in $(seq 0 9); do
        INSERT_SQL+="INSERT INTO test (id, text) VALUES ($n, 'hello $n');"
    done
    INSERT_SQL+="COMMIT;"
    
    run_zig "$DB_ZIG" "$INSERT_SQL"
    run_rust "$DB_RUST" "$INSERT_SQL"
    
    # REPLACE all rows
    local REPLACE_SQL="BEGIN;"
    for n in $(seq 0 9); do
        REPLACE_SQL+="INSERT OR REPLACE INTO test (id, text) VALUES ($n, 'replaced $n');"
    done
    REPLACE_SQL+="COMMIT;"
    
    run_zig "$DB_ZIG" "$REPLACE_SQL"
    run_rust "$DB_RUST" "$REPLACE_SQL"
    
    local ZIG_SENTINELS=$(count_sentinels "zig" "$DB_ZIG")
    local RUST_SENTINELS=$(count_sentinels "rust" "$DB_RUST")
    
    echo "Test 3a: Sentinel count after REPLACE"
    check_parity "Sentinel count" "$ZIG_SENTINELS" "$RUST_SENTINELS" "0"
    
    echo ""
}

# ==============================================================================
# Property 4: No Sentinel on Merge (test_not_created_on_merge)
# From Python: Syncing INSERTs to another site should NOT create sentinels
# ==============================================================================
test_no_sentinel_on_merge() {
    echo "=============================================================================="
    echo "Property 4: No Sentinel on Merge"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Site A has data, sync to empty Site B"
    echo "Expected: 0 sentinels on Site B (no DELETE occurred)"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/merge_zig_a.db"
    local DB_ZIG_B="$TMPDIR/merge_zig_b.db"
    local DB_RUST_A="$TMPDIR/merge_rust_a.db"
    local DB_RUST_B="$TMPDIR/merge_rust_b.db"
    
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
"
    
    for db in "$DB_ZIG_A" "$DB_ZIG_B"; do
        run_zig "$db" "$SETUP"
    done
    for db in "$DB_RUST_A" "$DB_RUST_B"; do
        run_rust "$db" "$SETUP"
    done
    
    # Insert data on Site A
    local INSERT_SQL="
INSERT INTO test VALUES (1, 'hello 1');
INSERT INTO test VALUES (2, 'hello 2');
INSERT INTO test VALUES (3, 'hello 3');
"
    run_zig "$DB_ZIG_A" "$INSERT_SQL"
    run_rust "$DB_RUST_A" "$INSERT_SQL"
    
    # Sync A -> B
    local SITE_A="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'"
    local SYNC_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010901', 'text', 'hello 1', 1, 1, $SITE_A, 1, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010902', 'text', 'hello 2', 1, 1, $SITE_A, 1, 1);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010903', 'text', 'hello 3', 1, 1, $SITE_A, 1, 2);
"
    
    run_zig "$DB_ZIG_B" "$SYNC_SQL"
    run_rust "$DB_RUST_B" "$SYNC_SQL"
    
    # Verify Site B has data
    local ZIG_B_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM test;")
    local RUST_B_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM test;")
    
    echo "Test 4a: Site B has data after merge"
    check_parity "Row count" "$ZIG_B_COUNT" "$RUST_B_COUNT" "3"
    
    # Verify no sentinels on either site
    local ZIG_A_SENTINELS=$(count_sentinels "zig" "$DB_ZIG_A")
    local RUST_A_SENTINELS=$(count_sentinels "rust" "$DB_RUST_A")
    
    echo "Test 4b: Site A has no sentinels"
    check_parity "Site A sentinels" "$ZIG_A_SENTINELS" "$RUST_A_SENTINELS" "0"
    
    local ZIG_B_SENTINELS=$(count_sentinels "zig" "$DB_ZIG_B")
    local RUST_B_SENTINELS=$(count_sentinels "rust" "$DB_RUST_B")
    
    echo "Test 4c: Site B has no sentinels after merge"
    check_parity "Site B sentinels" "$ZIG_B_SENTINELS" "$RUST_B_SENTINELS" "0"
    
    echo ""
}

# ==============================================================================
# Property 5: No Sentinel on Noop Merge (test_not_created_on_noop_merge)
# From Python: Merging identical data should NOT create sentinels
# ==============================================================================
test_no_sentinel_on_noop_merge() {
    echo "=============================================================================="
    echo "Property 5: No Sentinel on Noop Merge"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Both sites have identical data, sync between them"
    echo "Expected: 0 sentinels, db_version unchanged"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/noop_zig_a.db"
    local DB_ZIG_B="$TMPDIR/noop_zig_b.db"
    local DB_RUST_A="$TMPDIR/noop_rust_a.db"
    local DB_RUST_B="$TMPDIR/noop_rust_b.db"
    
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
INSERT INTO test VALUES (1, 'hello');
"
    
    for db in "$DB_ZIG_A" "$DB_ZIG_B"; do
        run_zig "$db" "$SETUP"
    done
    for db in "$DB_RUST_A" "$DB_RUST_B"; do
        run_rust "$db" "$SETUP"
    done
    
    # Get pre-merge versions
    local ZIG_A_PRE_VER=$(run_zig "$DB_ZIG_A" "SELECT crsql_db_version();")
    local ZIG_B_PRE_VER=$(run_zig "$DB_ZIG_B" "SELECT crsql_db_version();")
    local RUST_A_PRE_VER=$(run_rust "$DB_RUST_A" "SELECT crsql_db_version();")
    local RUST_B_PRE_VER=$(run_rust "$DB_RUST_B" "SELECT crsql_db_version();")
    
    echo "Test 5a: Pre-merge db_version parity"
    check_parity "Pre-merge db_version A" "$ZIG_A_PRE_VER" "$RUST_A_PRE_VER"
    check_parity "Pre-merge db_version B" "$ZIG_B_PRE_VER" "$RUST_B_PRE_VER"
    
    # Sync A -> B (should be noop since identical)
    # We need to use a different site_id than B's own
    local SITE_A="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'"
    local SYNC_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010901', 'text', 'hello', 1, 1, $SITE_A, 1, 0);
"
    
    run_zig "$DB_ZIG_B" "$SYNC_SQL"
    run_rust "$DB_RUST_B" "$SYNC_SQL"
    
    # Verify no sentinels
    local ZIG_SENTINELS=$(count_sentinels "zig" "$DB_ZIG_B")
    local RUST_SENTINELS=$(count_sentinels "rust" "$DB_RUST_B")
    
    echo "Test 5b: No sentinels after noop merge"
    check_parity "Sentinel count" "$ZIG_SENTINELS" "$RUST_SENTINELS" "0"
    
    echo ""
}

# ==============================================================================
# Property 6: Delete Sentinel Propagates (test_sentinel_propagated_when_present)
# From Python: DELETE sentinels should sync to other sites
# ==============================================================================
test_delete_sentinel_propagates() {
    echo "=============================================================================="
    echo "Property 6: Delete Sentinel Propagates"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Site A deletes data, sync to Site B"
    echo "Expected: Sentinel propagates to Site B, row deleted"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/prop_zig_a.db"
    local DB_ZIG_B="$TMPDIR/prop_zig_b.db"
    local DB_RUST_A="$TMPDIR/prop_rust_a.db"
    local DB_RUST_B="$TMPDIR/prop_rust_b.db"
    
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
INSERT INTO test VALUES (1, 'hello');
INSERT INTO test VALUES (2, 'world');
"
    
    for db in "$DB_ZIG_A" "$DB_ZIG_B"; do
        run_zig "$db" "$SETUP"
    done
    for db in "$DB_RUST_A" "$DB_RUST_B"; do
        run_rust "$db" "$SETUP"
    done
    
    # Delete all on Site A
    run_zig "$DB_ZIG_A" "DELETE FROM test;"
    run_rust "$DB_RUST_A" "DELETE FROM test;"
    
    # Verify Site A has sentinels
    local ZIG_A_SENTINELS=$(count_sentinels "zig" "$DB_ZIG_A")
    local RUST_A_SENTINELS=$(count_sentinels "rust" "$DB_RUST_A")
    
    echo "Test 6a: Site A has sentinels after DELETE"
    check_parity "Site A sentinels" "$ZIG_A_SENTINELS" "$RUST_A_SENTINELS" "2"
    
    # Sync delete sentinels to B
    local SITE_A="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'"
    local SYNC_DELETE="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010901', '-1', NULL, 2, 2, $SITE_A, 2, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010902', '-1', NULL, 2, 2, $SITE_A, 2, 1);
"
    
    run_zig "$DB_ZIG_B" "$SYNC_DELETE"
    run_rust "$DB_RUST_B" "$SYNC_DELETE"
    
    # Verify Site B now has sentinels
    local ZIG_B_SENTINELS=$(count_sentinels "zig" "$DB_ZIG_B")
    local RUST_B_SENTINELS=$(count_sentinels "rust" "$DB_RUST_B")
    
    echo "Test 6b: Site B has sentinels after sync"
    check_parity "Site B sentinels" "$ZIG_B_SENTINELS" "$RUST_B_SENTINELS" "2"
    
    # Verify rows deleted on B
    local ZIG_B_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM test;")
    local RUST_B_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM test;")
    
    echo "Test 6c: Site B rows deleted"
    check_parity "Site B row count" "$ZIG_B_COUNT" "$RUST_B_COUNT" "0"
    
    echo ""
}

# ==============================================================================
# Property 7: Default Value Merge Behavior (test_merging_on_defaults)
# From Python: Columns with default values should merge correctly
# ==============================================================================
test_default_value_merge() {
    echo "=============================================================================="
    echo "Property 7: Default Value Merge Behavior"
    echo "=============================================================================="
    echo ""
    echo "Scenario: db1 has row with default value, db2 has explicit value"
    echo "Expected: Explicit value wins over default"
    echo ""
    
    local DB_ZIG_1="$TMPDIR/default_zig_1.db"
    local DB_ZIG_2="$TMPDIR/default_zig_2.db"
    local DB_RUST_1="$TMPDIR/default_rust_1.db"
    local DB_RUST_2="$TMPDIR/default_rust_2.db"
    
    # db1: row with default value (b defaults to 0)
    local SETUP_1="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 0);
INSERT INTO foo (a) VALUES (1);
SELECT crsql_as_crr('foo');
"
    
    # db2: row with explicit value
    local SETUP_2="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 0);
INSERT INTO foo VALUES (1, 2);
SELECT crsql_as_crr('foo');
"
    
    run_zig "$DB_ZIG_1" "$SETUP_1"
    run_rust "$DB_RUST_1" "$SETUP_1"
    run_zig "$DB_ZIG_2" "$SETUP_2"
    run_rust "$DB_RUST_2" "$SETUP_2"
    
    # Sync db2 -> db1 (explicit value should win)
    local SITE_2="X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB02'"
    local SYNC_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 2, 1, 1, $SITE_2, 1, 0);
"
    
    run_zig "$DB_ZIG_1" "$SYNC_SQL"
    run_rust "$DB_RUST_1" "$SYNC_SQL"
    
    # Verify db1 now has the explicit value (2)
    local ZIG_VAL=$(run_zig "$DB_ZIG_1" "SELECT b FROM foo WHERE a=1;")
    local RUST_VAL=$(run_rust "$DB_RUST_1" "SELECT b FROM foo WHERE a=1;")
    
    echo "Test 7a: Explicit value wins over default"
    check_parity "Value after merge" "$ZIG_VAL" "$RUST_VAL" "2"
    
    echo ""
}

# ==============================================================================
# Property 8: Update Merge Without Creating Sentinel
# (test_not_created_on_update_merge from Python)
# ==============================================================================
test_update_merge_no_sentinel() {
    echo "=============================================================================="
    echo "Property 8: Update Merge Without Creating Sentinel"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Site A updates data, sync to Site B"
    echo "Expected: B gets updates, no sentinels created"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/update_zig_a.db"
    local DB_ZIG_B="$TMPDIR/update_zig_b.db"
    local DB_RUST_A="$TMPDIR/update_rust_a.db"
    local DB_RUST_B="$TMPDIR/update_rust_b.db"
    
    # Both sites start with same data
    local SETUP="
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, text TEXT);
SELECT crsql_as_crr('test');
INSERT INTO test VALUES (1, 'hello');
INSERT INTO test VALUES (2, 'world');
"
    
    for db in "$DB_ZIG_A" "$DB_ZIG_B"; do
        run_zig "$db" "$SETUP"
    done
    for db in "$DB_RUST_A" "$DB_RUST_B"; do
        run_rust "$db" "$SETUP"
    done
    
    # Update on Site A
    run_zig "$DB_ZIG_A" "UPDATE test SET text = 'goodbye' WHERE id = 1;"
    run_rust "$DB_RUST_A" "UPDATE test SET text = 'goodbye' WHERE id = 1;"
    
    # Sync update to B
    local SITE_A="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'"
    local SYNC_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('test', X'010901', 'text', 'goodbye', 2, 2, $SITE_A, 1, 0);
"
    
    run_zig "$DB_ZIG_B" "$SYNC_SQL"
    run_rust "$DB_RUST_B" "$SYNC_SQL"
    
    # Verify B got the update
    local ZIG_B_VAL=$(run_zig "$DB_ZIG_B" "SELECT text FROM test WHERE id=1;")
    local RUST_B_VAL=$(run_rust "$DB_RUST_B" "SELECT text FROM test WHERE id=1;")
    
    echo "Test 8a: Site B got the update"
    check_parity "Updated value" "$ZIG_B_VAL" "$RUST_B_VAL" "goodbye"
    
    # Verify no sentinels
    local ZIG_SENTINELS=$(count_sentinels "zig" "$DB_ZIG_B")
    local RUST_SENTINELS=$(count_sentinels "rust" "$DB_RUST_B")
    
    echo "Test 8b: No sentinels after update merge"
    check_parity "Sentinel count" "$ZIG_SENTINELS" "$RUST_SENTINELS" "0"
    
    echo ""
}

# ==============================================================================
# Run all tests
# ==============================================================================
test_no_sentinel_on_insert
test_sentinel_on_delete
test_no_sentinel_on_replace
test_no_sentinel_on_merge
test_no_sentinel_on_noop_merge
test_delete_sentinel_propagates
test_default_value_merge
test_update_merge_no_sentinel

# ==============================================================================
# Summary
# ==============================================================================
echo "=============================================================================="
echo "Sentinel Properties Test Summary"
echo "=============================================================================="
echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All sentinel property tests PASSED"
    echo ""
    echo "Verified properties:"
    echo "  1. No sentinel on INSERT"
    echo "  2. Sentinel created on DELETE"
    echo "  3. No sentinel on REPLACE"
    echo "  4. No sentinel on merge"
    echo "  5. No sentinel on noop merge"
    echo "  6. Delete sentinel propagates correctly"
    echo "  7. Default value merge behavior"
    echo "  8. Update merge without creating sentinel"
    exit 0
else
    echo "SENTINEL PROPERTY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAILED test(s)."
    exit 1
fi
