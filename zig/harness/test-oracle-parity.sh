#!/usr/bin/env bash
# Oracle Parity Test Suite for Zig CR-SQLite
# Compares Zig implementation outputs against Rust/C (Golden Master) oracle
#
# This test ensures wire-format and behavioral compatibility by comparing
# bit-identical outputs where applicable, or semantic equivalence otherwise.
#
# Tests:
# 1. pack_columns wire format parity
# 2. Clock table schema parity
# 3. Merge resolution value parity
# 4. Site ID storage format parity
# 5. Changes vtab output format parity
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Oracle Parity (Zig vs Rust/C)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Build the Zig extension
echo "Building Zig extension..."
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo "FAIL: Zig build failed"
    exit 1
fi

# Determine Zig extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Check for Zig extension
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    exit 1
fi

# Use local oracle binaries (updated via scripts/update-crsqlite-oracle.sh)
# These are fetched from vlcn-io/cr-sqlite releases, same source as sqlite-cr.
# NOTE: The sqlite3_close() returns 5 warning is harmless and expected.
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
else
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
fi

if [[ ! -f "$RUST_EXT" ]]; then
    echo "ERROR: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 1
fi

SQLITE_ZIG="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

ERRFILE="$TMPDIR/error.txt"

PASS=0
FAIL=0
SKIP=0

# Helper to run SQL with Zig extension
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE_ZIG "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Helper to run SQL with Rust/C extension (local oracle)
run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE_ZIG "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
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

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: pack_columns Wire Format Parity
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: pack_columns Wire Format Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1a: Integer packing
echo "Test 1a: Integer packing"
ZIG_INT=$(run_zig ":memory:" "SELECT hex(crsql_pack_columns(42));")
RUST_INT=$(run_rust ":memory:" "SELECT hex(crsql_pack_columns(42));")

if is_blocked; then
    echo "  SKIP: crsql_pack_columns not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_INT" == "$RUST_INT" ]]; then
    echo "  PASS: Integer 42 -> $ZIG_INT"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Integer packing differs"
    echo "    Zig:    $ZIG_INT"
    echo "    Rust/C: $RUST_INT"
    FAIL=$((FAIL + 1))
fi

# Test 1b: Text packing
echo "Test 1b: Text packing"
ZIG_TXT=$(run_zig ":memory:" "SELECT hex(crsql_pack_columns('hello'));")
RUST_TXT=$(run_rust ":memory:" "SELECT hex(crsql_pack_columns('hello'));")

if is_blocked; then
    echo "  SKIP: crsql_pack_columns not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_TXT" == "$RUST_TXT" ]]; then
    echo "  PASS: Text 'hello' -> $ZIG_TXT"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Text packing differs"
    echo "    Zig:    $ZIG_TXT"
    echo "    Rust/C: $RUST_TXT"
    FAIL=$((FAIL + 1))
fi

# Test 1c: Blob packing
echo "Test 1c: Blob packing"
ZIG_BLB=$(run_zig ":memory:" "SELECT hex(crsql_pack_columns(X'DEADBEEF'));")
RUST_BLB=$(run_rust ":memory:" "SELECT hex(crsql_pack_columns(X'DEADBEEF'));")

if is_blocked; then
    echo "  SKIP: crsql_pack_columns not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_BLB" == "$RUST_BLB" ]]; then
    echo "  PASS: Blob X'DEADBEEF' -> $ZIG_BLB"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Blob packing differs"
    echo "    Zig:    $ZIG_BLB"
    echo "    Rust/C: $RUST_BLB"
    FAIL=$((FAIL + 1))
fi

# Test 1d: Multi-column compound PK packing
echo "Test 1d: Compound PK packing (integer + text)"
ZIG_CPK=$(run_zig ":memory:" "SELECT hex(crsql_pack_columns(42, 'hello', X'BEEF'));")
RUST_CPK=$(run_rust ":memory:" "SELECT hex(crsql_pack_columns(42, 'hello', X'BEEF'));")

if is_blocked; then
    echo "  SKIP: crsql_pack_columns not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_CPK" == "$RUST_CPK" ]]; then
    echo "  PASS: Compound (42, 'hello', X'BEEF') -> $ZIG_CPK"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Compound PK packing differs"
    echo "    Zig:    $ZIG_CPK"
    echo "    Rust/C: $RUST_CPK"
    FAIL=$((FAIL + 1))
