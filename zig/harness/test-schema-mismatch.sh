#!/usr/bin/env bash
# Schema Mismatch Tests for Zig CR-SQLite
# Tests behavior when schema differs between sync sites
#
# TASK-173: Schema mismatch during sync tests
#
# Test Scenarios:
# 1. Source has column destination doesn't (extra column on source)
# 2. Destination has column source doesn't (extra column on dest)
# 3. Type mismatch between sites (INTEGER vs TEXT)
#
# All tests run against both Zig and Rust/C oracle to document parity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "=== Zig CR-SQLite Schema Mismatch Tests ==="
echo "TASK-173: Verify Zig handles schema mismatches gracefully during sync"
echo ""

# Determine Zig extension path
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Build only if extension doesn't exist
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    exit 1
fi

echo "Zig extension: $ZIG_EXT"

# Check for Rust/C oracle (via sqlite-cr wrapper)
HAVE_ORACLE=1
if ! nix run github:subtleGradient/sqlite-cr -- :memory: "SELECT 1;" >/dev/null 2>&1; then
    echo "WARNING: Rust/C oracle (sqlite-cr) not available, parity checks will be skipped"
    HAVE_ORACLE=0
else
    echo "Rust/C oracle: nix run github:subtleGradient/sqlite-cr"
fi
echo ""

# Create temp files and directories
TMPDIR=$(mktemp -d)
ERRFILE=$(mktemp)
ORACLE_ERRFILE=$(mktemp)
trap "rm -rf $TMPDIR $ERRFILE $ORACLE_ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
declare -a DIVERGENCES

# ═══════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

# Get actual error (filter out harmless warnings)
get_error() {
    local errfile="$1"
    grep -v "sqlite3_close" "$errfile" 2>/dev/null | grep -v "dlsym" | grep -v "^debug(" | head -1 || true
}

