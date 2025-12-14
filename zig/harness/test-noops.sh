#!/usr/bin/env bash
# Test: No-op changes do not advance clocks
# Validates CRDT property from core/src/crsqlite.test.c:noopsDoNotMoveClocks()
#
# This test verifies that applying identical changes (same values, same versions)
# via crsql_changes does NOT advance db_version. This prevents clock drift on
# redundant syncs - a critical CRDT property.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: No-op Clock Stability (crsqlite.test.c:noopsDoNotMoveClocks)"
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
ERRFILE=$(mktemp "$TMPDIR/noop-err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

PASS=0
FAIL=0

run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Test 1: Verify db_version advances on insert
echo "Test: db_version advances on insert"
RESULT=$(run_sql "
CREATE TABLE hoot (a, b PRIMARY KEY NOT NULL, c);
SELECT crsql_as_crr('hoot');
INSERT INTO hoot VALUES (1, 1, 1);
SELECT crsql_db_version();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    echo ""
    echo "All noop tests SKIPPED (functions not implemented)"
    exit 2
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: db_version = 1 after insert"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version = 1, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Test 2: Applying identical change via crsql_changes does NOT advance db_version
# This is the core noop test - same value, same col_version should be a no-op
echo "Test: Identical change via crsql_changes does not advance db_version"
RESULT=$(run_sql "
CREATE TABLE hoot (a, b PRIMARY KEY NOT NULL, c);
SELECT crsql_as_crr('hoot');
-- Make local change
INSERT INTO hoot VALUES (1, 1, 1);
-- Get the current db_version (should be 1)
-- Now apply an 'incoming' change with identical value and same col_version
-- This simulates a sync where the remote has the same state
-- The key: col_version=1 matches local, value=1 matches local
-- This should be detected as a no-op and NOT increment db_version
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('hoot', X'010901', 'a', 1, 1, 1, X'00000000000000000000000000000001', 1, 0);
SELECT crsql_db_version();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: db_version unchanged at 1 (no-op detected)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version = 1 (unchanged), got: $RESULT"
    echo "        Clock drifted on redundant sync!"
    FAIL=$((FAIL + 1))
fi

# Test 3: Different value DOES advance db_version (control test)
echo "Test: Different value via crsql_changes DOES advance db_version"
RESULT=$(run_sql "
CREATE TABLE hoot (a, b PRIMARY KEY NOT NULL, c);
SELECT crsql_as_crr('hoot');
INSERT INTO hoot VALUES (1, 1, 1);
-- Apply incoming change with DIFFERENT value and higher col_version
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('hoot', X'010901', 'a', 999, 2, 2, X'00000000000000000000000000000001', 1, 0);
SELECT crsql_db_version();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: db_version advanced to 2 (real change applied)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version = 2, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Test 4: Same value but lower col_version is also a no-op (loses conflict)
echo "Test: Same value with lower col_version does not advance db_version"
RESULT=$(run_sql "
CREATE TABLE hoot (a, b PRIMARY KEY NOT NULL, c);
SELECT crsql_as_crr('hoot');
INSERT INTO hoot VALUES (1, 1, 1);
UPDATE hoot SET a = 2 WHERE b = 1;
UPDATE hoot SET a = 3 WHERE b = 1;
-- Local col_version is now 3 for column 'a'
-- Apply incoming change with lower col_version (should lose and be no-op)
INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('hoot', X'010901', 'a', 999, 1, 1, X'00000000000000000000000000000001', 1, 0);
SELECT crsql_db_version();
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
elif grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: db_version unchanged at 3 (lower version lost conflict)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version = 3 (unchanged), got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "No-op Tests Summary: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All noop tests passed!"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All noop tests SKIPPED (functions not implemented)"
    exit 2
else
    echo "Some noop tests FAILED"
    exit 1
fi
