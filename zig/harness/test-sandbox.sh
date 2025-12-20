#!/usr/bin/env bash
# Sandbox Tests for Zig CR-SQLite
# Tests safety rails and basic sync invariants
#
# Reference: core/src/sandbox.test.c
#
# The C sandbox.test.c contains one test (testSandbox) that:
# 1. Creates 2 in-memory DBs with identical schema
# 2. Makes them CRRs via crsql_as_crr()
# 3. Inserts data on db1
# 4. Syncs db1 -> db2 via syncLeftToRight()
# 5. Verifies no errors
#
# This test validates the same basic sync flow works in Zig.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "=================================================================="
echo "Test Suite: Sandbox (sandbox.test.c parity)"
echo "=================================================================="
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        ARCH="aarch64"
    fi
    ZIG_EXT_PREBUILT="$ROOT_DIR/lib/crsqlite-zig-darwin-${ARCH}.dylib"
    ZIG_EXT_BUILD="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
    RUST_EXT="$ROOT_DIR/lib/crsqlite.dylib"
else
    ARCH=$(uname -m)
    ZIG_EXT_PREBUILT="$ROOT_DIR/lib/crsqlite-zig-linux-${ARCH}.so"
    ZIG_EXT_BUILD="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
    RUST_EXT="$ROOT_DIR/lib/crsqlite.so"
fi

# Try built extension first, fall back to pre-built
if [[ -f "$ZIG_EXT_BUILD" ]]; then
    ZIG_EXT="$ZIG_EXT_BUILD"
elif [[ -f "$ZIG_EXT_PREBUILT" ]]; then
    ZIG_EXT="$ZIG_EXT_PREBUILT"
else
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if nix run nixpkgs#zig -- build 2>&1; then
        ZIG_EXT="$ZIG_EXT_BUILD"
    else
        echo "FAIL: Zig build failed and no pre-built extension available"
        exit 1
    fi
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Extension not found at $ZIG_EXT"
    exit 1
fi

echo "Zig extension: $ZIG_EXT"
if [[ -f "$RUST_EXT" ]]; then
    echo "Rust/C extension: $RUST_EXT (oracle parity available)"
    HAS_ORACLE=1
else
    echo "Rust/C extension: not found (oracle parity disabled)"
    HAS_ORACLE=0
fi
echo ""

TMPDIR="${ROOT_DIR}/.tmp"
mkdir -p "$TMPDIR"
ERRFILE=$(mktemp "$TMPDIR/sandbox-err.XXXXXX")
TMPFILE=$(mktemp "$TMPDIR/sandbox-tmp.XXXXXX")
trap "rm -f $ERRFILE $TMPFILE" EXIT

PASS=0
FAIL=0
SKIP=0