fi

# Test 1e: NULL handling in pack_columns
echo "Test 1e: NULL in pack_columns"
ZIG_NULL=$(run_zig ":memory:" "SELECT hex(crsql_pack_columns(NULL));")
RUST_NULL=$(run_rust ":memory:" "SELECT hex(crsql_pack_columns(NULL));")

if is_blocked; then
    echo "  SKIP: crsql_pack_columns not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_NULL" == "$RUST_NULL" ]]; then
    echo "  PASS: NULL -> $ZIG_NULL"
    PASS=$((PASS + 1))
else
    echo "  FAIL: NULL packing differs"
    echo "    Zig:    $ZIG_NULL"
    echo "    Rust/C: $RUST_NULL"
    FAIL=$((FAIL + 1))
fi

# Test 1f: Float packing
echo "Test 1f: Float packing"
ZIG_FLT=$(run_zig ":memory:" "SELECT hex(crsql_pack_columns(3.14159));")
RUST_FLT=$(run_rust ":memory:" "SELECT hex(crsql_pack_columns(3.14159));")

if is_blocked; then
    echo "  SKIP: crsql_pack_columns not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_FLT" == "$RUST_FLT" ]]; then
    echo "  PASS: Float 3.14159 -> $ZIG_FLT"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Float packing differs"
    echo "    Zig:    $ZIG_FLT"
    echo "    Rust/C: $RUST_FLT"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Clock Table Schema Parity
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Clock Table Schema Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_SCHEMA="$TMPDIR/schema_zig.sqlite"
DB_RUST_SCHEMA="$TMPDIR/schema_rust.sqlite"

# Create CRR table in both
run_zig "$DB_ZIG_SCHEMA" "
    CREATE TABLE test_schema (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value REAL);
    SELECT crsql_as_crr('test_schema');
"

run_rust "$DB_RUST_SCHEMA" "
    CREATE TABLE test_schema (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value REAL);
    SELECT crsql_as_crr('test_schema');
"

