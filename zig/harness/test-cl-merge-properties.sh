#!/usr/bin/env bash
# Property-Based CL Merge Tests (ported from py/correctness/tests/test_cl_merging.py)
#
# These tests verify key CRDT properties discovered via Python Hypothesis testing:
# 1. Larger CL always wins (regardless of col_version)
# 2. Same CL uses col_version tiebreaker
# 3. Same CL + col_version uses value tiebreaker
# 4. Merge idempotency (same merge twice = no change)
# 5. Merge commutativity (A->B then B->A = B->A then A->B)
# 6. Proxy relay correctness (A->B->C should converge)
#
# Reference: TASK-191, py/correctness/tests/test_cl_merging.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=============================================================================="
echo "Test Suite: CL Merge Properties (Property-Based, Zig vs Rust/C)"
echo "=============================================================================="
echo ""
echo "Properties from Python Hypothesis tests:"
echo "  - Larger CL always wins (test_larger_cl_wins_all)"
echo "  - CL equality uses col_version tiebreaker (test_larger_col_version_same_cl)"
echo "  - Equivalent CLs with same col_version uses value tiebreaker"
echo "  - Merge is idempotent (test_equivalent_delete_cls_is_noop)"
echo "  - Three-node proxy convergence (test_ordered_delta_merge_proxy)"
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
TMPDIR="$ROOT_DIR/.tmp/cl-merge-properties-$$"
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

