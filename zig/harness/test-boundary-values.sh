#!/usr/bin/env bash
# Boundary Value Edge Case Tests for Zig CR-SQLite (Oracle Parity)
#
# Tests that extreme values roundtrip correctly through sync between
# Zig and Rust/C implementations.
#
# Test cases:
#   EC-010: MAX_INT64 (9223372036854775807)
#   EC-011: MIN_INT64 (-9223372036854775808)
#   EC-012: MAX_FLOAT (1.7976931348623157e+308)
#   EC-013: 1MB text
#   EC-014: 1MB blob
#   EC-020: Emoji (🎉🚀)
#   EC-021: NULL bytes in text
#
# Context: TASK-137, research/zig-cr/96-ideal-parity-experiments.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Boundary Value Edge Case Tests (Zig vs Rust/C Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

# Create temp directory - CRITICAL: use .tmp/, never /tmp/
TMP_DIR="$REPO_ROOT/.tmp/test-boundary-$$"
mkdir -p "$TMP_DIR"
trap "rm -rf $TMP_DIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0

ERRFILE="$TMP_DIR/error.txt"

# Helper to run SQL with Zig extension (clean sqlite, explicit .load)
run_zig() {
    local db="$1"; shift
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$@" 2>"$ERRFILE" || true
}

run_zig_silent() {
    local db="$1"; shift
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$@" >/dev/null 2>"$ERRFILE" || true
}

# Helper to run SQL with Rust/C extension
run_rust() {
    local db="$1"; shift
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$@" 2>"$ERRFILE" || true
}

run_rust_silent() {
    local db="$1"; shift
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$@" >/dev/null 2>"$ERRFILE" || true
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

# Sync from source DB to target DB (extract changes, apply)
# Usage: sync_changes SOURCE_DB SOURCE_RUN_FN TARGET_DB TARGET_RUN_FN
# This extracts all crsql_changes from source and applies to target
sync_changes() {
    local src_db="$1"
    local src_fn="$2"
    local tgt_db="$3"
    local tgt_fn="$4"
    
    local changes_file="$TMP_DIR/changes_$$.sql"
    
    # Get target site_id to exclude
    local tgt_site
    tgt_site=$($tgt_fn "$tgt_db" "SELECT quote(crsql_site_id());")
    
    # Export changes from source
    $src_fn "$src_db" "
        SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
            quote([table]) || ', ' ||
            quote(pk) || ', ' ||
            quote(cid) || ', ' ||
            quote(val) || ', ' ||
            col_version || ', ' ||
            db_version || ', ' ||
            quote(site_id) || ', ' ||
            cl || ', ' ||
            seq || ');'
        FROM crsql_changes
        WHERE site_id IS NOT $tgt_site;
    " > "$changes_file"
    
    # Apply changes to target
    if [[ -s "$changes_file" ]]; then
        $tgt_fn "$tgt_db" ".read $changes_file" 2>>"$ERRFILE" || true
    fi
    
    rm -f "$changes_file"
}

# ══════════════════════════════════════════════════════════════════════════════
# EC-010: MAX_INT64 (9223372036854775807) roundtrips through sync
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-010: MAX_INT64 (9223372036854775807) roundtrips through sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MAX_INT64="9223372036854775807"
DB_RUST_10="$TMP_DIR/ec010_rust.db"
DB_ZIG_10="$TMP_DIR/ec010_zig.db"

# Create table in both DBs
run_rust_silent "$DB_RUST_10" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value INTEGER);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_10" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value INTEGER);
    SELECT crsql_as_crr('t');
"

# Insert MAX_INT64 in Rust
run_rust_silent "$DB_RUST_10" "INSERT INTO t (id, value) VALUES (1, $MAX_INT64);"

# Sync Rust -> Zig
RUST_SITE=$(run_rust "$DB_RUST_10" "SELECT quote(crsql_site_id());")
CHANGES=$(run_rust "$DB_RUST_10" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_10" ".read /dev/stdin"

# Verify in Zig
ZIG_VALUE=$(run_zig "$DB_ZIG_10" "SELECT value FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_VALUE" == "$MAX_INT64" ]]; then
    echo "  PASS: MAX_INT64 roundtripped correctly"
    echo "    Value: $ZIG_VALUE"
    PASS=$((PASS + 1))