# Helper to run SQL with an extension
run_sql() {
    local ext="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $ext" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL on a specific file-based DB
run_sql_file() {
    local ext="$1"
    local dbfile="$2"
    local sql="$3"
    nix run nixpkgs#sqlite -- "$dbfile" -cmd ".load $ext" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Check core function availability
echo "Checking function availability..."
SMOKE=$(run_sql "$ZIG_EXT" "SELECT crsql_as_crr('nonexistent');" 2>&1 || echo "ERROR")
if grep -q "no such function: crsql_as_crr" "$ERRFILE" 2>/dev/null; then
    echo "BLOCKED: crsql_as_crr() not implemented"
    exit 2
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Basic two-DB sync (mirrors sandbox.test.c:testSandbox)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Basic two-DB sync (testSandbox equivalent)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB1="$TMPDIR/sandbox1-$$.db"
DB2="$TMPDIR/sandbox2-$$.db"
rm -f "$DB1" "$DB2"

# Setup db1: create table, make CRR, insert
nix run nixpkgs#sqlite -- "$DB1" -cmd ".load $ZIG_EXT" "
CREATE TABLE foo (a PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1);
" 2>"$ERRFILE"

if grep -qi "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: Error setting up db1"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: db1 setup (table + CRR + insert)"
    PASS=$((PASS + 1))
fi

# Setup db2: create identical table, make CRR
nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $ZIG_EXT" "
CREATE TABLE foo (a PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('foo');
" 2>"$ERRFILE"

if grep -qi "error" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: Error setting up db2"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: db2 setup (table + CRR)"
    PASS=$((PASS + 1))
fi

# Get db2's site_id for filtering
DB2_SITE=$(run_sql_file "$ZIG_EXT" "$DB2" "SELECT quote(crsql_site_id());")

# Extract changes from db1 and apply to db2 (syncLeftToRight equivalent)
nix run nixpkgs#sqlite -- "$DB1" -cmd ".load $ZIG_EXT" "
SELECT 'CHANGE:' || 
    [table] || '|' || 
    quote(pk) || '|' || 
    cid || '|' || 
    quote(val) || '|' || 
    col_version || '|' || 
    db_version || '|' || 
    quote(site_id) || '|' || 
    cl || '|' || 
    seq
FROM crsql_changes
WHERE site_id IS NOT $DB2_SITE;
" 2>"$ERRFILE" > "$TMPFILE"

SYNC_ERROR=0
while IFS= read -r line; do
    if [[ "$line" == CHANGE:* ]]; then
        change="${line#CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $ZIG_EXT" "
            INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
            VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        " 2>"$ERRFILE"
        if grep -qi "error" "$ERRFILE" 2>/dev/null; then
            SYNC_ERROR=1
        fi
    fi
done < "$TMPFILE"

if [[ $SYNC_ERROR -eq 0 ]]; then
    echo "  PASS: Sync db1 -> db2 completed without error"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Error during sync"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
fi

# Verify db2 has the data
RESULT=$(run_sql_file "$ZIG_EXT" "$DB2" "SELECT COUNT(*) FROM foo;")
if [[ "$RESULT" == "1" ]]; then
    echo "  PASS: db2 has 1 row after sync"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 1 row in db2, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Verify the data matches
DB1_VAL=$(run_sql_file "$ZIG_EXT" "$DB1" "SELECT a FROM foo;")
DB2_VAL=$(run_sql_file "$ZIG_EXT" "$DB2" "SELECT a FROM foo;")
if [[ "$DB1_VAL" == "$DB2_VAL" ]]; then
    echo "  PASS: Data matches after sync (a=$DB1_VAL)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Data mismatch: db1=$DB1_VAL, db2=$DB2_VAL"
    FAIL=$((FAIL + 1))
fi

rm -f "$DB1" "$DB2"

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Bidirectional sync (additional safety test)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Bidirectional sync (convergence invariant)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB1="$TMPDIR/sandbox-bi1-$$.db"
DB2="$TMPDIR/sandbox-bi2-$$.db"
rm -f "$DB1" "$DB2"

# Setup both DBs with same schema
for db in "$DB1" "$DB2"; do
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "
    CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
    SELECT crsql_as_crr('foo');
    " 2>"$ERRFILE"
done

# Insert different data on each
nix run nixpkgs#sqlite -- "$DB1" -cmd ".load $ZIG_EXT" "INSERT INTO foo VALUES (1, 'from_db1');" 2>"$ERRFILE"
nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $ZIG_EXT" "INSERT INTO foo VALUES (2, 'from_db2');" 2>"$ERRFILE"

# Get site IDs
DB1_SITE=$(run_sql_file "$ZIG_EXT" "$DB1" "SELECT quote(crsql_site_id());")
DB2_SITE=$(run_sql_file "$ZIG_EXT" "$DB2" "SELECT quote(crsql_site_id());")

# Sync db1 -> db2
nix run nixpkgs#sqlite -- "$DB1" -cmd ".load $ZIG_EXT" "
SELECT 'CHANGE:' || [table] || '|' || quote(pk) || '|' || cid || '|' || quote(val) || '|' || 
       col_version || '|' || db_version || '|' || quote(site_id) || '|' || cl || '|' || seq
FROM crsql_changes WHERE site_id IS NOT $DB2_SITE;
" 2>"$ERRFILE" > "$TMPFILE"

while IFS= read -r line; do
    if [[ "$line" == CHANGE:* ]]; then
        change="${line#CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $ZIG_EXT" "
            INSERT INTO crsql_changes VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        " 2>"$ERRFILE"
    fi
done < "$TMPFILE"

# Sync db2 -> db1
nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $ZIG_EXT" "
SELECT 'CHANGE:' || [table] || '|' || quote(pk) || '|' || cid || '|' || quote(val) || '|' || 
       col_version || '|' || db_version || '|' || quote(site_id) || '|' || cl || '|' || seq
FROM crsql_changes WHERE site_id IS NOT $DB1_SITE;
" 2>"$ERRFILE" > "$TMPFILE"

while IFS= read -r line; do
    if [[ "$line" == CHANGE:* ]]; then
        change="${line#CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        nix run nixpkgs#sqlite -- "$DB1" -cmd ".load $ZIG_EXT" "
            INSERT INTO crsql_changes VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        " 2>"$ERRFILE"
    fi
done < "$TMPFILE"

# Verify both DBs converged
DB1_DATA=$(run_sql_file "$ZIG_EXT" "$DB1" "SELECT a, b FROM foo ORDER BY a;")
DB2_DATA=$(run_sql_file "$ZIG_EXT" "$DB2" "SELECT a, b FROM foo ORDER BY a;")

if [[ "$DB1_DATA" == "$DB2_DATA" ]]; then
    echo "  PASS: Both databases converged after bidirectional sync"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Databases did not converge"
    echo "    db1: $DB1_DATA"
    echo "    db2: $DB2_DATA"
    FAIL=$((FAIL + 1))
fi

# Verify both have 2 rows
COUNT1=$(run_sql_file "$ZIG_EXT" "$DB1" "SELECT COUNT(*) FROM foo;")
COUNT2=$(run_sql_file "$ZIG_EXT" "$DB2" "SELECT COUNT(*) FROM foo;")
if [[ "$COUNT1" == "2" && "$COUNT2" == "2" ]]; then
    echo "  PASS: Both databases have 2 rows"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 2 rows each, got db1=$COUNT1, db2=$COUNT2"
    FAIL=$((FAIL + 1))
fi

rm -f "$DB1" "$DB2"

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Oracle parity (if available)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Oracle parity (Zig vs Rust/C)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$HAS_ORACLE" -eq 0 ]]; then
    echo "  SKIP: Rust/C extension not available"
    SKIP=$((SKIP + 2))
else
    # Test same operations produce same final state
    SQL_SETUP="
    CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
    SELECT crsql_as_crr('foo');
    INSERT INTO foo VALUES (1, 'hello');
    INSERT INTO foo VALUES (2, 'world');
    SELECT crsql_db_version();
    "
    
    ZIG_VER=$(run_sql "$ZIG_EXT" "$SQL_SETUP")
    RUST_VER=$(run_sql "$RUST_EXT" "$SQL_SETUP")
    
    if [[ "$ZIG_VER" == "$RUST_VER" ]]; then
        echo "  PASS: db_version parity: Zig=$ZIG_VER, Rust=$RUST_VER"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: db_version divergence: Zig=$ZIG_VER, Rust=$RUST_VER"
        FAIL=$((FAIL + 1))
    fi
    
    # Test changes count parity
    SQL_CHANGES="
    CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
    SELECT crsql_as_crr('foo');
    INSERT INTO foo VALUES (1, 'hello');
    INSERT INTO foo VALUES (2, 'world');
    SELECT COUNT(*) FROM crsql_changes;
    "
    
    ZIG_COUNT=$(run_sql "$ZIG_EXT" "$SQL_CHANGES")
    RUST_COUNT=$(run_sql "$RUST_EXT" "$SQL_CHANGES")
    
    if [[ "$ZIG_COUNT" == "$RUST_COUNT" ]]; then
        echo "  PASS: changes count parity: Zig=$ZIG_COUNT, Rust=$RUST_COUNT"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: changes count divergence: Zig=$ZIG_COUNT, Rust=$RUST_COUNT"
        FAIL=$((FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=================================================================="
echo "                    SANDBOX TEST SUMMARY"
echo "=================================================================="
printf "  PASSED:  %d\n" "$PASS"
printf "  FAILED:  %d\n" "$FAIL"
printf "  SKIPPED: %d\n" "$SKIP"
echo "=================================================================="
echo ""

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All Sandbox tests PASSED"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All Sandbox tests SKIPPED"
    exit 2
else
    echo "Some Sandbox tests FAILED"
    exit 1
fi
