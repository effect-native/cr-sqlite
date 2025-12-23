#!/usr/bin/env bash
# Test suite for crsql_tracked_peers table
# TASK-189: Verifies the table exists and works correctly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: crsql_tracked_peers table"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Build the extension
echo "Building Zig extension..."
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo "FAIL: Zig build failed"
    exit 1
fi

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Extension not found at $ZIG_EXT"
    exit 1
fi

echo "Zig Extension: $ZIG_EXT"
echo ""

# Temp directory for test databases
TMP_DIR="$ROOT_DIR/.tmp/test-tracked-peers"
mkdir -p "$TMP_DIR"
TMPDB="$TMP_DIR/test.db"
ERRFILE=$(mktemp "$TMP_DIR/err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0

# Helper to run SQL with Zig extension
run_zig() {
    local db="$1"; shift
    nix run nixpkgs#sqlite --quiet -- "$db" -cmd ".load $ZIG_EXT" "$@" 2>"$ERRFILE" || true
}

# Helper to run SQL and get last line
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to run SQL with file db
run_sql_file() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite --quiet -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: crsql_tracked_peers table exists
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: crsql_tracked_peers table exists"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "SELECT name FROM sqlite_master WHERE type='table' AND name='crsql_tracked_peers';")
if [[ "$RESULT" == "crsql_tracked_peers" ]]; then
    echo "  PASS: crsql_tracked_peers table exists"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: crsql_tracked_peers table not found"
    echo "  Got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Schema has correct columns
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: crsql_tracked_peers has correct columns"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SCHEMA=$(nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "PRAGMA table_info(crsql_tracked_peers);" 2>/dev/null)
echo "  Schema: $SCHEMA"

HAS_SITE_ID=$(echo "$SCHEMA" | grep -c "site_id" || echo "0")
HAS_VERSION=$(echo "$SCHEMA" | grep -c "version" || echo "0")
HAS_SEQ=$(echo "$SCHEMA" | grep -c "seq" || echo "0")
HAS_TAG=$(echo "$SCHEMA" | grep -c "tag" || echo "0")
HAS_EVENT=$(echo "$SCHEMA" | grep -c "event" || echo "0")

if [[ "$HAS_SITE_ID" -ge 1 && "$HAS_VERSION" -ge 1 && "$HAS_SEQ" -ge 1 && "$HAS_TAG" -ge 1 && "$HAS_EVENT" -ge 1 ]]; then
    echo "  PASS: All expected columns present (site_id, version, seq, tag, event)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Missing columns"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Can INSERT rows
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Can INSERT into crsql_tracked_peers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 1, 0, 1, 1);
SELECT COUNT(*) FROM crsql_tracked_peers;
")

if [[ "$RESULT" == "1" ]]; then
    echo "  PASS: INSERT succeeded, count = 1"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected count 1, got: '$RESULT'"
    cat "$ERRFILE" 2>/dev/null || true
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Primary key constraint works
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Primary key constraint enforced"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Insert same primary key twice should fail
RESULT=$(nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "
INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 1, 0, 1, 1);
INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 2, 0, 1, 1);
" 2>&1 || echo "ERROR_CAUGHT")

if [[ "$RESULT" == *"UNIQUE constraint failed"* ]] || [[ "$RESULT" == *"constraint"* ]] || [[ "$RESULT" == *"ERROR"* ]]; then
    echo "  PASS: Primary key constraint enforced"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected constraint error, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Can UPDATE rows
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Can UPDATE crsql_tracked_peers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 1, 0, 1, 1);
UPDATE crsql_tracked_peers SET version = 5, seq = 10 WHERE tag = 1;
SELECT version || ',' || seq FROM crsql_tracked_peers;
")

if [[ "$RESULT" == "5,10" ]]; then
    echo "  PASS: UPDATE succeeded (version=5, seq=10)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected '5,10', got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Can DELETE rows
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Can DELETE from crsql_tracked_peers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT=$(run_sql "
INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 1, 0, 1, 1);
DELETE FROM crsql_tracked_peers WHERE tag = 1;
SELECT COUNT(*) FROM crsql_tracked_peers;
")

if [[ "$RESULT" == "0" ]]; then
    echo "  PASS: DELETE succeeded (count=0)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected count 0, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Table survives close/reopen
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Table persists across close/reopen"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

rm -f "$TMPDB"

# Insert in first connection
run_sql_file "$TMPDB" "INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 1, 0, 1, 1);"

# Read in second connection
RESULT=$(run_sql_file "$TMPDB" "SELECT COUNT(*) FROM crsql_tracked_peers;")

if [[ "$RESULT" == "1" ]]; then
    echo "  PASS: Data persists across connections (count=1)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Expected count 1, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: Oracle parity - same crsql_ tables exist
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: Oracle parity - same crsql_ tables"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ZIG_TABLES=$(nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'crsql_%' ORDER BY name;" 2>/dev/null | sort)

RUST_TABLES=$(nix run github:subtleGradient/sqlite-cr --quiet -- :memory: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'crsql_%' ORDER BY name;" 2>/dev/null | sort || echo "SKIP")

echo "  Zig tables:"
echo "$ZIG_TABLES" | sed 's/^/    /'
echo "  Rust/C tables:"
echo "$RUST_TABLES" | sed 's/^/    /'

if [[ "$RUST_TABLES" == "SKIP" ]]; then
    echo "  SKIP: Could not run Rust/C oracle"
    # Don't count as pass or fail
elif [[ "$ZIG_TABLES" == "$RUST_TABLES" ]]; then
    echo "  PASS: Tables match oracle"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Tables differ from oracle"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 9: Table is STRICT (cannot insert wrong types)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 9: Table is STRICT (type enforcement)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Try to insert a string where INTEGER is expected - STRICT tables reject this
RESULT=$(nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" "
INSERT INTO crsql_tracked_peers (site_id, version, seq, tag, event) VALUES (X'0102030405060708090a0b0c0d0e0f10', 'not_a_number', 0, 1, 1);
" 2>&1 || echo "ERROR_CAUGHT")

if [[ "$RESULT" == *"cannot store"* ]] || [[ "$RESULT" == *"datatype mismatch"* ]] || [[ "$RESULT" == *"type"* ]]; then
    echo "  PASS: STRICT table rejects wrong type for version"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: STRICT enforcement not detected, got: '$RESULT'"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
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
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "All tests PASSED"
    exit 0
else
    echo "Some tests FAILED"
    exit 1
fi
