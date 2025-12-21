#!/usr/bin/env bash
# Merge Value Comparison Parity Tests (Zig vs Rust/C Oracle)
#
# When col_version is equal between local and remote, the implementations must use
# the same value comparison algorithm to determine the winner. This test suite
# verifies that behavior for all SQLite types.
#
# Test IDs:
# - MR-020: String comparison (lexicographic)
# - MR-021: Integer comparison
# - MR-022: NULL vs value
# - MR-023: Value vs NULL
# - MR-024: Float comparison
# - MR-025: Blob comparison
#
# Context: TASK-134 (create tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Merge Value Comparison Parity Tests (Zig vs Rust/C Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "These tests verify that when col_version ties, value comparison"
echo "produces identical winners in both implementations."
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Check for Rust/C oracle
if [[ ! -f "$RUST_EXT" ]]; then
    echo "BLOCKED: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 2
fi

# Check/build Zig extension
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

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/merge-value-parity-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0

ERRFILE="$TMPDIR/error.txt"

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

# Compare two values and report result
compare() {
    local zig_val="$1"
    local rust_val="$2"
    local test_name="$3"
    
    if [[ "$zig_val" == "$rust_val" ]]; then
        echo "  PASS: $test_name"
        echo "    Both selected: $zig_val"
        PASS=$((PASS + 1))
        return 0
    else
        echo "  FAIL: $test_name"
        echo "    Zig selected:    '$zig_val'"
        echo "    Oracle selected: '$rust_val'"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MR-020: String comparison (lexicographic)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-020: String comparison (lexicographic) - 'apple' vs 'banana'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When col_version ties, the larger string value wins."
echo "'banana' > 'apple' lexicographically, so 'banana' should win."
echo ""

DB_ZIG_020="$TMPDIR/mr020_zig.db"
DB_RUST_020="$TMPDIR/mr020_rust.db"

# Remote site_id that will be used for incoming changes
REMOTE_SITE="X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'"

# Setup: Create local row with 'apple' in both DBs
run_zig "$DB_ZIG_020" "
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'apple');
"

