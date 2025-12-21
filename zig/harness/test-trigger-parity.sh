#!/usr/bin/env bash
# Test: Trigger/Clock Logic Equivalence (Oracle Parity)
# Validates that INSERT/UPDATE/DELETE triggers produce identical __crsql_clock
# entries in both Rust/C and Zig implementations.
#
# This is an oracle test: Given the same DML sequence, both implementations
# must produce identical clock table contents (col_version, db_version, seq).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Trigger/Clock Logic Equivalence (Oracle Parity)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine extension paths based on platform
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
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
    echo "ERROR: Zig extension not found at $ZIG_EXT"
    echo "Run 'cd zig && nix run nixpkgs#zig -- build' to build it first"
    exit 1
fi

# NOTE: The sqlite3_close() returns 5 warning is harmless and expected.
SQLITE="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory and files
TMPDIR="${SCRIPT_DIR}/../../.tmp"
mkdir -p "$TMPDIR"
RUST_DB=$(mktemp "$TMPDIR/rust-parity.XXXXXX.db")
ZIG_DB=$(mktemp "$TMPDIR/zig-parity.XXXXXX.db")
RUST_OUT=$(mktemp "$TMPDIR/rust-out.XXXXXX")
ZIG_OUT=$(mktemp "$TMPDIR/zig-out.XXXXXX")
ERRFILE=$(mktemp "$TMPDIR/parity-err.XXXXXX")
trap "rm -f $RUST_DB $ZIG_DB $RUST_OUT $ZIG_OUT $ERRFILE" EXIT

PASS=0
FAIL=0

# Helper: Run SQL on Rust/C oracle (local binary)
run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

# Helper: Run SQL on Zig extension
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

# Helper: Dump clock table sorted for comparison
# Note: Both implementations use "key" column in clock tables
dump_clock_rust() {
    local db="$1"
    local table="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" \
        "SELECT key, col_name, col_version, db_version, seq FROM ${table}__crsql_clock ORDER BY key, col_name, db_version;" 2>/dev/null || true
}

dump_clock_zig() {
    local db="$1"
    local table="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT sqlite3_crsqlite_init" \
        "SELECT key, col_name, col_version, db_version, seq FROM ${table}__crsql_clock ORDER BY key, col_name, db_version;" 2>/dev/null || true
}