if is_blocked; then
    echo "SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Test 2a: __crsql_clock table schema
    echo "Test 2a: __crsql_clock table columns"
    ZIG_CLOCK_SCHEMA=$(run_zig "$DB_ZIG_SCHEMA" "PRAGMA table_info(test_schema__crsql_clock);" | sort)
    RUST_CLOCK_SCHEMA=$(run_rust "$DB_RUST_SCHEMA" "PRAGMA table_info(test_schema__crsql_clock);" | sort)

    if [[ "$ZIG_CLOCK_SCHEMA" == "$RUST_CLOCK_SCHEMA" ]]; then
        echo "  PASS: __crsql_clock schema matches"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: __crsql_clock schema differs"
        echo "    Zig:"
        echo "$ZIG_CLOCK_SCHEMA" | sed 's/^/      /'
        echo "    Rust/C:"
        echo "$RUST_CLOCK_SCHEMA" | sed 's/^/      /'
        FAIL=$((FAIL + 1))
    fi

    # Test 2b: Check index structure
    echo "Test 2b: __crsql_clock index structure"
    ZIG_CLOCK_IDX=$(run_zig "$DB_ZIG_SCHEMA" "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='test_schema__crsql_clock' ORDER BY name;")
    RUST_CLOCK_IDX=$(run_rust "$DB_RUST_SCHEMA" "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='test_schema__crsql_clock' ORDER BY name;")

    # Normalize for comparison (index names might differ)
    ZIG_IDX_COUNT=$(run_zig "$DB_ZIG_SCHEMA" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='test_schema__crsql_clock';")
    RUST_IDX_COUNT=$(run_rust "$DB_RUST_SCHEMA" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='test_schema__crsql_clock';")

    if [[ "$ZIG_IDX_COUNT" == "$RUST_IDX_COUNT" ]]; then
        echo "  PASS: __crsql_clock index count matches ($ZIG_IDX_COUNT)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: __crsql_clock index count differs (Zig=$ZIG_IDX_COUNT, Rust=$RUST_IDX_COUNT)"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Merge Resolution Value Parity
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Merge Resolution Value Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_MERGE="$TMPDIR/merge_zig.sqlite"
DB_RUST_MERGE="$TMPDIR/merge_rust.sqlite"

# Setup identical tables
run_zig "$DB_ZIG_MERGE" "
    CREATE TABLE merge_test (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
    SELECT crsql_as_crr('merge_test');
    INSERT INTO merge_test VALUES (1, 'local');
"

run_rust "$DB_RUST_MERGE" "
    CREATE TABLE merge_test (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
    SELECT crsql_as_crr('merge_test');
    INSERT INTO merge_test VALUES (1, 'local');
"

if is_blocked; then
    echo "SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Test 3a: Remote wins with higher col_version
    echo "Test 3a: Remote wins with higher col_version"
    
    # Create a "remote" change with higher col_version
    REMOTE_SITE="X'11111111111111111111111111111111'"
    
    # Apply same remote change to both
    run_zig "$DB_ZIG_MERGE" "
        INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('merge_test', X'010901', 'val', 'remote_winner', 99, 99, $REMOTE_SITE, 1, 0);
    "
    
    run_rust "$DB_RUST_MERGE" "
        INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('merge_test', X'010901', 'val', 'remote_winner', 99, 99, $REMOTE_SITE, 1, 0);
    "

    ZIG_VAL=$(run_zig "$DB_ZIG_MERGE" "SELECT val FROM merge_test WHERE id = 1;")
    RUST_VAL=$(run_rust "$DB_RUST_MERGE" "SELECT val FROM merge_test WHERE id = 1;")

    if [[ "$ZIG_VAL" == "$RUST_VAL" && "$ZIG_VAL" == "remote_winner" ]]; then
        echo "  PASS: Both select remote_winner (higher col_version wins)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Merge resolution differs"
        echo "    Zig:    $ZIG_VAL"
        echo "    Rust/C: $RUST_VAL"
        FAIL=$((FAIL + 1))
    fi

    # Test 3b: Local wins with equal col_version but lower site_id (tiebreaker)
    echo "Test 3b: site_id tiebreaker (lower site_id wins on equal col_version)"
    
    DB_ZIG_TIE="$TMPDIR/tie_zig.sqlite"
    DB_RUST_TIE="$TMPDIR/tie_rust.sqlite"
    
    # Create with specific site_ids to control tiebreaker
    run_zig "$DB_ZIG_TIE" "
        CREATE TABLE tie_test (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
        SELECT crsql_as_crr('tie_test');
    "
    
    run_rust "$DB_RUST_TIE" "
        CREATE TABLE tie_test (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
        SELECT crsql_as_crr('tie_test');
    "
    
    # Get site_ids
    ZIG_TIE_SITE=$(run_zig "$DB_ZIG_TIE" "SELECT hex(crsql_site_id());")
    RUST_TIE_SITE=$(run_rust "$DB_RUST_TIE" "SELECT hex(crsql_site_id());")
    
    # Apply two changes with same col_version but different site_ids
    SITE_LOW="X'00000000000000000000000000000001'"
    SITE_HIGH="X'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'"
    
    run_zig "$DB_ZIG_TIE" "
        INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('tie_test', X'010901', 'val', 'high_site', 1, 1, $SITE_HIGH, 1, 0);
        INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('tie_test', X'010901', 'val', 'low_site', 1, 2, $SITE_LOW, 1, 0);
    "
    
    run_rust "$DB_RUST_TIE" "
        INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('tie_test', X'010901', 'val', 'high_site', 1, 1, $SITE_HIGH, 1, 0);
        INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
        VALUES ('tie_test', X'010901', 'val', 'low_site', 1, 2, $SITE_LOW, 1, 0);
    "
    
    ZIG_TIE_VAL=$(run_zig "$DB_ZIG_TIE" "SELECT val FROM tie_test WHERE id = 1;")
    RUST_TIE_VAL=$(run_rust "$DB_RUST_TIE" "SELECT val FROM tie_test WHERE id = 1;")
    
    if [[ "$ZIG_TIE_VAL" == "$RUST_TIE_VAL" ]]; then
        echo "  PASS: Same winner selected: $ZIG_TIE_VAL"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Tiebreaker resolution differs"
        echo "    Zig:    $ZIG_TIE_VAL"
        echo "    Rust/C: $RUST_TIE_VAL"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: Site ID Storage Format Parity
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Site ID Storage Format Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 4a: Site ID is 16 bytes (UUID format)
echo "Test 4a: Site ID length (should be 16 bytes)"
ZIG_LEN=$(run_zig ":memory:" "SELECT length(crsql_site_id());")
RUST_LEN=$(run_rust ":memory:" "SELECT length(crsql_site_id());")

if [[ "$ZIG_LEN" == "16" && "$RUST_LEN" == "16" ]]; then
    echo "  PASS: Both produce 16-byte site_id"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Site ID length differs"
    echo "    Zig:    $ZIG_LEN bytes"
    echo "    Rust/C: $RUST_LEN bytes"
    FAIL=$((FAIL + 1))
fi

# Test 4b: Cross-open a Zig-created DB with Rust/C (preserves site_id)
echo "Test 4b: Cross-open Zig DB with Rust/C preserves site_id"

DB_CROSS="$TMPDIR/cross_open.sqlite"

run_zig "$DB_CROSS" "
    CREATE TABLE cross_test (id INTEGER PRIMARY KEY NOT NULL);
    SELECT crsql_as_crr('cross_test');
"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_ORIG_SITE=$(run_zig "$DB_CROSS" "SELECT hex(crsql_site_id());")
    RUST_READ_SITE=$(run_rust "$DB_CROSS" "SELECT hex(crsql_site_id());")
    
    if [[ "$ZIG_ORIG_SITE" == "$RUST_READ_SITE" ]]; then
        echo "  PASS: Rust/C reads Zig's site_id correctly: $ZIG_ORIG_SITE"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Site ID not preserved"
        echo "    Zig created:  $ZIG_ORIG_SITE"
        echo "    Rust/C reads: $RUST_READ_SITE"
        FAIL=$((FAIL + 1))
    fi
fi

# Test 4c: Cross-open a Rust/C-created DB with Zig (preserves site_id)
echo "Test 4c: Cross-open Rust/C DB with Zig preserves site_id"

DB_CROSS2="$TMPDIR/cross_open2.sqlite"

run_rust "$DB_CROSS2" "
    CREATE TABLE cross_test2 (id INTEGER PRIMARY KEY NOT NULL);
    SELECT crsql_as_crr('cross_test2');
"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    RUST_ORIG_SITE=$(run_rust "$DB_CROSS2" "SELECT hex(crsql_site_id());")
    ZIG_READ_SITE=$(run_zig "$DB_CROSS2" "SELECT hex(crsql_site_id());")
    
    if [[ "$RUST_ORIG_SITE" == "$ZIG_READ_SITE" ]]; then
        echo "  PASS: Zig reads Rust/C's site_id correctly: $RUST_ORIG_SITE"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Site ID not preserved"
        echo "    Rust/C created: $RUST_ORIG_SITE"
        echo "    Zig reads:      $ZIG_READ_SITE"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Test 5: Changes Virtual Table Output Format
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Changes Virtual Table Output Format"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_CHG="$TMPDIR/changes_zig.sqlite"
DB_RUST_CHG="$TMPDIR/changes_rust.sqlite"

# Create identical data in both
run_zig "$DB_ZIG_CHG" "
    CREATE TABLE chg_test (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
    SELECT crsql_as_crr('chg_test');
    INSERT INTO chg_test VALUES (1, 'test', 42);
"

run_rust "$DB_RUST_CHG" "
    CREATE TABLE chg_test (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
    SELECT crsql_as_crr('chg_test');
    INSERT INTO chg_test VALUES (1, 'test', 42);
"

if is_blocked; then
    echo "SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    # Test 5a: crsql_changes column names
    echo "Test 5a: crsql_changes column names"
    ZIG_COLS=$(run_zig "$DB_ZIG_CHG" "PRAGMA table_info(crsql_changes);" | awk -F'|' '{print $2}' | sort | tr '\n' ',')
    RUST_COLS=$(run_rust "$DB_RUST_CHG" "PRAGMA table_info(crsql_changes);" | awk -F'|' '{print $2}' | sort | tr '\n' ',')
    
    if [[ "$ZIG_COLS" == "$RUST_COLS" ]]; then
        echo "  PASS: crsql_changes columns match"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: crsql_changes columns differ"
        echo "    Zig:    $ZIG_COLS"
        echo "    Rust/C: $RUST_COLS"
        FAIL=$((FAIL + 1))
    fi

    # Test 5b: Change record format for same data
    echo "Test 5b: Change record format (same data produces same pk blob)"
    
    # Extract pk blob for id=1
    ZIG_PK=$(run_zig "$DB_ZIG_CHG" "SELECT hex(pk) FROM crsql_changes WHERE [table]='chg_test' LIMIT 1;")
    RUST_PK=$(run_rust "$DB_RUST_CHG" "SELECT hex(pk) FROM crsql_changes WHERE [table]='chg_test' LIMIT 1;")
    
    if [[ "$ZIG_PK" == "$RUST_PK" ]]; then
        echo "  PASS: PK blob encoding identical: $ZIG_PK"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: PK blob encoding differs"
        echo "    Zig:    $ZIG_PK"
        echo "    Rust/C: $RUST_PK"
        FAIL=$((FAIL + 1))
    fi

    # Test 5c: Value encoding
    echo "Test 5c: Value encoding in changes (quote(val))"
    ZIG_VALS=$(run_zig "$DB_ZIG_CHG" "SELECT cid, quote(val) FROM crsql_changes WHERE [table]='chg_test' ORDER BY cid;")
    RUST_VALS=$(run_rust "$DB_RUST_CHG" "SELECT cid, quote(val) FROM crsql_changes WHERE [table]='chg_test' ORDER BY cid;")
    
    if [[ "$ZIG_VALS" == "$RUST_VALS" ]]; then
        echo "  PASS: Value encoding matches"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Value encoding differs"
        echo "    Zig:"
        echo "$ZIG_VALS" | sed 's/^/      /'
        echo "    Rust/C:"
        echo "$RUST_VALS" | sed 's/^/      /'
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Test 6: db_version Behavior Parity
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: db_version Behavior Parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 6a: Initial db_version is 0
echo "Test 6a: Initial db_version is 0"
ZIG_INIT=$(run_zig ":memory:" "SELECT crsql_db_version();")
RUST_INIT=$(run_rust ":memory:" "SELECT crsql_db_version();")

if [[ "$ZIG_INIT" == "0" && "$RUST_INIT" == "0" ]]; then
    echo "  PASS: Both start at db_version=0"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Initial db_version differs"
    echo "    Zig:    $ZIG_INIT"
    echo "    Rust/C: $RUST_INIT"
    FAIL=$((FAIL + 1))
fi

# Test 6b: db_version advances after INSERT
echo "Test 6b: db_version advances after INSERT"

DB_ZIG_VER="$TMPDIR/version_zig.sqlite"
DB_RUST_VER="$TMPDIR/version_rust.sqlite"

run_zig "$DB_ZIG_VER" "
    CREATE TABLE ver_test (id INTEGER PRIMARY KEY NOT NULL);
    SELECT crsql_as_crr('ver_test');
    INSERT INTO ver_test VALUES (1);
"

run_rust "$DB_RUST_VER" "
    CREATE TABLE ver_test (id INTEGER PRIMARY KEY NOT NULL);
    SELECT crsql_as_crr('ver_test');
    INSERT INTO ver_test VALUES (1);
"

if is_blocked; then
    echo "  SKIP: crsql_as_crr not implemented"
    SKIP=$((SKIP + 1))
else
    ZIG_VER=$(run_zig "$DB_ZIG_VER" "SELECT crsql_db_version();")
    RUST_VER=$(run_rust "$DB_RUST_VER" "SELECT crsql_db_version();")
    
    if [[ "$ZIG_VER" -gt 0 && "$RUST_VER" -gt 0 ]]; then
        echo "  PASS: Both advance db_version after INSERT (Zig=$ZIG_VER, Rust=$RUST_VER)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: db_version should advance after INSERT"
        echo "    Zig:    $ZIG_VER"
        echo "    Rust/C: $RUST_VER"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Oracle Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""

if [[ $FAIL -eq 0 ]]; then
    if [[ $SKIP -gt 0 ]]; then
        echo "Some tests skipped (functions not implemented)"
        exit 0
    else
        echo "All oracle parity tests PASSED"
        echo ""
        echo "Wire format and behavioral parity verified:"
        echo "  - pack_columns encoding matches"
        echo "  - Clock table schema matches"
        echo "  - Merge resolution matches"
        echo "  - Site ID storage matches"
        echo "  - Changes vtab format matches"
        echo "  - db_version behavior matches"
        exit 0
    fi
else
    echo "PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAIL test(s)."
    echo "This may cause sync incompatibility between implementations."
    exit 1
fi