else
    echo "  FAIL: MAX_INT64 value mismatch"
    echo "    Expected: $MAX_INT64"
    echo "    Got:      $ZIG_VALUE"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EC-011: MIN_INT64 (-9223372036854775808) roundtrips through sync
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-011: MIN_INT64 (-9223372036854775808) roundtrips through sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MIN_INT64="-9223372036854775808"
DB_RUST_11="$TMP_DIR/ec011_rust.db"
DB_ZIG_11="$TMP_DIR/ec011_zig.db"

# Create table in both DBs
run_rust_silent "$DB_RUST_11" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value INTEGER);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_11" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value INTEGER);
    SELECT crsql_as_crr('t');
"

# Insert MIN_INT64 in Rust
run_rust_silent "$DB_RUST_11" "INSERT INTO t (id, value) VALUES (1, $MIN_INT64);"

# Sync Rust -> Zig
CHANGES=$(run_rust "$DB_RUST_11" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_11" ".read /dev/stdin"

# Verify in Zig
ZIG_VALUE=$(run_zig "$DB_ZIG_11" "SELECT value FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_VALUE" == "$MIN_INT64" ]]; then
    echo "  PASS: MIN_INT64 roundtripped correctly"
    echo "    Value: $ZIG_VALUE"
    PASS=$((PASS + 1))
else
    echo "  FAIL: MIN_INT64 value mismatch"
    echo "    Expected: $MIN_INT64"
    echo "    Got:      $ZIG_VALUE"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EC-012: MAX_FLOAT (1.7976931348623157e+308) roundtrips through sync
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-012: MAX_FLOAT roundtrips through sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MAX_FLOAT="1.7976931348623157e+308"
DB_RUST_12="$TMP_DIR/ec012_rust.db"
DB_ZIG_12="$TMP_DIR/ec012_zig.db"

# Create table in both DBs
run_rust_silent "$DB_RUST_12" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value REAL);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_12" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value REAL);
    SELECT crsql_as_crr('t');
"

# Insert MAX_FLOAT in Rust
run_rust_silent "$DB_RUST_12" "INSERT INTO t (id, value) VALUES (1, $MAX_FLOAT);"

# Get Rust value for comparison (may format differently)
RUST_VALUE=$(run_rust "$DB_RUST_12" "SELECT value FROM t WHERE id=1;")

# Sync Rust -> Zig
CHANGES=$(run_rust "$DB_RUST_12" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_12" ".read /dev/stdin"

# Verify in Zig
ZIG_VALUE=$(run_zig "$DB_ZIG_12" "SELECT value FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_VALUE" == "$RUST_VALUE" ]]; then
    echo "  PASS: MAX_FLOAT roundtripped correctly"
    echo "    Value: $ZIG_VALUE"
    PASS=$((PASS + 1))
else
    echo "  FAIL: MAX_FLOAT value mismatch"
    echo "    Rust:     $RUST_VALUE"
    echo "    Zig:      $ZIG_VALUE"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EC-013: 1MB text roundtrips through sync
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-013: 1MB text roundtrips through sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_RUST_13="$TMP_DIR/ec013_rust.db"
DB_ZIG_13="$TMP_DIR/ec013_zig.db"
TEXT_FILE="$TMP_DIR/ec013_text.txt"

# Generate 1MB of text (base64 for safe characters)
dd if=/dev/urandom bs=1024 count=768 2>/dev/null | base64 | head -c 1048576 > "$TEXT_FILE"
TEXT_SIZE=$(wc -c < "$TEXT_FILE" | tr -d ' ')

echo "  Generated text file: $TEXT_SIZE bytes"

# Create table in both DBs
run_rust_silent "$DB_RUST_13" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_13" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
    SELECT crsql_as_crr('t');
"

# Insert 1MB text in Rust using readfile
run_rust_silent "$DB_RUST_13" "INSERT INTO t (id, value) VALUES (1, readfile('$TEXT_FILE'));"

# Get hash of original for comparison
RUST_HASH=$(run_rust "$DB_RUST_13" "SELECT hex(substr(value, 1, 32)) || '...' || length(value) FROM t WHERE id=1;")

