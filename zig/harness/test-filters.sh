#!/usr/bin/env bash
# Filter Tests for Zig CR-SQLite crsql_changes virtual table
# Tests filter pushdown as defined in changes-vtab.test.c:testFilters()
#
# This validates:
# 1. db_version > N filter
# 2. site_id IS NULL / IS NOT NULL filters
# 3. site_id = / != / IS / IS NOT crsql_site_id() filters
# 4. Compound filters (AND, OR)
# 5. Range filters (db_version >= X AND db_version < Y)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig CR-SQLite Filter Tests ==="
echo "Source: changes-vtab.test.c:testFilters()"
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
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$EXT" ]]; then
    echo "FAIL: Extension not found at $EXT"
    exit 1
fi

echo "Extension: $EXT"
echo ""

TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $TMPFILE $ERRFILE" EXIT

FAILURES=0

# Helper to run SQL and get result (returns last line of output)
run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

# Helper to check for blocking errors
check_blocked() {
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function: crsql_as_crr" "$ERRFILE"; then
            echo "BLOCKED: crsql_as_crr() not yet implemented"
            exit 2
        fi
        if grep -q "no such table: crsql_changes" "$ERRFILE"; then
            echo "BLOCKED: crsql_changes virtual table not yet implemented"
            exit 2
        fi
    fi
}

# Setup: Create table with 3 rows
SETUP_SQL="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 2);
INSERT INTO foo VALUES (2, 3);
INSERT INTO foo VALUES (3, 4);
"

echo "=== Test 1: No filters (baseline count) ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes;")
check_blocked

# Should have 3 changes (one per column 'b' for each row)
if [[ "$RESULT" == "3" ]]; then
    echo "PASS: No filters - got 3 changes"
else
    echo "FAIL: No filters - expected 3 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 2: site_id IS NULL filter ==="
echo ""

# Local changes have site_id = crsql_site_id(), not NULL
# So site_id IS NULL should return 0
RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE site_id IS NULL;")
check_blocked

if [[ "$RESULT" == "0" ]]; then
    echo "PASS: site_id IS NULL - got 0 changes (all are local)"
else
    echo "FAIL: site_id IS NULL - expected 0 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 3: site_id IS NOT NULL filter ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE site_id IS NOT NULL;")
check_blocked

if [[ "$RESULT" == "3" ]]; then
    echo "PASS: site_id IS NOT NULL - got 3 changes"
else
    echo "FAIL: site_id IS NOT NULL - expected 3 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 4: site_id = crsql_site_id() filter ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE site_id = crsql_site_id();")
check_blocked

if [[ "$RESULT" == "3" ]]; then
    echo "PASS: site_id = crsql_site_id() - got 3 changes (all local)"
else
    echo "FAIL: site_id = crsql_site_id() - expected 3 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 5: site_id != crsql_site_id() filter ==="
echo ""

# Per ANSI SQL, NULL != anything is never true, so this returns 0
# (even though site_id is not NULL for local changes)
RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE site_id != crsql_site_id();")
check_blocked

if [[ "$RESULT" == "0" ]]; then
    echo "PASS: site_id != crsql_site_id() - got 0 (ANSI SQL NULL semantics)"
else
    echo "FAIL: site_id != crsql_site_id() - expected 0, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 6: site_id IS crsql_site_id() filter ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE site_id IS crsql_site_id();")
check_blocked

if [[ "$RESULT" == "3" ]]; then
    echo "PASS: site_id IS crsql_site_id() - got 3 changes"
else
    echo "FAIL: site_id IS crsql_site_id() - expected 3 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 7: site_id IS NOT crsql_site_id() filter ==="
echo "Source: crsqlite.test.c:testPullingOnlyLocalChanges()"
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE site_id IS NOT crsql_site_id();")
check_blocked

if [[ "$RESULT" == "0" ]]; then
    echo "PASS: site_id IS NOT crsql_site_id() - got 0 (no remote changes)"
else
    echo "FAIL: site_id IS NOT crsql_site_id() - expected 0, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 8: db_version range filter (>= 1 AND < 2) ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE db_version >= 1 AND db_version < 2;")
check_blocked

if [[ "$RESULT" == "1" ]]; then
    echo "PASS: db_version >= 1 AND < 2 - got 1 change"
else
    echo "FAIL: db_version >= 1 AND < 2 - expected 1 change, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 9: db_version > 0 filter ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE db_version > 0;")
check_blocked

if [[ "$RESULT" == "3" ]]; then
    echo "PASS: db_version > 0 - got 3 changes"
else
    echo "FAIL: db_version > 0 - expected 3 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 10: db_version > 2 filter ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE db_version > 2;")
check_blocked

if [[ "$RESULT" == "1" ]]; then
    echo "PASS: db_version > 2 - got 1 change"
else
    echo "FAIL: db_version > 2 - expected 1 change, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 11: OR condition filter ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE db_version > 2 OR site_id IS crsql_site_id();")
check_blocked

if [[ "$RESULT" == "3" ]]; then
    echo "PASS: OR condition - got 3 changes"
else
    echo "FAIL: OR condition - expected 3 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 12: Compound AND filter (version + site_id) ==="
echo ""

RESULT=$(run_sql "$SETUP_SQL SELECT COUNT(*) FROM crsql_changes WHERE db_version > 1 AND site_id IS crsql_site_id();")
check_blocked

if [[ "$RESULT" == "2" ]]; then
    echo "PASS: db_version > 1 AND site_id IS crsql_site_id() - got 2 changes"
else
    echo "FAIL: Compound AND filter - expected 2 changes, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Summary ==="
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "All filter tests PASSED"
    exit 0
else
    echo "$FAILURES test(s) FAILED"
    exit 1
fi