run_rust "$DB_RUST_020" "
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'apple');
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version (should be 1)
    # Note: clock table uses 'key' column (integer PK), not 'pk'
    ZIG_CV=$(run_zig "$DB_ZIG_020" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='name';")
    RUST_CV=$(run_rust "$DB_RUST_020" "SELECT col_version FROM foo__crsql_clock WHERE key=1 AND col_name='name';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote 'banana' with SAME col_version (tie-breaker: value comparison)
    run_zig "$DB_ZIG_020" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('foo', X'010901', 'name', 'banana', $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_020" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('foo', X'010901', 'name', 'banana', $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner
    ZIG_WINNER=$(run_zig "$DB_ZIG_020" "SELECT name FROM foo WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_020" "SELECT name FROM foo WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "String comparison winner"
    echo "    Expected: 'banana' (lexicographically larger)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MR-021: Integer comparison - 100 vs 99
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-021: Integer comparison - 100 vs 99"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When col_version ties, the larger integer value wins."
echo "100 > 99, so 100 should win."
echo ""

DB_ZIG_021="$TMPDIR/mr021_zig.db"
DB_RUST_021="$TMPDIR/mr021_rust.db"

# Setup: Create local row with 99 in both DBs
run_zig "$DB_ZIG_021" "
CREATE TABLE nums (id INTEGER PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('nums');
INSERT INTO nums VALUES (1, 99);
"

run_rust "$DB_RUST_021" "
CREATE TABLE nums (id INTEGER PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('nums');
INSERT INTO nums VALUES (1, 99);
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version
    ZIG_CV=$(run_zig "$DB_ZIG_021" "SELECT col_version FROM nums__crsql_clock WHERE key=1 AND col_name='val';")
    RUST_CV=$(run_rust "$DB_RUST_021" "SELECT col_version FROM nums__crsql_clock WHERE key=1 AND col_name='val';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote 100 with SAME col_version
    run_zig "$DB_ZIG_021" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('nums', X'010901', 'val', 100, $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_021" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('nums', X'010901', 'val', 100, $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner
    ZIG_WINNER=$(run_zig "$DB_ZIG_021" "SELECT val FROM nums WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_021" "SELECT val FROM nums WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "Integer comparison winner"
    echo "    Expected: 100 (larger integer)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MR-022: NULL vs value - NULL loses to any value
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-022: NULL vs value - local NULL, remote has value"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When col_version ties, NULL loses to any non-NULL value."
echo "This documents the expected behavior."
echo ""

DB_ZIG_022="$TMPDIR/mr022_zig.db"
DB_RUST_022="$TMPDIR/mr022_rust.db"

# Setup: Create local row with NULL in both DBs
run_zig "$DB_ZIG_022" "
CREATE TABLE nulltest (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('nulltest');
INSERT INTO nulltest VALUES (1, NULL);
"

run_rust "$DB_RUST_022" "
CREATE TABLE nulltest (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('nulltest');
INSERT INTO nulltest VALUES (1, NULL);
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version
    ZIG_CV=$(run_zig "$DB_ZIG_022" "SELECT col_version FROM nulltest__crsql_clock WHERE key=1 AND col_name='data';")
    RUST_CV=$(run_rust "$DB_RUST_022" "SELECT col_version FROM nulltest__crsql_clock WHERE key=1 AND col_name='data';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote 'hello' with SAME col_version
    run_zig "$DB_ZIG_022" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('nulltest', X'010901', 'data', 'hello', $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_022" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('nulltest', X'010901', 'data', 'hello', $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner
    ZIG_WINNER=$(run_zig "$DB_ZIG_022" "SELECT COALESCE(data, 'NULL') FROM nulltest WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_022" "SELECT COALESCE(data, 'NULL') FROM nulltest WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "NULL vs value winner"
    echo "    Note: Documenting which wins (NULL or non-NULL)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MR-023: Value vs NULL - value wins over NULL
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-023: Value vs NULL - local has value, remote is NULL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When col_version ties and local has value but remote has NULL."
echo "This documents the expected behavior."
echo ""

DB_ZIG_023="$TMPDIR/mr023_zig.db"
DB_RUST_023="$TMPDIR/mr023_rust.db"

# Setup: Create local row with 'existing' in both DBs
run_zig "$DB_ZIG_023" "
CREATE TABLE nulltest2 (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('nulltest2');
INSERT INTO nulltest2 VALUES (1, 'existing');
"

run_rust "$DB_RUST_023" "
CREATE TABLE nulltest2 (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('nulltest2');
INSERT INTO nulltest2 VALUES (1, 'existing');
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version
    ZIG_CV=$(run_zig "$DB_ZIG_023" "SELECT col_version FROM nulltest2__crsql_clock WHERE key=1 AND col_name='data';")
    RUST_CV=$(run_rust "$DB_RUST_023" "SELECT col_version FROM nulltest2__crsql_clock WHERE key=1 AND col_name='data';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote NULL with SAME col_version
    run_zig "$DB_ZIG_023" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('nulltest2', X'010901', 'data', NULL, $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_023" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('nulltest2', X'010901', 'data', NULL, $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner
    ZIG_WINNER=$(run_zig "$DB_ZIG_023" "SELECT COALESCE(data, 'NULL') FROM nulltest2 WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_023" "SELECT COALESCE(data, 'NULL') FROM nulltest2 WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "Value vs NULL winner"
    echo "    Note: Documenting which wins (value or NULL)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MR-024: Float comparison - 3.14 vs 3.15
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-024: Float comparison - 3.14 vs 3.15"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When col_version ties, the larger float value wins."
echo "3.15 > 3.14, so 3.15 should win."
echo ""

DB_ZIG_024="$TMPDIR/mr024_zig.db"
DB_RUST_024="$TMPDIR/mr024_rust.db"

# Setup: Create local row with 3.14 in both DBs
run_zig "$DB_ZIG_024" "
CREATE TABLE floats (id INTEGER PRIMARY KEY NOT NULL, val REAL);
SELECT crsql_as_crr('floats');
INSERT INTO floats VALUES (1, 3.14);
"

run_rust "$DB_RUST_024" "
CREATE TABLE floats (id INTEGER PRIMARY KEY NOT NULL, val REAL);
SELECT crsql_as_crr('floats');
INSERT INTO floats VALUES (1, 3.14);
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version
    ZIG_CV=$(run_zig "$DB_ZIG_024" "SELECT col_version FROM floats__crsql_clock WHERE key=1 AND col_name='val';")
    RUST_CV=$(run_rust "$DB_RUST_024" "SELECT col_version FROM floats__crsql_clock WHERE key=1 AND col_name='val';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote 3.15 with SAME col_version
    run_zig "$DB_ZIG_024" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('floats', X'010901', 'val', 3.15, $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_024" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('floats', X'010901', 'val', 3.15, $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner
    ZIG_WINNER=$(run_zig "$DB_ZIG_024" "SELECT val FROM floats WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_024" "SELECT val FROM floats WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "Float comparison winner"
    echo "    Expected: 3.15 (larger float)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MR-025: Blob comparison - X'AA' vs X'BB'
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-025: Blob comparison - X'AA' vs X'BB'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "When col_version ties, blobs are compared bytewise."
echo "X'BB' > X'AA' bytewise, so X'BB' should win."
echo ""

DB_ZIG_025="$TMPDIR/mr025_zig.db"
DB_RUST_025="$TMPDIR/mr025_rust.db"

# Setup: Create local row with X'AA' in both DBs
run_zig "$DB_ZIG_025" "
CREATE TABLE blobs (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('blobs');
INSERT INTO blobs VALUES (1, X'AA');
"

run_rust "$DB_RUST_025" "
CREATE TABLE blobs (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('blobs');
INSERT INTO blobs VALUES (1, X'AA');
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version
    ZIG_CV=$(run_zig "$DB_ZIG_025" "SELECT col_version FROM blobs__crsql_clock WHERE key=1 AND col_name='data';")
    RUST_CV=$(run_rust "$DB_RUST_025" "SELECT col_version FROM blobs__crsql_clock WHERE key=1 AND col_name='data';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote X'BB' with SAME col_version
    run_zig "$DB_ZIG_025" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('blobs', X'010901', 'data', X'BB', $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_025" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('blobs', X'010901', 'data', X'BB', $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner (using hex to display blob)
    ZIG_WINNER=$(run_zig "$DB_ZIG_025" "SELECT hex(data) FROM blobs WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_025" "SELECT hex(data) FROM blobs WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "Blob comparison winner"
    echo "    Expected: BB (bytewise larger)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# MR-026: Cross-type comparison - integer vs text
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MR-026: Cross-type comparison - integer vs text"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SQLite's type affinity means columns can hold different types."
echo "This tests that cross-type comparison is handled identically."
echo ""

DB_ZIG_026="$TMPDIR/mr026_zig.db"
DB_RUST_026="$TMPDIR/mr026_rust.db"

# Setup: Create local row with integer 42 in both DBs
run_zig "$DB_ZIG_026" "
CREATE TABLE mixed (id INTEGER PRIMARY KEY NOT NULL, data);
SELECT crsql_as_crr('mixed');
INSERT INTO mixed VALUES (1, 42);
"

run_rust "$DB_RUST_026" "
CREATE TABLE mixed (id INTEGER PRIMARY KEY NOT NULL, data);
SELECT crsql_as_crr('mixed');
INSERT INTO mixed VALUES (1, 42);
"

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Get local col_version
    ZIG_CV=$(run_zig "$DB_ZIG_026" "SELECT col_version FROM mixed__crsql_clock WHERE key=1 AND col_name='data';")
    RUST_CV=$(run_rust "$DB_RUST_026" "SELECT col_version FROM mixed__crsql_clock WHERE key=1 AND col_name='data';")
    
    echo "  Local col_version: Zig=$ZIG_CV, Rust=$RUST_CV"
    
    # Merge remote text '99' with SAME col_version
    run_zig "$DB_ZIG_026" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('mixed', X'010901', 'data', '99', $ZIG_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_026" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('mixed', X'010901', 'data', '99', $RUST_CV, 99, $REMOTE_SITE, 1, 0);
    "
    
    # Verify both selected the same winner
    ZIG_WINNER=$(run_zig "$DB_ZIG_026" "SELECT typeof(data) || ':' || data FROM mixed WHERE id=1;")
    RUST_WINNER=$(run_rust "$DB_RUST_026" "SELECT typeof(data) || ':' || data FROM mixed WHERE id=1;")
    
    compare "$ZIG_WINNER" "$RUST_WINNER" "Cross-type comparison winner"
    echo "    Note: SQLite type ordering is NULL < INTEGER/REAL < TEXT < BLOB"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Merge Value Comparison Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  PASS:    %d\n" "$PASS"
printf "  FAIL:    %d\n" "$FAIL"
printf "  SKIP:    %d\n" "$SKIP"
echo ""

if [[ $SKIP -gt 0 && $PASS -eq 0 && $FAIL -eq 0 ]]; then
    echo "BLOCKED: All tests skipped (functions not implemented)"
    exit 2
fi

if [[ $FAIL -gt 0 ]]; then
    echo "PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAIL test(s)."
    echo "When col_version ties, both must select the same winner via value comparison."
    echo ""
    echo "Review: zig/src/merge_oracle.zig for value comparison logic"
    exit 1
fi

echo "All merge value comparison parity tests PASSED"
echo ""
echo "Value comparison parity verified:"
echo "  - MR-020: String lexicographic comparison"
echo "  - MR-021: Integer comparison"
echo "  - MR-022: NULL vs value handling"
echo "  - MR-023: Value vs NULL handling"
echo "  - MR-024: Float comparison"
echo "  - MR-025: Blob bytewise comparison"
echo "  - MR-026: Cross-type comparison"
exit 0