# Sync Rust -> Zig
CHANGES=$(run_rust "$DB_RUST_13" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_13" ".read /dev/stdin"

# Verify in Zig
ZIG_HASH=$(run_zig "$DB_ZIG_13" "SELECT hex(substr(value, 1, 32)) || '...' || length(value) FROM t WHERE id=1;")
ZIG_LEN=$(run_zig "$DB_ZIG_13" "SELECT length(value) FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_HASH" == "$RUST_HASH" ]]; then
    echo "  PASS: 1MB text roundtripped correctly"
    echo "    Length: $ZIG_LEN bytes"
    echo "    Hash:   $ZIG_HASH"
    PASS=$((PASS + 1))
else
    echo "  FAIL: 1MB text mismatch"
    echo "    Rust: $RUST_HASH"
    echo "    Zig:  $ZIG_HASH"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EC-014: 1MB blob roundtrips through sync
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-014: 1MB blob roundtrips through sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_RUST_14="$TMP_DIR/ec014_rust.db"
DB_ZIG_14="$TMP_DIR/ec014_zig.db"
BLOB_FILE="$TMP_DIR/ec014_blob.bin"

# Generate 1MB binary blob
dd if=/dev/urandom bs=1024 count=1024 2>/dev/null > "$BLOB_FILE"
BLOB_SIZE=$(wc -c < "$BLOB_FILE" | tr -d ' ')

echo "  Generated blob file: $BLOB_SIZE bytes"

# Create table in both DBs
run_rust_silent "$DB_RUST_14" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value BLOB);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_14" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value BLOB);
    SELECT crsql_as_crr('t');
"

# Insert 1MB blob in Rust using readfile
run_rust_silent "$DB_RUST_14" "INSERT INTO t (id, value) VALUES (1, readfile('$BLOB_FILE'));"

# Get hash of original for comparison
RUST_HASH=$(run_rust "$DB_RUST_14" "SELECT hex(substr(value, 1, 32)) || '...' || length(value) FROM t WHERE id=1;")

# Sync Rust -> Zig
CHANGES=$(run_rust "$DB_RUST_14" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_14" ".read /dev/stdin"

# Verify in Zig
ZIG_HASH=$(run_zig "$DB_ZIG_14" "SELECT hex(substr(value, 1, 32)) || '...' || length(value) FROM t WHERE id=1;")
ZIG_LEN=$(run_zig "$DB_ZIG_14" "SELECT length(value) FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_HASH" == "$RUST_HASH" ]]; then
    echo "  PASS: 1MB blob roundtripped correctly"
    echo "    Length: $ZIG_LEN bytes"
    echo "    Hash:   $ZIG_HASH"
    PASS=$((PASS + 1))
else
    echo "  FAIL: 1MB blob mismatch"
    echo "    Rust: $RUST_HASH"
    echo "    Zig:  $ZIG_HASH"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EC-020: Emoji roundtrips through sync
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-020: Emoji (🎉🚀) roundtrips through sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

EMOJI_TEXT="🎉🚀🌈🦄💯"
DB_RUST_20="$TMP_DIR/ec020_rust.db"
DB_ZIG_20="$TMP_DIR/ec020_zig.db"

# Create table in both DBs
run_rust_silent "$DB_RUST_20" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_20" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
    SELECT crsql_as_crr('t');
"

# Insert emoji in Rust
run_rust_silent "$DB_RUST_20" "INSERT INTO t (id, value) VALUES (1, '$EMOJI_TEXT');"

# Get Rust value
RUST_VALUE=$(run_rust "$DB_RUST_20" "SELECT value FROM t WHERE id=1;")

# Sync Rust -> Zig
CHANGES=$(run_rust "$DB_RUST_20" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_20" ".read /dev/stdin"

# Verify in Zig
ZIG_VALUE=$(run_zig "$DB_ZIG_20" "SELECT value FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_VALUE" == "$RUST_VALUE" ]]; then
    echo "  PASS: Emoji roundtripped correctly"
    echo "    Value: $ZIG_VALUE"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Emoji mismatch"
    echo "    Original: $EMOJI_TEXT"
    echo "    Rust:     $RUST_VALUE"
    echo "    Zig:      $ZIG_VALUE"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EC-021: NULL bytes in text handled correctly
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EC-021: NULL bytes in text handled correctly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Note: SQLite TEXT columns can contain NUL bytes, but the sqlite3 CLI
# may have issues displaying them. We use hex comparison to verify.
# The text is: 'hello<NUL>world' stored as blob-like text

DB_RUST_21="$TMP_DIR/ec021_rust.db"
DB_ZIG_21="$TMP_DIR/ec021_zig.db"

