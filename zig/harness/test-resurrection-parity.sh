#!/usr/bin/env bash
# Resurrection Parity Tests for Zig CR-SQLite
# Tests that resurrection scenarios (via sentinel or column update) produce identical
# behavior in both Zig and Rust/C implementations.
#
# Tests (from py/correctness/tests/test_cl_merging.py):
# 1. test_live_via_sentinel - Sentinel arrives for already-live row
# 2. test_dead_via_sentinel - Sentinel resurrects tombstoned row
# 3. test_live_via_column - Column update on live row (CL verification)
# 4. test_dead_via_column - Column update resurrects tombstoned row
# 5. test_out_of_order - Changes arrive in wrong order (delete after resurrect)
#
# Reference: TASK-161, py/correctness/tests/test_cl_merging.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Resurrection Parity (Zig vs Rust/C)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Tests resurrection scenarios: sentinel/column update on live/dead rows"
echo "Verifies both implementations produce identical state and CL values"
echo ""

# Build the Zig extension
echo "Building Zig extension..."
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo "FAIL: Zig build failed"
    exit 1
fi

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
fi

# Verify extensions exist
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    exit 1
fi

if [[ ! -f "$RUST_EXT" ]]; then
    echo "ERROR: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 1
fi

SQLITE="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/resurrection-parity-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

ERRFILE="$TMPDIR/error.txt"

PASS=0
FAIL=0
SKIP=0

# Helper to run SQL with Zig extension
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Helper to run SQL with Rust/C extension
run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

# Check for blocking errors
is_blocked() {
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function" "$ERRFILE"; then
            return 0
        fi
    fi
    return 1
}