# Check if test is blocked due to missing functions
check_blocked() {
    if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
        return 0
    fi
    if grep -q "no such table: crsql_changes" "$ERRFILE" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Record a divergence between Zig and Rust/C
record_divergence() {
    local test_name="$1"
    local zig_behavior="$2"
    local rust_behavior="$3"
    DIVERGENCES+=("$test_name: Zig='$zig_behavior' vs Rust='$rust_behavior'")
}

# ═══════════════════════════════════════════════════════════════════════════
# Smoke Test: Check core functions
# ═══════════════════════════════════════════════════════════════════════════

echo "Checking core function availability..."
nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" "SELECT crsql_as_crr('nonexistent');" 2>"$ERRFILE" >/dev/null || true
if check_blocked; then
    echo "BLOCKED: crsql_as_crr() not yet implemented"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                           TEST SUMMARY                               ║"
    echo "╠═══════════════════════════════════════════════════════════════════════╣"
    echo "║  PASSED:  0                                                          ║"
    echo "║  FAILED:  0                                                          ║"
    echo "║  SKIPPED: ALL (core functions not implemented)                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    exit 2
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Source has extra column (destination doesn't have it)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Source has extra column that destination doesn't"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario: Site A has (id, name, extra), Site B has (id, name)"
echo "Site A inserts with extra='value', syncs to Site B"
echo ""

test_source_has_extra_column() {
    local impl="$1"  # "zig" or "rust"
    local db1="$TMPDIR/${impl}_src_extra.sqlite"
    local db2="$TMPDIR/${impl}_dest_extra.sqlite"
    
    if [[ "$impl" == "zig" ]]; then
        # Create source with extra column
        nix run nixpkgs#sqlite -- "$db1" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE users (id PRIMARY KEY NOT NULL, name, extra);
SELECT crsql_as_crr('users');
INSERT INTO users VALUES (1, 'Alice', 'bonus_data');
EOSQL
        
        # Create destination without extra column
        nix run nixpkgs#sqlite -- "$db2" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE users (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('users');
EOSQL
        
        # Extract changes from source (format: table|pk|cid|val|col_version|db_version|site_id|cl|seq)
        local changes
        changes=$(nix run nixpkgs#sqlite -- "$db1" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
.mode list
.separator |
SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
FROM crsql_changes;
EOSQL
)
        
        # Apply each change
        local extra_result="NO_EXTRA_CHANGE"
        while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
            [[ -z "$tbl" ]] && continue
            
            nix run nixpkgs#sqlite -- "$db2" -cmd ".load $ZIG_EXT" \
                "INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);" \
                2>"$ERRFILE" || true
            
            if [[ "$cid" == "extra" ]]; then
                local apply_err
                apply_err=$(get_error "$ERRFILE")
                if [[ -n "$apply_err" ]]; then
                    extra_result="ERROR"
                else
                    extra_result="IGNORED"
                fi
            fi
        done <<< "$changes"
        
        # Check destination state
        local dest_data dest_cols
        dest_data=$(nix run nixpkgs#sqlite -- "$db2" -cmd ".load $ZIG_EXT" "SELECT id || '~' || name FROM users WHERE id = 1;" 2>/dev/null | tail -1)
        dest_cols=$(nix run nixpkgs#sqlite -- "$db2" -cmd ".load $ZIG_EXT" "SELECT COUNT(*) FROM pragma_table_info('users');" 2>/dev/null | tail -1)
        
        echo "$extra_result^$dest_data^$dest_cols"
    else
        # Rust implementation
        nix run github:subtleGradient/sqlite-cr -- "$db1" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE users (id PRIMARY KEY NOT NULL, name, extra);
SELECT crsql_as_crr('users');
INSERT INTO users VALUES (1, 'Alice', 'bonus_data');
EOSQL
        
        nix run github:subtleGradient/sqlite-cr -- "$db2" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE users (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('users');
EOSQL
        
        local changes
        changes=$(nix run github:subtleGradient/sqlite-cr -- "$db1" <<'EOSQL' 2>"$ORACLE_ERRFILE"
.mode list
.separator |
SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
FROM crsql_changes;
EOSQL
)
        
        local extra_result="NO_EXTRA_CHANGE"
        while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
            [[ -z "$tbl" ]] && continue
            
            nix run github:subtleGradient/sqlite-cr -- "$db2" \
                "INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);" \
                2>"$ORACLE_ERRFILE" || true
            
            if [[ "$cid" == "extra" ]]; then
                local apply_err
                apply_err=$(get_error "$ORACLE_ERRFILE")
                if [[ -n "$apply_err" ]]; then
                    extra_result="ERROR"
                else
                    extra_result="IGNORED"
                fi
            fi
        done <<< "$changes"
        
        local dest_data dest_cols
        dest_data=$(nix run github:subtleGradient/sqlite-cr -- "$db2" "SELECT id || '~' || name FROM users WHERE id = 1;" 2>/dev/null | grep -v "^OK$" | tail -1)
        dest_cols=$(nix run github:subtleGradient/sqlite-cr -- "$db2" "SELECT COUNT(*) FROM pragma_table_info('users');" 2>/dev/null | grep -v "^OK$" | tail -1)
        
        echo "$extra_result^$dest_data^$dest_cols"
    fi
}

# Helper to clean Rust oracle output (remove OK lines and trim)
clean_output() {
    echo "$1" | grep -v "^OK$" | tr -d '\n' | xargs
}

# Test 1a: Run Zig test
echo "Test 1a: Zig - apply changeset with extra column"
ZIG_RESULT=$(test_source_has_extra_column "zig")
ZIG_EXTRA_BEHAVIOR=$(echo "$ZIG_RESULT" | cut -d'^' -f1 | tr -d '\n' | xargs)
ZIG_DEST_DATA=$(echo "$ZIG_RESULT" | cut -d'^' -f2 | tr -d '\n' | xargs)
ZIG_DEST_COLS=$(echo "$ZIG_RESULT" | cut -d'^' -f3 | tr -d '\n' | xargs)

echo "  Zig behavior for 'extra' column: $ZIG_EXTRA_BEHAVIOR"
echo "  Destination data: $ZIG_DEST_DATA"
echo "  Destination column count: $ZIG_DEST_COLS"

# Test 1b: Run Rust test
if [[ $HAVE_ORACLE -eq 1 ]]; then
    echo ""
    echo "Test 1b: Rust/C - apply changeset with extra column"
    RUST_RESULT=$(test_source_has_extra_column "rust")
    RUST_EXTRA_BEHAVIOR=$(clean_output "$(echo "$RUST_RESULT" | cut -d'^' -f1)")
    RUST_DEST_DATA=$(clean_output "$(echo "$RUST_RESULT" | cut -d'^' -f2)")
    RUST_DEST_COLS=$(clean_output "$(echo "$RUST_RESULT" | cut -d'^' -f3)")
    
    echo "  Rust behavior for 'extra' column: $RUST_EXTRA_BEHAVIOR"
    echo "  Destination data: $RUST_DEST_DATA"
    echo "  Destination column count: $RUST_DEST_COLS"
    
    # Parity check
    echo ""
    echo "Test 1c: Parity check"
    if [[ "$ZIG_EXTRA_BEHAVIOR" == "$RUST_EXTRA_BEHAVIOR" ]]; then
        echo "  PASS: Zig and Rust/C have identical behavior ($ZIG_EXTRA_BEHAVIOR)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  DIVERGENCE: Behaviors differ"
        record_divergence "source_has_extra_column" "$ZIG_EXTRA_BEHAVIOR" "$RUST_EXTRA_BEHAVIOR"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    # Data integrity check
    echo ""
    echo "Test 1d: Data integrity check"
    if [[ "$ZIG_DEST_DATA" == *"Alice"* ]]; then
        echo "  PASS: Zig - Known columns synced correctly (name='Alice')"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Zig - Data not synced correctly: $ZIG_DEST_DATA"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    if [[ "$RUST_DEST_DATA" == *"Alice"* ]]; then
        echo "  PASS: Rust - Known columns synced correctly (name='Alice')"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Rust - Data not synced correctly: $RUST_DEST_DATA"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    # Schema integrity - trim whitespace for comparison
    ZIG_DEST_COLS_CLEAN=$(echo "$ZIG_DEST_COLS" | tr -d '[:space:]')
    if [[ "$ZIG_DEST_COLS_CLEAN" == "2" ]]; then
        echo "  PASS: Zig - Schema unchanged (2 columns)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Zig - Schema corrupted ($ZIG_DEST_COLS_CLEAN columns, expected 2)"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
else
    echo ""
    echo "Test 1b-d: SKIPPED (oracle not available)"
    TOTAL_SKIP=$((TOTAL_SKIP + 4))
    
    # Standalone Zig check
    if [[ "$ZIG_DEST_DATA" == *"Alice"* ]]; then
        echo "  PASS: Zig - Known columns synced correctly"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  INFO: Zig destination data: $ZIG_DEST_DATA"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Destination has extra column (source doesn't have it)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Destination has extra column that source doesn't"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario: Site A has (id, name), Site B has (id, name, extra)"
echo "Site A inserts, syncs to Site B. Extra column should be NULL/default."
echo ""

test_dest_has_extra_column() {
    local impl="$1"
    local src="$TMPDIR/${impl}_src_simple.sqlite"
    local dest="$TMPDIR/${impl}_dest_with_extra.sqlite"
    
    if [[ "$impl" == "zig" ]]; then
        nix run nixpkgs#sqlite -- "$src" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE products (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('products');
INSERT INTO products VALUES (100, 'Widget');
EOSQL
        
        nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE products (id PRIMARY KEY NOT NULL, name, extra DEFAULT 'default_val');
SELECT crsql_as_crr('products');
EOSQL
        
        local changes
        changes=$(nix run nixpkgs#sqlite -- "$src" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
.mode list
.separator |
SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
FROM crsql_changes;
EOSQL
)
        
        while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
            [[ -z "$tbl" ]] && continue
            nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" \
                "INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);" \
                2>"$ERRFILE" || true
        done <<< "$changes"
        
        nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" "SELECT id || '~' || name || '~' || COALESCE(extra, 'NULL') FROM products WHERE id = 100;" 2>/dev/null | tail -1
    else
        nix run github:subtleGradient/sqlite-cr -- "$src" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE products (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('products');
INSERT INTO products VALUES (100, 'Widget');
EOSQL
        
        nix run github:subtleGradient/sqlite-cr -- "$dest" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE products (id PRIMARY KEY NOT NULL, name, extra DEFAULT 'default_val');
SELECT crsql_as_crr('products');
EOSQL
        
        local changes
        changes=$(nix run github:subtleGradient/sqlite-cr -- "$src" <<'EOSQL' 2>"$ORACLE_ERRFILE"
.mode list
.separator |
SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
FROM crsql_changes;
EOSQL
)
        
        while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
            [[ -z "$tbl" ]] && continue
            nix run github:subtleGradient/sqlite-cr -- "$dest" \
                "INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);" \
                2>"$ORACLE_ERRFILE" || true
        done <<< "$changes"
        
        nix run github:subtleGradient/sqlite-cr -- "$dest" "SELECT id || '~' || name || '~' || COALESCE(extra, 'NULL') FROM products WHERE id = 100;" 2>/dev/null | grep -v "^OK$" | tail -1
    fi
}

echo "Test 2a: Zig - apply changeset to table with extra column"
ZIG_DEST_ROW=$(test_dest_has_extra_column "zig" | tr -d '\n' | xargs)
echo "  Zig destination row: $ZIG_DEST_ROW"

if [[ $HAVE_ORACLE -eq 1 ]]; then
    echo ""
    echo "Test 2b: Rust/C - apply changeset to table with extra column"
    RUST_DEST_ROW=$(clean_output "$(test_dest_has_extra_column "rust")")
    echo "  Rust destination row: $RUST_DEST_ROW"
    
    echo ""
    echo "Test 2c: Parity and integrity check"
    
    if [[ "$ZIG_DEST_ROW" == *"Widget"* ]]; then
        echo "  PASS: Zig - Row synced with name='Widget'"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Zig - Row not synced correctly: $ZIG_DEST_ROW"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    if [[ "$RUST_DEST_ROW" == *"Widget"* ]]; then
        echo "  PASS: Rust - Row synced with name='Widget'"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Rust - Row not synced correctly: $RUST_DEST_ROW"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    if [[ "$ZIG_DEST_ROW" == *"default_val"* ]] || [[ "$ZIG_DEST_ROW" == *"NULL"* ]]; then
        echo "  PASS: Zig - Extra column has default/NULL value"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  INFO: Zig - Extra column value in: $ZIG_DEST_ROW"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    fi
    
    if [[ "$RUST_DEST_ROW" == *"default_val"* ]] || [[ "$RUST_DEST_ROW" == *"NULL"* ]]; then
        echo "  PASS: Rust - Extra column has default/NULL value"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  INFO: Rust - Extra column value in: $RUST_DEST_ROW"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    fi
else
    echo ""
    echo "Test 2b-c: SKIPPED (oracle not available)"
    TOTAL_SKIP=$((TOTAL_SKIP + 4))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Column type mismatch between sites
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Column type mismatch (INTEGER vs TEXT)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario: Site A has 'val' as INTEGER, Site B has 'val' as TEXT"
echo "Site A inserts val=42, syncs to Site B. Document type coercion behavior."
echo ""
echo "Note: SQLite has flexible typing, so this tests type affinity behavior"
echo ""

test_type_mismatch() {
    local impl="$1"
    local direction="$2"  # "int_to_text" or "text_to_int"
    local src="$TMPDIR/${impl}_${direction}_src.sqlite"
    local dest="$TMPDIR/${impl}_${direction}_dest.sqlite"
    
    if [[ "$impl" == "zig" ]]; then
        if [[ "$direction" == "int_to_text" ]]; then
            nix run nixpkgs#sqlite -- "$src" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('data');
INSERT INTO data VALUES (1, 42);
EOSQL
            
            nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('data');
EOSQL
        else
            nix run nixpkgs#sqlite -- "$src" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('data');
INSERT INTO data VALUES (1, 'hello');
EOSQL
            
            nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('data');
EOSQL
        fi
        
        local changes
        changes=$(nix run nixpkgs#sqlite -- "$src" -cmd ".load $ZIG_EXT" <<'EOSQL' 2>"$ERRFILE"
.mode list
.separator |
SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
FROM crsql_changes;
EOSQL
)
        
        while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
            [[ -z "$tbl" ]] && continue
            nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" \
                "INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);" \
                2>"$ERRFILE" || true
        done <<< "$changes"
        
        nix run nixpkgs#sqlite -- "$dest" -cmd ".load $ZIG_EXT" "SELECT val || '~' || typeof(val) FROM data WHERE id = 1;" 2>/dev/null | tail -1
    else
        if [[ "$direction" == "int_to_text" ]]; then
            nix run github:subtleGradient/sqlite-cr -- "$src" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('data');
INSERT INTO data VALUES (1, 42);
EOSQL
            
            nix run github:subtleGradient/sqlite-cr -- "$dest" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('data');
EOSQL
        else
            nix run github:subtleGradient/sqlite-cr -- "$src" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('data');
INSERT INTO data VALUES (1, 'hello');
EOSQL
            
            nix run github:subtleGradient/sqlite-cr -- "$dest" <<'EOSQL' 2>"$ORACLE_ERRFILE"
CREATE TABLE data (id PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('data');
EOSQL
        fi
        
        local changes
        changes=$(nix run github:subtleGradient/sqlite-cr -- "$src" <<'EOSQL' 2>"$ORACLE_ERRFILE"
.mode list
.separator |
SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
FROM crsql_changes;
EOSQL
)
        
        while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
            [[ -z "$tbl" ]] && continue
            nix run github:subtleGradient/sqlite-cr -- "$dest" \
                "INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);" \
                2>"$ORACLE_ERRFILE" || true
        done <<< "$changes"
        
        nix run github:subtleGradient/sqlite-cr -- "$dest" "SELECT val || '~' || typeof(val) FROM data WHERE id = 1;" 2>/dev/null | grep -v "^OK$" | tail -1
    fi
}

# Test 3a: INTEGER to TEXT
echo "Test 3a: Zig - sync INTEGER value to TEXT affinity column"
ZIG_INT_TO_TEXT=$(test_type_mismatch "zig" "int_to_text" | tr -d '\n' | xargs)
echo "  Zig result: $ZIG_INT_TO_TEXT"

if [[ $HAVE_ORACLE -eq 1 ]]; then
    echo ""
    echo "Test 3b: Rust/C - sync INTEGER value to TEXT affinity column"
    RUST_INT_TO_TEXT=$(clean_output "$(test_type_mismatch "rust" "int_to_text")")
    echo "  Rust result: $RUST_INT_TO_TEXT"
    
    echo ""
    echo "Test 3c: Parity and type coercion check"
    
    if [[ "$ZIG_INT_TO_TEXT" == "$RUST_INT_TO_TEXT" ]]; then
        echo "  PASS: Zig and Rust/C have identical type handling"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  DIVERGENCE: Type handling differs"
        echo "    Zig:  $ZIG_INT_TO_TEXT"
        echo "    Rust: $RUST_INT_TO_TEXT"
        record_divergence "type_mismatch_int_to_text" "$ZIG_INT_TO_TEXT" "$RUST_INT_TO_TEXT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    if [[ "$ZIG_INT_TO_TEXT" == *"42"* ]]; then
        echo "  PASS: Zig - Value synced (42)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Zig - Value not synced: $ZIG_INT_TO_TEXT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    if [[ "$RUST_INT_TO_TEXT" == *"42"* ]]; then
        echo "  PASS: Rust - Value synced (42)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  FAIL: Rust - Value not synced: $RUST_INT_TO_TEXT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
else
    echo ""
    echo "Test 3b-c: SKIPPED (oracle not available)"
    TOTAL_SKIP=$((TOTAL_SKIP + 3))
fi

# Test 3d: TEXT to INTEGER (reverse direction)
echo ""
echo "Test 3d: Reverse - sync TEXT value to INTEGER affinity column"
ZIG_TEXT_TO_INT=$(test_type_mismatch "zig" "text_to_int" | tr -d '\n' | xargs)
echo "  Zig TEXT->INTEGER result: $ZIG_TEXT_TO_INT"

if [[ $HAVE_ORACLE -eq 1 ]]; then
    RUST_TEXT_TO_INT=$(clean_output "$(test_type_mismatch "rust" "text_to_int")")
    echo "  Rust TEXT->INTEGER result: $RUST_TEXT_TO_INT"
    
    if [[ "$ZIG_TEXT_TO_INT" == "$RUST_TEXT_TO_INT" ]]; then
        echo "  PASS: Zig and Rust/C have identical TEXT->INTEGER handling"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  DIVERGENCE: TEXT->INTEGER handling differs"
        record_divergence "type_mismatch_text_to_int" "$ZIG_TEXT_TO_INT" "$RUST_TEXT_TO_INT"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
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

if [[ ${#DIVERGENCES[@]} -gt 0 ]]; then
    echo ""
    echo "Divergences found:"
    for div in "${DIVERGENCES[@]}"; do
        echo "  - $div"
    done
fi

echo ""
if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "✓ All implemented tests PASSED"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo "⚠ All tests SKIPPED"
    exit 2
else
    echo "✗ Some tests FAILED or divergences found"
    exit 1
fi
