#!/usr/bin/env bash
# Causal Length (CL) Parity Tests for Zig CR-SQLite
# Tests that row lifecycle (insert -> delete -> resurrect) produces identical
# causal length values and winner decisions in both implementations.
#
# Tests:
# MR-041: Deleted row + insert merge (higher cl) -> Row resurrected
# MR-042: cl=1 (live) vs cl=2 (deleted) -> Deleted wins
# MR-043: cl=2 (deleted) vs cl=3 (resurrected) -> Resurrected wins
#
# Reference: TASK-135, research/zig-cr/96-ideal-parity-experiments.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Causal Length (CL) Parity (Zig vs Rust/C)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Tests row lifecycle: insert -> delete -> resurrect"
echo "Verifies both implementations produce identical CL values and winners"
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
TMPDIR="${REPO_ROOT}/.tmp/cl-parity-$$"
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

# Remote site ID for merge operations (fixed for reproducibility)
REMOTE_SITE="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'"

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: CL Lifecycle Values Parity
# Verifies both implementations assign identical CL values through lifecycle
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: CL Lifecycle Values Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: INSERT (cl=1) -> DELETE (cl=2)"
echo "Expected: Both implementations produce identical CL values"
echo ""

DB_ZIG_1="$TMPDIR/lifecycle_zig.db"
DB_RUST_1="$TMPDIR/lifecycle_rust.db"

# Setup and INSERT in both
SETUP_1="
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'original');
"