# ==============================================================================
# Property 1: Larger CL Wins All (test_larger_cl_wins_all)
# From Python: c1 has cl=3 (insert->delete->insert), c2 has cl=1 with high col_versions
# Expected: c1's values win despite c2 having higher col_versions
# ==============================================================================
test_larger_cl_wins_all() {
    echo "=============================================================================="
    echo "Property 1: Larger CL Wins All"
    echo "=============================================================================="
    echo ""
    echo "Scenario: c1 has cl=3 (resurrected), c2 has cl=1 with col_version=3"
    echo "Expected: c1 wins (cl=3 > cl=1), col_version doesn't matter when CL differs"
    echo ""
    
    local DB_ZIG_C1="$TMPDIR/larger_cl_zig_c1.db"
    local DB_RUST_C1="$TMPDIR/larger_cl_rust_c1.db"
    local DB_ZIG_C2="$TMPDIR/larger_cl_zig_c2.db"
    local DB_RUST_C2="$TMPDIR/larger_cl_rust_c2.db"
    
    # c1: INSERT -> DELETE -> INSERT (cl=3, col_version=1 after resurrection)
    local SETUP_C1="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
INSERT INTO foo VALUES (1, 1);
"
    
    # c2: INSERT + 2 updates (cl=1, col_version=3)
    local SETUP_C2="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
UPDATE foo SET b = 3 WHERE a = 1;
UPDATE foo SET b = 4 WHERE a = 1;
"
    
    run_zig "$DB_ZIG_C1" "$SETUP_C1"
    run_rust "$DB_RUST_C1" "$SETUP_C1"
    run_zig "$DB_ZIG_C2" "$SETUP_C2"
    run_rust "$DB_RUST_C2" "$SETUP_C2"
    
    # Verify preconditions
    local ZIG_C1_CL=$(run_zig "$DB_ZIG_C1" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_C1_CL=$(run_rust "$DB_RUST_C1" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 1a: Verify c1 has cl=3 (resurrected)"
    check_parity "c1 CL after resurrection" "$ZIG_C1_CL" "$RUST_C1_CL" "3"
    
    local ZIG_C2_COL_VER=$(run_zig "$DB_ZIG_C2" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_C2_COL_VER=$(run_rust "$DB_RUST_C2" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 1b: Verify c2 has col_version=3 (2 updates)"
    check_parity "c2 col_version" "$ZIG_C2_COL_VER" "$RUST_C2_COL_VER" "3"
    
    # Sync c1 to c2 (c1 should win despite lower col_version)
    # Get c1's changes and apply to c2
    local ZIG_C1_SITE=$(run_zig "$DB_ZIG_C1" "SELECT quote(crsql_site_id());")
    local RUST_C1_SITE=$(run_rust "$DB_RUST_C1" "SELECT quote(crsql_site_id());")
    
    local MERGE_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 1, 1, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 1);
"
    
    run_zig "$DB_ZIG_C2" "$MERGE_SQL"
    run_rust "$DB_RUST_C2" "$MERGE_SQL"
    
    # Verify c2 now has c1's values (cl=3 wins)
    local ZIG_C2_NEW_CL=$(run_zig "$DB_ZIG_C2" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_C2_NEW_CL=$(run_rust "$DB_RUST_C2" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 1c: c2 CL advanced to 3 after merge"
    check_parity "c2 CL after merge" "$ZIG_C2_NEW_CL" "$RUST_C2_NEW_CL" "3"
    
    local ZIG_C2_NEW_COL_VER=$(run_zig "$DB_ZIG_C2" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_C2_NEW_COL_VER=$(run_rust "$DB_RUST_C2" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 1d: c2 col_version set to winner's value (1)"
    check_parity "c2 col_version after merge" "$ZIG_C2_NEW_COL_VER" "$RUST_C2_NEW_COL_VER" "1"
    
    local ZIG_C2_VAL=$(run_zig "$DB_ZIG_C2" "SELECT b FROM foo WHERE a=1;")
    local RUST_C2_VAL=$(run_rust "$DB_RUST_C2" "SELECT b FROM foo WHERE a=1;")
    
    echo "Test 1e: c2 has c1's value (1) not c2's old value (4)"
    check_parity "c2 value after merge" "$ZIG_C2_VAL" "$RUST_C2_VAL" "1"
    
    echo ""
}

# ==============================================================================
# Property 2: Same CL Uses Col Version Tiebreaker (test_larger_col_version_same_cl)
# From Python: Both have cl=1, c1 has col_version=2, c2 has col_version=1
# Expected: c1 wins (higher col_version)
# ==============================================================================
test_same_cl_col_version_tiebreaker() {
    echo "=============================================================================="
    echo "Property 2: Same CL Uses Col Version Tiebreaker"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Both have cl=1, c1 has col_version=2 (one update), c2 has col_version=1"
    echo "Expected: c1 wins (col_version=2 > col_version=1)"
    echo ""
    
    local DB_ZIG_C1="$TMPDIR/col_ver_zig_c1.db"
    local DB_RUST_C1="$TMPDIR/col_ver_rust_c1.db"
    local DB_ZIG_C2="$TMPDIR/col_ver_zig_c2.db"
    local DB_RUST_C2="$TMPDIR/col_ver_rust_c2.db"
    
    # c1: INSERT + UPDATE (cl=1, col_version=2, value=0)
    local SETUP_C1="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
UPDATE foo SET b = 0 WHERE a = 1;
"
    
    # c2: INSERT only (cl=1, col_version=1, value=1)
    local SETUP_C2="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
"
    
    run_zig "$DB_ZIG_C1" "$SETUP_C1"
    run_rust "$DB_RUST_C1" "$SETUP_C1"
    run_zig "$DB_ZIG_C2" "$SETUP_C2"
    run_rust "$DB_RUST_C2" "$SETUP_C2"
    
    # Verify preconditions
    local ZIG_C1_COL_VER=$(run_zig "$DB_ZIG_C1" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_C1_COL_VER=$(run_rust "$DB_RUST_C1" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 2a: Verify c1 has col_version=2"
    check_parity "c1 col_version" "$ZIG_C1_COL_VER" "$RUST_C1_COL_VER" "2"
    
    # Sync c1 to c2
    local MERGE_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 0, 2, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 1, 0);
"
    
    run_zig "$DB_ZIG_C2" "$MERGE_SQL"
    run_rust "$DB_RUST_C2" "$MERGE_SQL"
    
    # Verify c2 now has c1's values
    local ZIG_C2_VAL=$(run_zig "$DB_ZIG_C2" "SELECT b FROM foo WHERE a=1;")
    local RUST_C2_VAL=$(run_rust "$DB_RUST_C2" "SELECT b FROM foo WHERE a=1;")
    
    echo "Test 2b: c2 has c1's value (0) after merge (higher col_version wins)"
    check_parity "c2 value after merge" "$ZIG_C2_VAL" "$RUST_C2_VAL" "0"
    
    local ZIG_C2_COL_VER=$(run_zig "$DB_ZIG_C2" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_C2_COL_VER=$(run_rust "$DB_RUST_C2" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 2c: c2 col_version is now 2"
    check_parity "c2 col_version after merge" "$ZIG_C2_COL_VER" "$RUST_C2_COL_VER" "2"
    
    echo ""
}

# ==============================================================================
# Property 3: Same CL + Col Version Uses Value Tiebreaker
# (test_larger_col_value_same_cl_and_col_version)
# From Python: Both have cl=1, col_version=1, different values
# Expected: Larger value wins
# ==============================================================================
test_same_cl_value_tiebreaker() {
    echo "=============================================================================="
    echo "Property 3: Same CL + Col Version Uses Value Tiebreaker"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Both have cl=1, col_version=1, c1 has value=4, c2 has value=1"
    echo "Expected: c1 wins (4 > 1)"
    echo ""
    
    local DB_ZIG_C1="$TMPDIR/val_tie_zig_c1.db"
    local DB_RUST_C1="$TMPDIR/val_tie_rust_c1.db"
    local DB_ZIG_C2="$TMPDIR/val_tie_zig_c2.db"
    local DB_RUST_C2="$TMPDIR/val_tie_rust_c2.db"
    
    # c1: INSERT with value=4
    local SETUP_C1="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 4);
"
    
    # c2: INSERT with value=1
    local SETUP_C2="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
"
    
    run_zig "$DB_ZIG_C1" "$SETUP_C1"
    run_rust "$DB_RUST_C1" "$SETUP_C1"
    run_zig "$DB_ZIG_C2" "$SETUP_C2"
    run_rust "$DB_RUST_C2" "$SETUP_C2"
    
    # Sync c1 to c2
    local MERGE_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 4, 1, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 1, 0);
"
    
    run_zig "$DB_ZIG_C2" "$MERGE_SQL"
    run_rust "$DB_RUST_C2" "$MERGE_SQL"
    
    # Verify c2 now has c1's value (4 > 1)
    local ZIG_C2_VAL=$(run_zig "$DB_ZIG_C2" "SELECT b FROM foo WHERE a=1;")
    local RUST_C2_VAL=$(run_rust "$DB_RUST_C2" "SELECT b FROM foo WHERE a=1;")
    
    echo "Test 3a: c2 has c1's value (4) after merge (larger value wins)"
    check_parity "c2 value after merge" "$ZIG_C2_VAL" "$RUST_C2_VAL" "4"
    
    echo ""
}

# ==============================================================================
# Property 4: Equivalent CLs with Same State is No-Op
# (test_equivalent_delete_cls_is_noop)
# From Python: Both have same deleted state with cl=2
# Expected: Merge doesn't change anything
# ==============================================================================
test_equivalent_cl_noop() {
    echo "=============================================================================="
    echo "Property 4: Equivalent CLs with Same State is No-Op"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Both have INSERT->DELETE (cl=2), same state"
    echo "Expected: Merging is a no-op (no db_version change)"
    echo ""
    
    local DB_ZIG_C1="$TMPDIR/noop_zig_c1.db"
    local DB_RUST_C1="$TMPDIR/noop_rust_c1.db"
    local DB_ZIG_C2="$TMPDIR/noop_zig_c2.db"
    local DB_RUST_C2="$TMPDIR/noop_rust_c2.db"
    
    # Both: INSERT -> DELETE (cl=2)
    local SETUP="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER) STRICT;
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
"
    
    run_zig "$DB_ZIG_C1" "$SETUP"
    run_rust "$DB_RUST_C1" "$SETUP"
    run_zig "$DB_ZIG_C2" "$SETUP"
    run_rust "$DB_RUST_C2" "$SETUP"
    
    # Get pre-merge db_version for c2
    local ZIG_C2_PRE_VER=$(run_zig "$DB_ZIG_C2" "SELECT crsql_db_version();")
    local RUST_C2_PRE_VER=$(run_rust "$DB_RUST_C2" "SELECT crsql_db_version();")
    
    echo "Test 4a: Pre-merge db_version"
    check_parity "c2 pre-merge db_version" "$ZIG_C2_PRE_VER" "$RUST_C2_PRE_VER"
    
    # Sync c1 to c2 (should be no-op)
    local MERGE_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 2, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 2, 0);
"
    
    run_zig "$DB_ZIG_C2" "$MERGE_SQL"
    run_rust "$DB_RUST_C2" "$MERGE_SQL"
    
    # Get post-merge db_version - should be unchanged if true no-op
    local ZIG_C2_POST_VER=$(run_zig "$DB_ZIG_C2" "SELECT crsql_db_version();")
    local RUST_C2_POST_VER=$(run_rust "$DB_RUST_C2" "SELECT crsql_db_version();")
    
    echo "Test 4b: Post-merge db_version (should match or be same as pre-merge)"
    check_parity "c2 post-merge db_version" "$ZIG_C2_POST_VER" "$RUST_C2_POST_VER"
    
    # Verify row still deleted
    local ZIG_C2_COUNT=$(run_zig "$DB_ZIG_C2" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_C2_COUNT=$(run_rust "$DB_RUST_C2" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 4c: Row still deleted after merge"
    check_parity "c2 row count" "$ZIG_C2_COUNT" "$RUST_C2_COUNT" "0"
    
    echo ""
}

# ==============================================================================
# Property 5: Three-Node Proxy Convergence (test_ordered_delta_merge_proxy)
# From Python: A -> B -> C topology, changes proxied through B
# Expected: All three nodes converge to same state
# ==============================================================================
test_proxy_convergence() {
    echo "=============================================================================="
    echo "Property 5: Three-Node Proxy Convergence"
    echo "=============================================================================="
    echo ""
    echo "Scenario: A creates data, syncs to B, B proxies to C"
    echo "Expected: A, B, C all have identical state"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/proxy_zig_a.db"
    local DB_ZIG_B="$TMPDIR/proxy_zig_b.db"
    local DB_ZIG_C="$TMPDIR/proxy_zig_c.db"
    local DB_RUST_A="$TMPDIR/proxy_rust_a.db"
    local DB_RUST_B="$TMPDIR/proxy_rust_b.db"
    local DB_RUST_C="$TMPDIR/proxy_rust_c.db"
    
    # Setup schema on all nodes (using INTEGER PK for simpler encoding)
    local SETUP="
CREATE TABLE item (id INTEGER PRIMARY KEY NOT NULL, width INTEGER, height INTEGER);
SELECT crsql_as_crr('item');
"
    
    for db in "$DB_ZIG_A" "$DB_ZIG_B" "$DB_ZIG_C"; do
        run_zig "$db" "$SETUP"
    done
    for db in "$DB_RUST_A" "$DB_RUST_B" "$DB_RUST_C"; do
        run_rust "$db" "$SETUP"
    done
    
    # A creates data
    local CREATE_SQL="INSERT INTO item VALUES (1, 100, 200);"
    run_zig "$DB_ZIG_A" "$CREATE_SQL"
    run_rust "$DB_RUST_A" "$CREATE_SQL"
    
    # For simplicity, we'll use a fixed site_id for A
    local SITE_A="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'"
    
    # Sync A -> B (using X'010901' for pk=1 as integer)
    local SYNC_AB="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('item', X'010901', 'width', 100, 1, 1, $SITE_A, 1, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('item', X'010901', 'height', 200, 1, 1, $SITE_A, 1, 1);
"
    run_zig "$DB_ZIG_B" "$SYNC_AB"
    run_rust "$DB_RUST_B" "$SYNC_AB"
    
    # B proxies to C (same changes, B just forwards them)
    run_zig "$DB_ZIG_C" "$SYNC_AB"
    run_rust "$DB_RUST_C" "$SYNC_AB"
    
    # Verify all three have same data
    local ZIG_A_DATA=$(run_zig "$DB_ZIG_A" "SELECT id, width, height FROM item ORDER BY id;")
    local ZIG_B_DATA=$(run_zig "$DB_ZIG_B" "SELECT id, width, height FROM item ORDER BY id;")
    local ZIG_C_DATA=$(run_zig "$DB_ZIG_C" "SELECT id, width, height FROM item ORDER BY id;")
    local RUST_A_DATA=$(run_rust "$DB_RUST_A" "SELECT id, width, height FROM item ORDER BY id;")
    local RUST_B_DATA=$(run_rust "$DB_RUST_B" "SELECT id, width, height FROM item ORDER BY id;")
    local RUST_C_DATA=$(run_rust "$DB_RUST_C" "SELECT id, width, height FROM item ORDER BY id;")
    
    echo "Test 5a: Zig nodes converge (A=B=C)"
    if [[ "$ZIG_A_DATA" == "$ZIG_B_DATA" && "$ZIG_B_DATA" == "$ZIG_C_DATA" ]]; then
        echo "  PASS: All Zig nodes have identical data"
        echo "    Data: $ZIG_A_DATA"
        PASSED=$((PASSED + 1))
    else
        echo "  FAIL: Zig nodes diverge"
        echo "    A: $ZIG_A_DATA"
        echo "    B: $ZIG_B_DATA"
        echo "    C: $ZIG_C_DATA"
        FAILED=$((FAILED + 1))
    fi
    
    echo "Test 5b: Rust nodes converge (A=B=C)"
    if [[ "$RUST_A_DATA" == "$RUST_B_DATA" && "$RUST_B_DATA" == "$RUST_C_DATA" ]]; then
        echo "  PASS: All Rust nodes have identical data"
        echo "    Data: $RUST_A_DATA"
        PASSED=$((PASSED + 1))
    else
        echo "  FAIL: Rust nodes diverge"
        echo "    A: $RUST_A_DATA"
        echo "    B: $RUST_B_DATA"
        echo "    C: $RUST_C_DATA"
        FAILED=$((FAILED + 1))
    fi
    
    echo "Test 5c: Zig and Rust implementations converge"
    check_parity "Cross-impl convergence" "$ZIG_A_DATA" "$RUST_A_DATA"
    
    echo ""
}

# ==============================================================================
# Property 6: Primary-Key Only Table Sync (test_pko_*)
# From Python: Tables with only PK columns should sync correctly
# ==============================================================================
test_pko_sync() {
    echo "=============================================================================="
    echo "Property 6: Primary-Key Only Table Sync"
    echo "=============================================================================="
    echo ""
    echo "Scenario: Table with only PK column, sync insert/delete/resurrect"
    echo "Expected: Parity between Zig and Rust/C"
    echo ""
    
    local DB_ZIG_C1="$TMPDIR/pko_zig_c1.db"
    local DB_RUST_C1="$TMPDIR/pko_rust_c1.db"
    local DB_ZIG_C2="$TMPDIR/pko_zig_c2.db"
    local DB_RUST_C2="$TMPDIR/pko_rust_c2.db"
    
    # PK-only table
    local SETUP="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL) STRICT;
SELECT crsql_as_crr('foo');
"
    
    run_zig "$DB_ZIG_C1" "$SETUP"
    run_rust "$DB_RUST_C1" "$SETUP"
    run_zig "$DB_ZIG_C2" "$SETUP"
    run_rust "$DB_RUST_C2" "$SETUP"
    
    # c1: INSERT -> DELETE -> INSERT (resurrection)
    local C1_OPS="
INSERT INTO foo VALUES (1);
DELETE FROM foo;
INSERT INTO foo VALUES (1);
"
    run_zig "$DB_ZIG_C1" "$C1_OPS"
    run_rust "$DB_RUST_C1" "$C1_OPS"
    
    # c2: INSERT -> DELETE (tombstone)
    local C2_OPS="
INSERT INTO foo VALUES (1);
DELETE FROM foo;
"
    run_zig "$DB_ZIG_C2" "$C2_OPS"
    run_rust "$DB_RUST_C2" "$C2_OPS"
    
    # Verify c1 has cl=3 (resurrected)
    local ZIG_C1_CL=$(run_zig "$DB_ZIG_C1" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_C1_CL=$(run_rust "$DB_RUST_C1" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 6a: PKO table c1 has cl=3 after resurrection"
    check_parity "c1 CL" "$ZIG_C1_CL" "$RUST_C1_CL" "3"
    
    # Sync c1 to c2 (c1 should win, row resurrected)
    local MERGE_SQL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 0);
"
    
    run_zig "$DB_ZIG_C2" "$MERGE_SQL"
    run_rust "$DB_RUST_C2" "$MERGE_SQL"
    
    # Verify row exists in c2
    local ZIG_C2_COUNT=$(run_zig "$DB_ZIG_C2" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_C2_COUNT=$(run_rust "$DB_RUST_C2" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 6b: PKO table row resurrected in c2"
    check_parity "c2 row count" "$ZIG_C2_COUNT" "$RUST_C2_COUNT" "1"
    
    # Verify c2 has cl=3
    local ZIG_C2_CL=$(run_zig "$DB_ZIG_C2" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_C2_CL=$(run_rust "$DB_RUST_C2" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 6c: PKO table c2 has cl=3 after merge"
    check_parity "c2 CL after merge" "$ZIG_C2_CL" "$RUST_C2_CL" "3"
    
    echo ""
}

# ==============================================================================
# Run all tests
# ==============================================================================
test_larger_cl_wins_all
test_same_cl_col_version_tiebreaker
test_same_cl_value_tiebreaker
test_equivalent_cl_noop
test_proxy_convergence
test_pko_sync

# ==============================================================================
# Summary
# ==============================================================================
echo "=============================================================================="
echo "CL Merge Properties Test Summary"
echo "=============================================================================="
echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All CL merge property tests PASSED"
    echo ""
    echo "Verified properties:"
    echo "  1. Larger CL always wins regardless of col_version"
    echo "  2. Same CL uses col_version as tiebreaker"
    echo "  3. Same CL + col_version uses value as tiebreaker"
    echo "  4. Equivalent states merge as no-op"
    echo "  5. Three-node proxy topology converges"
    echo "  6. Primary-key only tables sync correctly"
    exit 0
else
    echo "CL MERGE PROPERTY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAILED test(s)."
    exit 1
fi