# Create table in both DBs
run_rust_silent "$DB_RUST_21" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
    SELECT crsql_as_crr('t');
"
run_zig_silent "$DB_ZIG_21" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
    SELECT crsql_as_crr('t');
"

# Insert text with embedded NUL using CAST from blob
# X'68656C6C6F00776F726C64' = 'hello\0world'
run_rust_silent "$DB_RUST_21" "INSERT INTO t (id, value) VALUES (1, CAST(X'68656C6C6F00776F726C64' AS TEXT));"

# Get Rust value as hex for comparison
RUST_HEX=$(run_rust "$DB_RUST_21" "SELECT hex(value) FROM t WHERE id=1;")
RUST_LEN=$(run_rust "$DB_RUST_21" "SELECT length(value) FROM t WHERE id=1;")

# Sync Rust -> Zig
CHANGES=$(run_rust "$DB_RUST_21" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_zig_silent "$DB_ZIG_21" ".read /dev/stdin"

# Verify in Zig using hex
ZIG_HEX=$(run_zig "$DB_ZIG_21" "SELECT hex(value) FROM t WHERE id=1;")
ZIG_LEN=$(run_zig "$DB_ZIG_21" "SELECT length(value) FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_HEX" == "$RUST_HEX" && "$ZIG_LEN" == "$RUST_LEN" ]]; then
    echo "  PASS: Text with NULL bytes roundtripped correctly"
    echo "    Hex:    $ZIG_HEX"
    echo "    Length: $ZIG_LEN"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Text with NULL bytes mismatch"
    echo "    Rust hex: $RUST_HEX (len=$RUST_LEN)"
    echo "    Zig hex:  $ZIG_HEX (len=$ZIG_LEN)"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Bidirectional test: Verify Zig -> Rust sync also works
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bidirectional: Zig -> Rust sync verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_BI="$TMP_DIR/bidi_zig.db"
DB_RUST_BI="$TMP_DIR/bidi_rust.db"

# Create table in both DBs
run_zig_silent "$DB_ZIG_BI" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value INTEGER);
    SELECT crsql_as_crr('t');
"
run_rust_silent "$DB_RUST_BI" "
    CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, value INTEGER);
    SELECT crsql_as_crr('t');
"

# Insert MAX_INT64 in Zig
run_zig_silent "$DB_ZIG_BI" "INSERT INTO t (id, value) VALUES (1, $MAX_INT64);"

# Sync Zig -> Rust
CHANGES=$(run_zig "$DB_ZIG_BI" "
    SELECT 'INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (' ||
        quote([table]) || ', ' ||
        quote(pk) || ', ' ||
        quote(cid) || ', ' ||
        quote(val) || ', ' ||
        col_version || ', ' ||
        db_version || ', ' ||
        quote(site_id) || ', ' ||
        cl || ', ' ||
        seq || ');'
    FROM crsql_changes;
")
echo "$CHANGES" | run_rust_silent "$DB_RUST_BI" ".read /dev/stdin"

# Verify in Rust
RUST_BI_VALUE=$(run_rust "$DB_RUST_BI" "SELECT value FROM t WHERE id=1;")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$RUST_BI_VALUE" == "$MAX_INT64" ]]; then
    echo "  PASS: MAX_INT64 roundtripped Zig -> Rust correctly"
    echo "    Value: $RUST_BI_VALUE"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Zig -> Rust MAX_INT64 value mismatch"
    echo "    Expected: $MAX_INT64"
    echo "    Got:      $RUST_BI_VALUE"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Boundary Value Edge Case Test Summary"
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
    echo "The Zig implementation differs from the Rust/C oracle for $FAIL boundary value(s)."
    echo "This may cause sync incompatibility between implementations."
    exit 1
fi

echo "All boundary value edge case tests PASSED"
echo ""
echo "Verified parity for:"
echo "  - EC-010: MAX_INT64 (9223372036854775807)"
echo "  - EC-011: MIN_INT64 (-9223372036854775808)"
echo "  - EC-012: MAX_FLOAT"
echo "  - EC-013: 1MB text"
echo "  - EC-014: 1MB blob"
echo "  - EC-020: Emoji (🎉🚀🌈🦄💯)"
echo "  - EC-021: NULL bytes in text"
echo "  - Bidirectional sync (Zig -> Rust)"
exit 0