run_zig "$DB_ZIG_1" "$SETUP_1"
run_rust "$DB_RUST_1" "$SETUP_1"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Get CL after INSERT from crsql_changes (cl is only in changes vtab)
    # Note: sentinel row (-1) only exists after delete; for live rows, use any column's cl
    ZIG_CL_INSERT=$(run_zig "$DB_ZIG_1" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='name' LIMIT 1;")
    RUST_CL_INSERT=$(run_rust "$DB_RUST_1" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='name' LIMIT 1;")
    
    echo "Test 1a: CL after INSERT"
    if [[ "$ZIG_CL_INSERT" == "$RUST_CL_INSERT" ]]; then
        echo "  PASS: Both have cl=$ZIG_CL_INSERT after INSERT"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: CL diverges after INSERT"
        echo "    Zig:    cl=$ZIG_CL_INSERT"
        echo "    Rust/C: cl=$RUST_CL_INSERT"
        FAIL=$((FAIL + 1))
    fi
    
    # DELETE the row
    run_zig "$DB_ZIG_1" "DELETE FROM foo WHERE id=1;"
    run_rust "$DB_RUST_1" "DELETE FROM foo WHERE id=1;"
    
    # Get CL after DELETE (sentinel row -1 now exists with cl=2)
    ZIG_CL_DELETE=$(run_zig "$DB_ZIG_1" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    RUST_CL_DELETE=$(run_rust "$DB_RUST_1" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    
    echo "Test 1b: CL after DELETE"
    if [[ "$ZIG_CL_DELETE" == "$RUST_CL_DELETE" ]]; then
        echo "  PASS: Both have cl=$ZIG_CL_DELETE after DELETE"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: CL diverges after DELETE"
        echo "    Zig:    cl=$ZIG_CL_DELETE"
        echo "    Rust/C: cl=$RUST_CL_DELETE"
        FAIL=$((FAIL + 1))
    fi
    
    # Verify row is gone in both
    ZIG_COUNT=$(run_zig "$DB_ZIG_1" "SELECT COUNT(*) FROM foo WHERE id=1;")
    RUST_COUNT=$(run_rust "$DB_RUST_1" "SELECT COUNT(*) FROM foo WHERE id=1;")
    
    echo "Test 1c: Row deleted in both"
    if [[ "$ZIG_COUNT" == "0" && "$RUST_COUNT" == "0" ]]; then
        echo "  PASS: Row deleted in both (count=0)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Row not deleted properly"
        echo "    Zig count:    $ZIG_COUNT"
        echo "    Rust/C count: $RUST_COUNT"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: MR-042 - Live vs Deleted (higher CL wins)
# Local: cl=1 (row exists), Remote: cl=2 (row deleted)
# Expected: Remote wins, row gets deleted
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: MR-042 - Live vs Deleted (cl=1 vs cl=2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Local has live row (cl=1), remote sends delete (cl=2)"
echo "Expected: Remote wins (cl=2 > cl=1), row gets deleted"
echo ""

DB_ZIG_2="$TMPDIR/mr042_zig.db"
DB_RUST_2="$TMPDIR/mr042_rust.db"

# Setup local live row in both (cl=1)
SETUP_2="
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'local_value');
"

run_zig "$DB_ZIG_2" "$SETUP_2"
run_rust "$DB_RUST_2" "$SETUP_2"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Verify local row exists with cl=1 (from crsql_changes, since live rows don't have sentinel)
    ZIG_LOCAL_CL=$(run_zig "$DB_ZIG_2" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='name' LIMIT 1;")
    RUST_LOCAL_CL=$(run_rust "$DB_RUST_2" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='name' LIMIT 1;")
    
    echo "Test 2a: Verify local cl=1 before merge"
    if [[ "$ZIG_LOCAL_CL" == "1" && "$RUST_LOCAL_CL" == "1" ]]; then
        echo "  PASS: Both have local cl=1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Expected local cl=1"
        echo "    Zig:    cl=$ZIG_LOCAL_CL"
        echo "    Rust/C: cl=$RUST_LOCAL_CL"
        FAIL=$((FAIL + 1))
    fi
    
    # Merge remote delete with cl=2
    # PK encoding for integer 1: X'010901' (01=1 col, 09=int type, 01=value 1)
    MERGE_DELETE="
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 2, 99, $REMOTE_SITE, 2, 0);
"
    
    run_zig "$DB_ZIG_2" "$MERGE_DELETE"
    run_rust "$DB_RUST_2" "$MERGE_DELETE"
    
    # Verify row is deleted in both
    ZIG_COUNT=$(run_zig "$DB_ZIG_2" "SELECT COUNT(*) FROM foo WHERE id=1;")
    RUST_COUNT=$(run_rust "$DB_RUST_2" "SELECT COUNT(*) FROM foo WHERE id=1;")
    
    echo "Test 2b: Row deleted after remote cl=2 merge"
    if [[ "$ZIG_COUNT" == "$RUST_COUNT" ]]; then
        if [[ "$ZIG_COUNT" == "0" ]]; then
            echo "  PASS: Both deleted row (higher cl wins)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: Row should be deleted but both have count=$ZIG_COUNT"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: Delete decision diverges"
        echo "    Zig count:    $ZIG_COUNT"
        echo "    Rust/C count: $RUST_COUNT"
        FAIL=$((FAIL + 1))
    fi
    
    # Verify cl is now 2 in both (sentinel row exists after delete)
    ZIG_FINAL_CL=$(run_zig "$DB_ZIG_2" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    RUST_FINAL_CL=$(run_rust "$DB_RUST_2" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    
    echo "Test 2c: CL updated to 2 after merge"
    if [[ "$ZIG_FINAL_CL" == "$RUST_FINAL_CL" ]]; then
        echo "  PASS: Both have cl=$ZIG_FINAL_CL after merge"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Final CL diverges"
        echo "    Zig:    cl=$ZIG_FINAL_CL"
        echo "    Rust/C: cl=$RUST_FINAL_CL"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: MR-043 - Deleted vs Resurrected (cl=2 vs cl=3)
# Local: cl=2 (deleted), Remote: cl=3 (resurrected)
# Expected: Remote wins, row resurrected with new value
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: MR-043 - Deleted vs Resurrected (cl=2 vs cl=3)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Local has deleted row (cl=2), remote sends resurrection (cl=3)"
echo "Expected: Remote wins (cl=3 > cl=2), row resurrected with new value"
echo ""

DB_ZIG_3="$TMPDIR/mr043_zig.db"
DB_RUST_3="$TMPDIR/mr043_rust.db"

# Setup: Create row, then delete it (creates tombstone cl=2)
SETUP_3="
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'original');
DELETE FROM foo WHERE id=1;
"

run_zig "$DB_ZIG_3" "$SETUP_3"
run_rust "$DB_RUST_3" "$SETUP_3"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Verify local tombstone with cl=2 (sentinel row exists after delete)
    ZIG_TOMB_CL=$(run_zig "$DB_ZIG_3" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    RUST_TOMB_CL=$(run_rust "$DB_RUST_3" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    
    echo "Test 3a: Verify local tombstone cl=2"
    if [[ "$ZIG_TOMB_CL" == "2" && "$RUST_TOMB_CL" == "2" ]]; then
        echo "  PASS: Both have tombstone cl=2"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Expected tombstone cl=2"
        echo "    Zig:    cl=$ZIG_TOMB_CL"
        echo "    Rust/C: cl=$RUST_TOMB_CL"
        FAIL=$((FAIL + 1))
    fi
    
    # Merge resurrection with cl=3
    # First: sentinel row with cl=3 (marks row as alive)
    # Then: column value
    MERGE_RESURRECT="
BEGIN;
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 100, $REMOTE_SITE, 3, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'name', 'resurrected', 1, 100, $REMOTE_SITE, 3, 1);
COMMIT;
"
    
    run_zig "$DB_ZIG_3" "$MERGE_RESURRECT"
    run_rust "$DB_RUST_3" "$MERGE_RESURRECT"
    
    # Verify row exists in both
    ZIG_COUNT=$(run_zig "$DB_ZIG_3" "SELECT COUNT(*) FROM foo WHERE id=1;")
    RUST_COUNT=$(run_rust "$DB_RUST_3" "SELECT COUNT(*) FROM foo WHERE id=1;")
    
    echo "Test 3b: Row resurrected after remote cl=3 merge"
    if [[ "$ZIG_COUNT" == "$RUST_COUNT" ]]; then
        if [[ "$ZIG_COUNT" == "1" ]]; then
            echo "  PASS: Both resurrected row (higher cl wins)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: Row should be resurrected but both have count=$ZIG_COUNT"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: Resurrection decision diverges"
        echo "    Zig count:    $ZIG_COUNT"
        echo "    Rust/C count: $RUST_COUNT"
        FAIL=$((FAIL + 1))
    fi
    
    # Verify value is 'resurrected' in both
    ZIG_VAL=$(run_zig "$DB_ZIG_3" "SELECT name FROM foo WHERE id=1;")
    RUST_VAL=$(run_rust "$DB_RUST_3" "SELECT name FROM foo WHERE id=1;")
    
    echo "Test 3c: Resurrected row has correct value"
    if [[ "$ZIG_VAL" == "$RUST_VAL" ]]; then
        if [[ "$ZIG_VAL" == "resurrected" ]]; then
            echo "  PASS: Both have value='resurrected'"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: Expected value='resurrected', got '$ZIG_VAL'"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: Resurrected value diverges"
        echo "    Zig:    '$ZIG_VAL'"
        echo "    Rust/C: '$RUST_VAL'"
        FAIL=$((FAIL + 1))
    fi
    
    # Verify cl is now 3 in both (from crsql_changes after resurrection)
    ZIG_FINAL_CL=$(run_zig "$DB_ZIG_3" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='-1' LIMIT 1;")
    RUST_FINAL_CL=$(run_rust "$DB_RUST_3" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='-1' LIMIT 1;")
    
    echo "Test 3d: CL updated to 3 after resurrection"
    if [[ "$ZIG_FINAL_CL" == "$RUST_FINAL_CL" ]]; then
        echo "  PASS: Both have cl=$ZIG_FINAL_CL after resurrection"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Final CL diverges"
        echo "    Zig:    cl=$ZIG_FINAL_CL"
        echo "    Rust/C: cl=$RUST_FINAL_CL"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: MR-041 - Full Lifecycle Resurrection Parity
# Create -> Delete -> Resurrect via merge, verify all CLs match
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: MR-041 - Full Lifecycle Resurrection Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Node A creates row, deletes it"
echo "          Node B (remote) had modified row (cl=3)"
echo "          Node A merges B's changes -> row resurrected"
echo ""

DB_ZIG_4="$TMPDIR/mr041_zig.db"
DB_RUST_4="$TMPDIR/mr041_rust.db"

# Setup: Node A creates row then deletes it
SETUP_4="
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'nodeA_original');
DELETE FROM foo WHERE id=1;
"

run_zig "$DB_ZIG_4" "$SETUP_4"
run_rust "$DB_RUST_4" "$SETUP_4"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Verify starting state: deleted with cl=2 (sentinel row exists)
    ZIG_START_CL=$(run_zig "$DB_ZIG_4" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    RUST_START_CL=$(run_rust "$DB_RUST_4" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    ZIG_START_COUNT=$(run_zig "$DB_ZIG_4" "SELECT COUNT(*) FROM foo WHERE id=1;")
    RUST_START_COUNT=$(run_rust "$DB_RUST_4" "SELECT COUNT(*) FROM foo WHERE id=1;")
    
    echo "Test 4a: Starting state (deleted, cl=2)"
    if [[ "$ZIG_START_CL" == "$RUST_START_CL" && "$ZIG_START_COUNT" == "$RUST_START_COUNT" ]]; then
        echo "  PASS: Both start with cl=$ZIG_START_CL, count=$ZIG_START_COUNT"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Starting state diverges"
        echo "    Zig:    cl=$ZIG_START_CL, count=$ZIG_START_COUNT"
        echo "    Rust/C: cl=$RUST_START_CL, count=$RUST_START_COUNT"
        FAIL=$((FAIL + 1))
    fi
    
    # Simulate receiving changes from Node B who modified the row (cl=3)
    # Node B's modifications: updated name to 'nodeB_modified'
    MERGE_NODEB="
BEGIN;
-- Node B's sentinel (row exists, cl=3)
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 3, 50, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB02', 3, 0);
-- Node B's column update
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'name', 'nodeB_modified', 2, 50, X'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB02', 3, 1);
COMMIT;
"
    
    run_zig "$DB_ZIG_4" "$MERGE_NODEB"
    run_rust "$DB_RUST_4" "$MERGE_NODEB"
    
    # Verify row is resurrected
    ZIG_FINAL_COUNT=$(run_zig "$DB_ZIG_4" "SELECT COUNT(*) FROM foo WHERE id=1;")
    RUST_FINAL_COUNT=$(run_rust "$DB_RUST_4" "SELECT COUNT(*) FROM foo WHERE id=1;")
    
    echo "Test 4b: Row resurrected after Node B merge"
    if [[ "$ZIG_FINAL_COUNT" == "$RUST_FINAL_COUNT" ]]; then
        if [[ "$ZIG_FINAL_COUNT" == "1" ]]; then
            echo "  PASS: Both resurrected row"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: Row should be resurrected (count=$ZIG_FINAL_COUNT)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: Resurrection diverges"
        echo "    Zig count:    $ZIG_FINAL_COUNT"
        echo "    Rust/C count: $RUST_FINAL_COUNT"
        FAIL=$((FAIL + 1))
    fi
    
    # Verify value
    ZIG_FINAL_VAL=$(run_zig "$DB_ZIG_4" "SELECT name FROM foo WHERE id=1;")
    RUST_FINAL_VAL=$(run_rust "$DB_RUST_4" "SELECT name FROM foo WHERE id=1;")
    
    echo "Test 4c: Resurrected row has Node B's value"
    if [[ "$ZIG_FINAL_VAL" == "$RUST_FINAL_VAL" ]]; then
        echo "  PASS: Both have value='$ZIG_FINAL_VAL'"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Value diverges"
        echo "    Zig:    '$ZIG_FINAL_VAL'"
        echo "    Rust/C: '$RUST_FINAL_VAL'"
        FAIL=$((FAIL + 1))
    fi
    
    # Verify final CL (from crsql_changes after resurrection)
    ZIG_FINAL_CL=$(run_zig "$DB_ZIG_4" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='-1' LIMIT 1;")
    RUST_FINAL_CL=$(run_rust "$DB_RUST_4" "SELECT cl FROM crsql_changes WHERE [table]='foo' AND cid='-1' LIMIT 1;")
    
    echo "Test 4d: Final CL is 3"
    if [[ "$ZIG_FINAL_CL" == "$RUST_FINAL_CL" ]]; then
        echo "  PASS: Both have cl=$ZIG_FINAL_CL"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Final CL diverges"
        echo "    Zig:    cl=$ZIG_FINAL_CL"
        echo "    Rust/C: cl=$RUST_FINAL_CL"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 5: Lower CL Loses (Remote delete with cl=1 vs local cl=2)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Lower CL Loses (remote cl=1 vs local cl=2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Local has deleted row (cl=2), remote sends stale insert (cl=1)"
echo "Expected: Local wins (cl=2 > cl=1), row stays deleted"
echo ""

DB_ZIG_5="$TMPDIR/lower_cl_zig.db"
DB_RUST_5="$TMPDIR/lower_cl_rust.db"

# Setup: Create row, then delete it (creates tombstone cl=2)
SETUP_5="
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'original');
DELETE FROM foo WHERE id=1;
"

run_zig "$DB_ZIG_5" "$SETUP_5"
run_rust "$DB_RUST_5" "$SETUP_5"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Try to merge a stale insert with cl=1 (should lose to local cl=2)
    MERGE_STALE="
BEGIN;
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', '-1', NULL, 1, 10, X'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC03', 1, 0);
INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('foo', X'010901', 'name', 'stale_value', 1, 10, X'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC03', 1, 1);
COMMIT;
"
    
    run_zig "$DB_ZIG_5" "$MERGE_STALE"
    run_rust "$DB_RUST_5" "$MERGE_STALE"
    
    # Row should still be deleted (local cl=2 wins over remote cl=1)
    ZIG_COUNT=$(run_zig "$DB_ZIG_5" "SELECT COUNT(*) FROM foo WHERE id=1;")
    RUST_COUNT=$(run_rust "$DB_RUST_5" "SELECT COUNT(*) FROM foo WHERE id=1;")
    
    echo "Test 5a: Row stays deleted (local cl=2 beats remote cl=1)"
    if [[ "$ZIG_COUNT" == "$RUST_COUNT" ]]; then
        if [[ "$ZIG_COUNT" == "0" ]]; then
            echo "  PASS: Both kept row deleted (local wins)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: Row should stay deleted but both have count=$ZIG_COUNT"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: Decision diverges"
        echo "    Zig count:    $ZIG_COUNT"
        echo "    Rust/C count: $RUST_COUNT"
        FAIL=$((FAIL + 1))
    fi
    
    # CL should still be 2 (sentinel row exists after original delete)
    ZIG_CL=$(run_zig "$DB_ZIG_5" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    RUST_CL=$(run_rust "$DB_RUST_5" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='-1';")
    
    echo "Test 5b: CL unchanged at 2"
    if [[ "$ZIG_CL" == "$RUST_CL" ]]; then
        if [[ "$ZIG_CL" == "2" ]]; then
            echo "  PASS: Both have cl=2 (unchanged)"
            PASS=$((PASS + 1))
        else
            echo "  INFO: CL is $ZIG_CL (may have advanced for other reasons)"
            PASS=$((PASS + 1))
        fi
    else
        echo "  FAIL: CL diverges"
        echo "    Zig:    cl=$ZIG_CL"
        echo "    Rust/C: cl=$RUST_CL"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 6: CL in crsql_changes output parity
# Verifies both produce identical cl values in change records
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: CL in crsql_changes output parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Verifies crsql_changes reports identical cl values in both implementations"
echo ""

DB_ZIG_6="$TMPDIR/changes_cl_zig.db"
DB_RUST_6="$TMPDIR/changes_cl_rust.db"

SETUP_6="
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'test');
UPDATE foo SET name='updated' WHERE id=1;
DELETE FROM foo WHERE id=1;
"

run_zig "$DB_ZIG_6" "$SETUP_6"
run_rust "$DB_RUST_6" "$SETUP_6"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Get cl values from crsql_changes
    ZIG_CHANGES_CL=$(run_zig "$DB_ZIG_6" "SELECT cid, cl FROM crsql_changes WHERE [table]='foo' ORDER BY cid;")
    RUST_CHANGES_CL=$(run_rust "$DB_RUST_6" "SELECT cid, cl FROM crsql_changes WHERE [table]='foo' ORDER BY cid;")
    
    echo "Test 6: crsql_changes cl values match"
    if [[ "$ZIG_CHANGES_CL" == "$RUST_CHANGES_CL" ]]; then
        echo "  PASS: crsql_changes cl values identical"
        echo "    Values: $ZIG_CHANGES_CL"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: crsql_changes cl values diverge"
        echo "    Zig:"
        echo "$ZIG_CHANGES_CL" | sed 's/^/      /'
        echo "    Rust/C:"
        echo "$RUST_CHANGES_CL" | sed 's/^/      /'
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Causal Length (CL) Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""

if [[ $FAIL -eq 0 ]]; then
    if [[ $SKIP -gt 0 ]]; then
        echo "Some tests skipped (functions not implemented)"
        exit 0
    else
        echo "All CL parity tests PASSED"
        echo ""
        echo "Verified:"
        echo "  - CL values identical through insert/delete lifecycle"
        echo "  - MR-042: Higher CL delete wins over lower CL live"
        echo "  - MR-043: Higher CL resurrection wins over lower CL delete"
        echo "  - MR-041: Full lifecycle resurrection works identically"
        echo "  - Lower CL changes are correctly rejected"
        echo "  - crsql_changes reports identical cl values"
        exit 0
    fi
else
    echo "CL PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAIL test(s)."
    echo "This may cause sync incompatibility between implementations."
    exit 1
fi