# Helper: Compare clock tables between implementations
compare_clocks() {
    local table="$1"
    local step="$2"
    
    dump_clock_rust "$RUST_DB" "$table" > "$RUST_OUT"
    dump_clock_zig "$ZIG_DB" "$table" > "$ZIG_OUT"
    
    if diff -q "$RUST_OUT" "$ZIG_OUT" > /dev/null 2>&1; then
        echo "  PASS: Clock tables match after $step"
        return 0
    else
        echo "  FAIL: Clock tables diverge after $step"
        echo "    Rust/C output:"
        sed 's/^/      /' "$RUST_OUT"
        echo "    Zig output:"
        sed 's/^/      /' "$ZIG_OUT"
        echo "    Diff:"
        diff "$RUST_OUT" "$ZIG_OUT" | sed 's/^/      /' || true
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Single-Column Primary Key Table
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Single-Column PK Table"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Initialize fresh databases
rm -f "$RUST_DB" "$ZIG_DB"

# Setup schema in both
SETUP_SQL="
CREATE TABLE items (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT,
    value INTEGER
);
SELECT crsql_as_crr('items');
"

echo "Setting up schema..."
run_rust "$RUST_DB" "$SETUP_SQL"
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "ERROR: Rust/C extension failed to load"
    cat "$ERRFILE"
    exit 1
fi

run_zig "$ZIG_DB" "$SETUP_SQL"
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "ERROR: Zig extension failed to load"
    cat "$ERRFILE"
    exit 1
fi

# Step 1: INSERT row
echo ""
echo "Step 1: INSERT row (id=1, name='test', value=100)"
INSERT_SQL="INSERT INTO items (id, name, value) VALUES (1, 'test', 100);"
run_rust "$RUST_DB" "$INSERT_SQL"
run_zig "$ZIG_DB" "$INSERT_SQL"

if compare_clocks "items" "INSERT"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 2: UPDATE single column
echo ""
echo "Step 2: UPDATE single column (name='updated')"
UPDATE1_SQL="UPDATE items SET name = 'updated' WHERE id = 1;"
run_rust "$RUST_DB" "$UPDATE1_SQL"
run_zig "$ZIG_DB" "$UPDATE1_SQL"

if compare_clocks "items" "UPDATE single column"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 3: UPDATE multiple columns
echo ""
echo "Step 3: UPDATE multiple columns (name='multi', value=200)"
UPDATE2_SQL="UPDATE items SET name = 'multi', value = 200 WHERE id = 1;"
run_rust "$RUST_DB" "$UPDATE2_SQL"
run_zig "$ZIG_DB" "$UPDATE2_SQL"

if compare_clocks "items" "UPDATE multiple columns"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 4: DELETE row
echo ""
echo "Step 4: DELETE row"
DELETE_SQL="DELETE FROM items WHERE id = 1;"
run_rust "$RUST_DB" "$DELETE_SQL"
run_zig "$ZIG_DB" "$DELETE_SQL"

if compare_clocks "items" "DELETE"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 5: Re-INSERT same PK (resurrection)
echo ""
echo "Step 5: Re-INSERT same PK (resurrection)"
REINSERT_SQL="INSERT INTO items (id, name, value) VALUES (1, 'resurrected', 999);"
run_rust "$RUST_DB" "$REINSERT_SQL"
run_zig "$ZIG_DB" "$REINSERT_SQL"

if compare_clocks "items" "Re-INSERT (resurrection)"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Compound Primary Key Table
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Compound Primary Key Table"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Reset databases
rm -f "$RUST_DB" "$ZIG_DB"

# Setup compound PK schema
SETUP_CPK_SQL="
CREATE TABLE relations (
    user_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    role TEXT,
    score INTEGER,
    PRIMARY KEY (user_id, item_id)
);
SELECT crsql_as_crr('relations');
"

echo "Setting up compound PK schema..."
run_rust "$RUST_DB" "$SETUP_CPK_SQL"
run_zig "$ZIG_DB" "$SETUP_CPK_SQL"

# Step 1: INSERT
echo ""
echo "Step 1: INSERT compound PK row (user_id=1, item_id=2)"
CPK_INSERT="INSERT INTO relations (user_id, item_id, role, score) VALUES (1, 2, 'owner', 10);"
run_rust "$RUST_DB" "$CPK_INSERT"
run_zig "$ZIG_DB" "$CPK_INSERT"

if compare_clocks "relations" "INSERT compound PK"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 2: UPDATE single column
echo ""
echo "Step 2: UPDATE single column (role='admin')"
CPK_UPDATE1="UPDATE relations SET role = 'admin' WHERE user_id = 1 AND item_id = 2;"
run_rust "$RUST_DB" "$CPK_UPDATE1"
run_zig "$ZIG_DB" "$CPK_UPDATE1"

if compare_clocks "relations" "UPDATE single column (compound PK)"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 3: UPDATE multiple columns
echo ""
echo "Step 3: UPDATE multiple columns (role='super', score=99)"
CPK_UPDATE2="UPDATE relations SET role = 'super', score = 99 WHERE user_id = 1 AND item_id = 2;"
run_rust "$RUST_DB" "$CPK_UPDATE2"
run_zig "$ZIG_DB" "$CPK_UPDATE2"

if compare_clocks "relations" "UPDATE multiple columns (compound PK)"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 4: DELETE
echo ""
echo "Step 4: DELETE compound PK row"
CPK_DELETE="DELETE FROM relations WHERE user_id = 1 AND item_id = 2;"
run_rust "$RUST_DB" "$CPK_DELETE"
run_zig "$ZIG_DB" "$CPK_DELETE"

if compare_clocks "relations" "DELETE (compound PK)"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# Step 5: Re-INSERT (resurrection)
echo ""
echo "Step 5: Re-INSERT compound PK (resurrection)"
CPK_REINSERT="INSERT INTO relations (user_id, item_id, role, score) VALUES (1, 2, 'revived', 1);"
run_rust "$RUST_DB" "$CPK_REINSERT"
run_zig "$ZIG_DB" "$CPK_REINSERT"

if compare_clocks "relations" "Re-INSERT (compound PK resurrection)"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Table with Nullable Columns
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Table with Nullable Columns"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Reset databases
rm -f "$RUST_DB" "$ZIG_DB"

# Note: Rust/C extension requires NOT NULL columns to have DEFAULT values
# for forward/backward schema compatibility
SETUP_NULL_SQL="
CREATE TABLE nullable (
    id INTEGER PRIMARY KEY NOT NULL,
    required TEXT NOT NULL DEFAULT '',
    optional TEXT
);
SELECT crsql_as_crr('nullable');
"

echo "Setting up nullable columns schema..."
run_rust "$RUST_DB" "$SETUP_NULL_SQL"
run_zig "$ZIG_DB" "$SETUP_NULL_SQL"

# INSERT with NULL
echo ""
echo "Step 1: INSERT with NULL (optional=NULL)"
NULL_INSERT="INSERT INTO nullable (id, required, optional) VALUES (1, 'required_value', NULL);"
run_rust "$RUST_DB" "$NULL_INSERT"
run_zig "$ZIG_DB" "$NULL_INSERT"

if compare_clocks "nullable" "INSERT with NULL"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# UPDATE NULL to value
echo ""
echo "Step 2: UPDATE NULL to value (optional='now set')"
NULL_UPDATE1="UPDATE nullable SET optional = 'now set' WHERE id = 1;"
run_rust "$RUST_DB" "$NULL_UPDATE1"
run_zig "$ZIG_DB" "$NULL_UPDATE1"

if compare_clocks "nullable" "UPDATE NULL to value"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# UPDATE value back to NULL
echo ""
echo "Step 3: UPDATE value back to NULL"
NULL_UPDATE2="UPDATE nullable SET optional = NULL WHERE id = 1;"
run_rust "$RUST_DB" "$NULL_UPDATE2"
run_zig "$ZIG_DB" "$NULL_UPDATE2"

if compare_clocks "nullable" "UPDATE value to NULL"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Table with DEFAULT Values
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Table with DEFAULT Values"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Reset databases
rm -f "$RUST_DB" "$ZIG_DB"

# Note: Rust/C extension requires NOT NULL columns to have DEFAULT values
SETUP_DEFAULT_SQL="
CREATE TABLE defaults (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL DEFAULT '',
    status TEXT DEFAULT 'pending',
    count INTEGER DEFAULT 0
);
SELECT crsql_as_crr('defaults');
"

echo "Setting up table with DEFAULT values..."
run_rust "$RUST_DB" "$SETUP_DEFAULT_SQL"
run_zig "$ZIG_DB" "$SETUP_DEFAULT_SQL"

# INSERT relying on defaults
echo ""
echo "Step 1: INSERT relying on DEFAULT values"
DEFAULT_INSERT="INSERT INTO defaults (id, name) VALUES (1, 'test');"
run_rust "$RUST_DB" "$DEFAULT_INSERT"
run_zig "$ZIG_DB" "$DEFAULT_INSERT"

if compare_clocks "defaults" "INSERT with DEFAULTs"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# UPDATE default column
echo ""
echo "Step 2: UPDATE default column (status='active')"
DEFAULT_UPDATE="UPDATE defaults SET status = 'active' WHERE id = 1;"
run_rust "$RUST_DB" "$DEFAULT_UPDATE"
run_zig "$ZIG_DB" "$DEFAULT_UPDATE"

if compare_clocks "defaults" "UPDATE default column"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Trigger/Clock Parity Summary: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All trigger parity tests PASSED!"
    echo "Clock tables match exactly between Rust/C and Zig implementations."
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All trigger parity tests SKIPPED"
    exit 2
else
    echo "Some trigger parity tests FAILED"
    echo "Clock table divergences detected between implementations."
    exit 1
fi
