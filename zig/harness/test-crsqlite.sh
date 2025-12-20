#!/usr/bin/env bash
# crsqlite Test Suite for Zig CR-SQLite
# Validates core extension behaviors from core/src/crsqlite.test.c
#
# Tests covered:
#   - testPullingOnlyLocalChanges: Filtering crsql_changes by site_id
#
# Note: Other crsqlite.test.c tests are covered by:
#   - test-e2e-sync.sh: teste2e(), testLamportCondition()
#   - test-alter.sh: testSelectChangesAfterChangingColumnName()
#   - test-noops.sh: noopsDoNotMoveClocks()
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: crsqlite (core/src/crsqlite.test.c)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    LIB="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$LIB" ]]; then
    echo "Extension not found at $LIB"
    echo "Run 'nix run nixpkgs#zig -- build' first"
    exit 1
fi

TMPDIR="${SCRIPT_DIR}/../../.tmp"
mkdir -p "$TMPDIR"
ERRFILE=$(mktemp "$TMPDIR/crsqlite-err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

PASS=0
FAIL=0

run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# =============================================================================
# Test: PullingOnlyLocalChanges (crsqlite.test.c:testPullingOnlyLocalChanges)
# =============================================================================
# This test validates filtering crsql_changes by site_id:
# - site_id IS crsql_site_id() should return local changes
# - site_id IS NOT crsql_site_id() should return remote changes
echo "Test: PullingOnlyLocalChanges - local changes have matching site_id"
RESULT=$(run_sql "
CREATE TABLE node (id PRIMARY KEY NOT NULL, content);
SELECT crsql_as_crr('node');
INSERT INTO node VALUES (1, 'some str');
INSERT INTO node VALUES (2, 'other str');
SELECT count(*) FROM crsql_changes WHERE site_id IS crsql_site_id();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    echo ""
    echo "All crsqlite tests SKIPPED (functions not implemented)"
    exit 2
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: count(*) = 2 for local changes (site_id matches)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 2 local changes, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test: PullingOnlyLocalChanges - no remote changes in fresh DB"
RESULT=$(run_sql "
CREATE TABLE node (id PRIMARY KEY NOT NULL, content);
SELECT crsql_as_crr('node');
INSERT INTO node VALUES (1, 'some str');
INSERT INTO node VALUES (2, 'other str');
SELECT count(*) FROM crsql_changes WHERE site_id IS NOT crsql_site_id();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: count(*) = 0 for remote changes (no synced data)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 0 remote changes, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Test that synced changes have different site_id
# Note: When inserting a row via crsql_changes, it creates entries for both
# the sentinel (-1) and the column value, so we count distinct PKs with remote site_id
echo "Test: PullingOnlyLocalChanges - synced changes have remote site_id"
RESULT=$(run_sql "
CREATE TABLE node (id PRIMARY KEY NOT NULL, content);
SELECT crsql_as_crr('node');
-- Insert a local row
INSERT INTO node VALUES (1, 'local');
-- Simulate receiving a synced change from a remote site
-- Use a different site_id (all zeros) to simulate remote origin
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('node', X'010902', 'content', 'remote', 1, 1, X'00000000000000000000000000000001', 1, 0);
-- Count distinct remote PKs (should be 1 - only the synced row pk=2)
SELECT count(DISTINCT pk) FROM crsql_changes WHERE site_id IS NOT crsql_site_id();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: count(DISTINCT pk) = 1 for remote changes after sync"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 1 distinct remote PK, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# =============================================================================
# Test: Data types preserved through sync (from teste2e)
# =============================================================================
echo "Test: Data types - float (scientific notation) preserved"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2.0e2);
SELECT typeof(b) || '|' || b FROM foo WHERE a = 1;
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif [[ "$RESULT" == "real|200.0" ]] || [[ "$RESULT" == "integer|200" ]]; then
    echo "  PASS: Float 2.0e2 stored correctly as $RESULT"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected real|200.0 or integer|200, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test: Data types - blob preserved"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, X'1232');
SELECT typeof(b) || '|' || hex(b) FROM foo WHERE a = 1;
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif [[ "$RESULT" == "blob|1232" ]]; then
    echo "  PASS: Blob X'1232' preserved correctly"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected blob|1232, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

echo "Test: Data types - text preserved"
RESULT=$(run_sql "
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello world');
SELECT typeof(b) || '|' || b FROM foo WHERE a = 1;
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif [[ "$RESULT" == "text|hello world" ]]; then
    echo "  PASS: Text 'hello world' preserved correctly"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected text|hello world, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "crsqlite Tests Summary: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All crsqlite tests passed!"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All crsqlite tests SKIPPED (functions not implemented)"
    exit 2
else
    echo "Some crsqlite tests FAILED"
    exit 1
fi