# Compare two values and report parity
check_parity() {
    local test_name="$1"
    local zig_val="$2"
    local rust_val="$3"
    local expected="$4"  # optional expected value
    
    if [[ "$zig_val" == "$rust_val" ]]; then
        if [[ -n "$expected" && "$zig_val" != "$expected" ]]; then
            echo "  FAIL: $test_name - values match but not expected"
            echo "    Both have: $zig_val"
            echo "    Expected:  $expected"
            FAIL=$((FAIL + 1))
            return 1
        fi
        echo "  PASS: $test_name"
        if [[ -n "$expected" ]]; then
            echo "    Value: $zig_val (expected: $expected)"
        else
            echo "    Value: $zig_val"
        fi
        PASS=$((PASS + 1))
        return 0
    else
        echo "  FAIL: $test_name - DIVERGENCE"
        echo "    Zig:    $zig_val"
        echo "    Rust/C: $rust_val"
        if [[ -n "$expected" ]]; then
            echo "    Expected: $expected"
        fi
        FAIL=$((FAIL + 1))
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Resurrection of Live Row via Sentinel
# Python test: test_resurrection_of_live_thing_via_sentinel
# Scenario: c1 does INSERT->DELETE->INSERT (cl=3), c2 has INSERT (cl=1)
#           c2 receives only the sentinel from c1's resurrection
#           Row should stay alive, CL should advance to 3, col clocks zeroed
# ══════════════════════════════════════════════════════════════════════════════
test_live_via_sentinel() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test 1: Resurrection of Live Row via Sentinel"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario: Site A has INSERT->DELETE->INSERT (cl=3)"
    echo "          Site B has INSERT only (cl=1)"
    echo "          Site B receives resurrection sentinel (cl=3) from Site A"
    echo "Expected: Row stays alive, CL=3, column clocks zeroed"
    echo ""
    
    # Create source DBs (Site A - the resurrector)
    local DB_ZIG_A="$TMPDIR/live_sentinel_zig_a.db"
    local DB_RUST_A="$TMPDIR/live_sentinel_rust_a.db"
    
    # Create target DBs (Site B - already live)
    local DB_ZIG_B="$TMPDIR/live_sentinel_zig_b.db"
    local DB_RUST_B="$TMPDIR/live_sentinel_rust_b.db"
    
    # Setup Site A: INSERT -> DELETE -> INSERT (resurrection, cl=3)
    local SETUP_A="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
INSERT INTO foo VALUES (1, 1);
"
    
    # Setup Site B: Just INSERT (cl=1)
    local SETUP_B="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
"
    
    run_zig "$DB_ZIG_A" "$SETUP_A"
    run_rust "$DB_RUST_A" "$SETUP_A"
    run_zig "$DB_ZIG_B" "$SETUP_B"
    run_rust "$DB_RUST_B" "$SETUP_B"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        SKIP=$((SKIP + 5))
        return
    fi
    
    # Verify Site A has cl=3 (sentinel)
    local ZIG_A_CL=$(run_zig "$DB_ZIG_A" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_A_CL=$(run_rust "$DB_RUST_A" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 1a: Verify Site A has sentinel with cl=3"
    check_parity "Site A sentinel CL" "$ZIG_A_CL" "$RUST_A_CL" "3"
    
    # Verify Site B has cl=1
    local ZIG_B_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 1b: Verify Site B has cl=1 before merge"
    check_parity "Site B initial CL" "$ZIG_B_CL" "$RUST_B_CL" "1"
    
    # Get Site A's site_id and sentinel change
    local ZIG_A_SITEID=$(run_zig "$DB_ZIG_A" "SELECT quote(crsql_site_id());")
    local RUST_A_SITEID=$(run_rust "$DB_RUST_A" "SELECT quote(crsql_site_id());")
    
    # Get the sentinel row from Site A's changes
    local ZIG_SENTINEL=$(run_zig "$DB_ZIG_A" "SELECT quote(pk), col_version, db_version, cl, seq FROM crsql_changes WHERE cid='-1';")
    local RUST_SENTINEL=$(run_rust "$DB_RUST_A" "SELECT quote(pk), col_version, db_version, cl, seq FROM crsql_changes WHERE cid='-1';")
    
    # Merge only the sentinel to Site B (simulating partial sync)
    # PK encoding for integer 1: X'010901'
    local MERGE_SENTINEL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 0);
"
    
    run_zig "$DB_ZIG_B" "$MERGE_SENTINEL"
    run_rust "$DB_RUST_B" "$MERGE_SENTINEL"
    
    # Verify row still exists
    local ZIG_B_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 1c: Row still exists after sentinel merge"
    check_parity "Row count" "$ZIG_B_COUNT" "$RUST_B_COUNT" "1"
    
    # Verify CL advanced to 3
    local ZIG_B_NEW_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_B_NEW_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 1d: CL advanced to 3 after sentinel merge"
    check_parity "Post-merge sentinel CL" "$ZIG_B_NEW_CL" "$RUST_B_NEW_CL" "3"
    
    # Key behavior: column clocks should be zeroed (col_version=0 for 'b')
    local ZIG_B_COL_VER=$(run_zig "$DB_ZIG_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_COL_VER=$(run_rust "$DB_RUST_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 1e: Column clock zeroed (col_version=0) after resurrection"
    check_parity "Column version zeroed" "$ZIG_B_COL_VER" "$RUST_B_COL_VER" "0"
    
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Resurrection of Dead Row via Sentinel
# Python test: test_resurrection_of_dead_thing_via_sentinel
# Scenario: c1 does INSERT->DELETE->INSERT (cl=3), c2 has INSERT->DELETE (cl=2)
#           c2 receives only the sentinel from c1's resurrection
#           Row should be resurrected, CL should advance to 3
# ══════════════════════════════════════════════════════════════════════════════
test_dead_via_sentinel() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test 2: Resurrection of Dead Row via Sentinel"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario: Site A has INSERT->DELETE->INSERT (cl=3)"
    echo "          Site B has INSERT->DELETE (cl=2, tombstoned)"
    echo "          Site B receives resurrection sentinel (cl=3) from Site A"
    echo "Expected: Row resurrected, CL=3"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/dead_sentinel_zig_a.db"
    local DB_RUST_A="$TMPDIR/dead_sentinel_rust_a.db"
    local DB_ZIG_B="$TMPDIR/dead_sentinel_zig_b.db"
    local DB_RUST_B="$TMPDIR/dead_sentinel_rust_b.db"
    
    # Setup Site A: INSERT -> DELETE -> INSERT (cl=3)
    local SETUP_A="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
INSERT INTO foo VALUES (1, 1);
"
    
    # Setup Site B: INSERT -> DELETE (cl=2, tombstoned)
    local SETUP_B="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
"
    
    run_zig "$DB_ZIG_A" "$SETUP_A"
    run_rust "$DB_RUST_A" "$SETUP_A"
    run_zig "$DB_ZIG_B" "$SETUP_B"
    run_rust "$DB_RUST_B" "$SETUP_B"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        SKIP=$((SKIP + 4))
        return
    fi
    
    # Verify Site B is tombstoned with cl=2
    local ZIG_B_TOMB_CL=$(run_zig "$DB_ZIG_B" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    local RUST_B_TOMB_CL=$(run_rust "$DB_RUST_B" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    
    echo "Test 2a: Verify Site B tombstone has cl=2"
    check_parity "Site B tombstone CL" "$ZIG_B_TOMB_CL" "$RUST_B_TOMB_CL" "2"
    
    # Verify row is deleted in Site B
    local ZIG_B_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 2b: Verify Site B row is deleted before merge"
    check_parity "Site B row count" "$ZIG_B_COUNT" "$RUST_B_COUNT" "0"
    
    # Merge resurrection sentinel from Site A (cl=3)
    local MERGE_SENTINEL="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 0);
"
    
    run_zig "$DB_ZIG_B" "$MERGE_SENTINEL"
    run_rust "$DB_RUST_B" "$MERGE_SENTINEL"
    
    # Verify row is resurrected (row now exists but has no column data yet)
    # Note: The sentinel alone resurrects the row but column values need separate merges
    local ZIG_B_NEW_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_NEW_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 2c: Row resurrected after sentinel merge"
    check_parity "Resurrected row count" "$ZIG_B_NEW_COUNT" "$RUST_B_NEW_COUNT" "1"
    
    # Verify CL is now 3
    local ZIG_B_NEW_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_B_NEW_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 2d: CL advanced to 3 after resurrection"
    check_parity "Post-resurrection CL" "$ZIG_B_NEW_CL" "$RUST_B_NEW_CL" "3"
    
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Update on Live Row via Column (CL verification)
# Python test: test_resurrection_of_live_thing_via_non_sentinel
# Scenario: c1 does INSERT->DELETE->INSERT (cl=3), c2 has INSERT (cl=1)
#           c2 receives only column update (not sentinel) from c1
#           CL should advance to 3, column clocks should roll back
# ══════════════════════════════════════════════════════════════════════════════
test_live_via_column() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test 3: Update on Live Row via Column"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario: Site A has INSERT->DELETE->INSERT (cl=3)"
    echo "          Site B has INSERT only (cl=1)"
    echo "          Site B receives column update (not sentinel) from Site A"
    echo "Expected: Row stays alive, CL advances to 3"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/live_column_zig_a.db"
    local DB_RUST_A="$TMPDIR/live_column_rust_a.db"
    local DB_ZIG_B="$TMPDIR/live_column_zig_b.db"
    local DB_RUST_B="$TMPDIR/live_column_rust_b.db"
    
    # Setup Site A: INSERT -> DELETE -> INSERT (cl=3)
    local SETUP_A="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
INSERT INTO foo VALUES (1, 1);
"
    
    # Setup Site B: Just INSERT (cl=1)
    local SETUP_B="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
"
    
    run_zig "$DB_ZIG_A" "$SETUP_A"
    run_rust "$DB_RUST_A" "$SETUP_A"
    run_zig "$DB_ZIG_B" "$SETUP_B"
    run_rust "$DB_RUST_B" "$SETUP_B"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        SKIP=$((SKIP + 5))
        return
    fi
    
    # Verify initial state
    local ZIG_B_INIT_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_INIT_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 3a: Verify Site B starts with cl=1"
    check_parity "Site B initial CL" "$ZIG_B_INIT_CL" "$RUST_B_INIT_CL" "1"
    
    # Merge only the column update (not sentinel) from Site A
    # col_version=1 for the value, cl=3 (from resurrection)
    local MERGE_COLUMN="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 1, 1, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 1);
"
    
    run_zig "$DB_ZIG_B" "$MERGE_COLUMN"
    run_rust "$DB_RUST_B" "$MERGE_COLUMN"
    
    # Verify row still exists
    local ZIG_B_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 3b: Row still exists after column merge"
    check_parity "Row count" "$ZIG_B_COUNT" "$RUST_B_COUNT" "1"
    
    # Verify CL advanced to 3 (sentinel should be created with cl=3)
    local ZIG_B_SENTINEL_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_B_SENTINEL_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 3c: Sentinel CL advanced to 3"
    check_parity "Sentinel CL after column merge" "$ZIG_B_SENTINEL_CL" "$RUST_B_SENTINEL_CL" "3"
    
    # Verify column CL is also 3
    local ZIG_B_COL_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_COL_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 3d: Column CL is 3"
    check_parity "Column CL after merge" "$ZIG_B_COL_CL" "$RUST_B_COL_CL" "3"
    
    # Verify column version is 1 (rolled back due to CL advance)
    local ZIG_B_COL_VER=$(run_zig "$DB_ZIG_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_COL_VER=$(run_rust "$DB_RUST_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 3e: Column version is 1"
    check_parity "Column version" "$ZIG_B_COL_VER" "$RUST_B_COL_VER" "1"
    
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: Resurrection of Dead Row via Column Update
# Python test: test_resurrection_of_dead_thing_via_non_sentinel
# Scenario: c1 does INSERT->DELETE->INSERT (cl=3), c2 has INSERT->DELETE (cl=2)
#           c2 receives only column update (not sentinel) from c1
#           Row should be resurrected, CL should advance to 3
# ══════════════════════════════════════════════════════════════════════════════
test_dead_via_column() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test 4: Resurrection of Dead Row via Column Update"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario: Site A has INSERT->DELETE->INSERT (cl=3)"
    echo "          Site B has INSERT->DELETE (cl=2, tombstoned)"
    echo "          Site B receives column update (not sentinel) from Site A"
    echo "Expected: Row resurrected, CL=3, column version rolled back"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/dead_column_zig_a.db"
    local DB_RUST_A="$TMPDIR/dead_column_rust_a.db"
    local DB_ZIG_B="$TMPDIR/dead_column_zig_b.db"
    local DB_RUST_B="$TMPDIR/dead_column_rust_b.db"
    
    # Setup Site A: INSERT -> DELETE -> INSERT (cl=3)
    local SETUP_A="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
INSERT INTO foo VALUES (1, 1);
"
    
    # Setup Site B: INSERT -> DELETE (cl=2, tombstoned)
    local SETUP_B="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
"
    
    run_zig "$DB_ZIG_A" "$SETUP_A"
    run_rust "$DB_RUST_A" "$SETUP_A"
    run_zig "$DB_ZIG_B" "$SETUP_B"
    run_rust "$DB_RUST_B" "$SETUP_B"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        SKIP=$((SKIP + 5))
        return
    fi
    
    # Verify Site B is tombstoned
    local ZIG_B_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 4a: Verify Site B row is deleted before merge"
    check_parity "Site B row count" "$ZIG_B_COUNT" "$RUST_B_COUNT" "0"
    
    # Merge only the column update (not sentinel) from Site A
    local MERGE_COLUMN="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 1, 1, 99, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 1);
"
    
    run_zig "$DB_ZIG_B" "$MERGE_COLUMN"
    run_rust "$DB_RUST_B" "$MERGE_COLUMN"
    
    # Verify row is resurrected
    local ZIG_B_NEW_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_NEW_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 4b: Row resurrected after column merge"
    check_parity "Resurrected row count" "$ZIG_B_NEW_COUNT" "$RUST_B_NEW_COUNT" "1"
    
    # Verify CL is 3
    local ZIG_B_SENTINEL_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_B_SENTINEL_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 4c: Sentinel CL is 3 after resurrection"
    check_parity "Sentinel CL" "$ZIG_B_SENTINEL_CL" "$RUST_B_SENTINEL_CL" "3"
    
    # Verify column CL is 3
    local ZIG_B_COL_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_COL_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 4d: Column CL is 3"
    check_parity "Column CL" "$ZIG_B_COL_CL" "$RUST_B_COL_CL" "3"
    
    # Verify column version is 1 (rolled back due to CL advance from cl=2 to cl=3)
    local ZIG_B_COL_VER=$(run_zig "$DB_ZIG_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_COL_VER=$(run_rust "$DB_RUST_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 4e: Column version is 1 (rolled back)"
    check_parity "Column version" "$ZIG_B_COL_VER" "$RUST_B_COL_VER" "1"
    
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 5: Out-of-Order Merge
# Python test: test_pr_299_scenario (partial), test_discord_report_corrosion
# Scenario: Changes arrive in wrong order (e.g., delete arrives after resurrect)
#           Final state should be determined by CL, not arrival order
# ══════════════════════════════════════════════════════════════════════════════
test_out_of_order() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test 5: Out-of-Order Merge"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario: Site A does INSERT (v1) -> DELETE (v2) -> INSERT (v3, cl=3)"
    echo "          Site B has INSERT with high col_versions (cl=1)"
    echo "          Site B receives v3 first (resurrect), then v2 (delete)"
    echo "Expected: Row is alive (cl=3 > cl=2), values from v3"
    echo ""
    
    local DB_ZIG_A="$TMPDIR/ooo_zig_a.db"
    local DB_RUST_A="$TMPDIR/ooo_rust_a.db"
    local DB_ZIG_B="$TMPDIR/ooo_zig_b.db"
    local DB_RUST_B="$TMPDIR/ooo_rust_b.db"
    
    # Setup Site A: INSERT -> DELETE -> INSERT (resurrect)
    local SETUP_A="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
DELETE FROM foo;
INSERT INTO foo VALUES (1, 1);
"
    
    # Setup Site B: INSERT with multiple updates (high col_versions, but cl=1)
    local SETUP_B="
CREATE TABLE foo (a INTEGER PRIMARY KEY NOT NULL, b INTEGER);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 1);
UPDATE foo SET b = 2 WHERE a = 1;
UPDATE foo SET b = 3 WHERE a = 1;
UPDATE foo SET b = 4 WHERE a = 1;
"
    
    run_zig "$DB_ZIG_A" "$SETUP_A"
    run_rust "$DB_RUST_A" "$SETUP_A"
    run_zig "$DB_ZIG_B" "$SETUP_B"
    run_rust "$DB_RUST_B" "$SETUP_B"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        SKIP=$((SKIP + 6))
        return
    fi
    
    # Verify Site B has high col_version (4 from 3 updates) but low cl (1)
    local ZIG_B_INIT_COL_VER=$(run_zig "$DB_ZIG_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_INIT_COL_VER=$(run_rust "$DB_RUST_B" "SELECT col_version FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 5a: Verify Site B has col_version=4 (high)"
    check_parity "Initial col_version" "$ZIG_B_INIT_COL_VER" "$RUST_B_INIT_COL_VER" "4"
    
    local ZIG_B_INIT_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    local RUST_B_INIT_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='b' LIMIT 1;")
    
    echo "Test 5b: Verify Site B has cl=1 (low)"
    check_parity "Initial CL" "$ZIG_B_INIT_CL" "$RUST_B_INIT_CL" "1"
    
    # First: Merge the resurrection (v3, cl=3) - skipping v2 (delete)
    # This simulates receiving changes out of order
    local MERGE_RESURRECT="
BEGIN;
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 100, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'b', 1, 1, 100, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 3, 1);
COMMIT;
"
    
    run_zig "$DB_ZIG_B" "$MERGE_RESURRECT"
    run_rust "$DB_RUST_B" "$MERGE_RESURRECT"
    
    # Verify state after resurrect merge
    local ZIG_B_MID_VAL=$(run_zig "$DB_ZIG_B" "SELECT b FROM foo WHERE a=1;")
    local RUST_B_MID_VAL=$(run_rust "$DB_RUST_B" "SELECT b FROM foo WHERE a=1;")
    
    echo "Test 5c: Value is 1 after resurrect merge (cl=3 wins over cl=1)"
    check_parity "Value after resurrect" "$ZIG_B_MID_VAL" "$RUST_B_MID_VAL" "1"
    
    # Now: Merge the delete (v2, cl=2) - arriving AFTER resurrect
    local MERGE_DELETE="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 2, 50, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01', 2, 0);
"
    
    run_zig "$DB_ZIG_B" "$MERGE_DELETE"
    run_rust "$DB_RUST_B" "$MERGE_DELETE"
    
    # Verify row is STILL alive (cl=3 beats cl=2 even though delete arrived later)
    local ZIG_B_FINAL_COUNT=$(run_zig "$DB_ZIG_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    local RUST_B_FINAL_COUNT=$(run_rust "$DB_RUST_B" "SELECT COUNT(*) FROM foo WHERE a=1;")
    
    echo "Test 5d: Row still alive after late delete (cl=3 > cl=2)"
    check_parity "Final row count" "$ZIG_B_FINAL_COUNT" "$RUST_B_FINAL_COUNT" "1"
    
    # Verify CL is still 3
    local ZIG_B_FINAL_CL=$(run_zig "$DB_ZIG_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    local RUST_B_FINAL_CL=$(run_rust "$DB_RUST_B" "SELECT cl FROM crsql_changes WHERE cid='-1' LIMIT 1;")
    
    echo "Test 5e: CL unchanged at 3"
    check_parity "Final CL" "$ZIG_B_FINAL_CL" "$RUST_B_FINAL_CL" "3"
    
    # Verify value is still from resurrection
    local ZIG_B_FINAL_VAL=$(run_zig "$DB_ZIG_B" "SELECT b FROM foo WHERE a=1;")
    local RUST_B_FINAL_VAL=$(run_rust "$DB_RUST_B" "SELECT b FROM foo WHERE a=1;")
    
    echo "Test 5f: Value still 1 (resurrection values preserved)"
    check_parity "Final value" "$ZIG_B_FINAL_VAL" "$RUST_B_FINAL_VAL" "1"
    
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ══════════════════════════════════════════════════════════════════════════════

test_live_via_sentinel
test_dead_via_sentinel
test_live_via_column
test_dead_via_column
test_out_of_order

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Resurrection Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""

if [[ $FAIL -eq 0 ]]; then
    if [[ $SKIP -gt 0 ]]; then
        echo "Some tests skipped (functions not implemented)"
        exit 0
    else
        echo "All resurrection parity tests PASSED"
        echo ""
        echo "Verified:"
        echo "  - Live row + sentinel: CL advances, column clocks zeroed"
        echo "  - Dead row + sentinel: Row resurrected, CL advances"
        echo "  - Live row + column: CL advances from column update"
        echo "  - Dead row + column: Row resurrected via column update"
        echo "  - Out-of-order: Higher CL wins regardless of arrival order"
        exit 0
    fi
else
    echo "RESURRECTION PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAIL test(s)."
    echo "This may cause sync incompatibility between implementations."
    exit 1
fi
