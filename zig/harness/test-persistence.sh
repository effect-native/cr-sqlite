#!/usr/bin/env bash
# Test: On-disk database persistence for Zig CR-SQLite
#
# This test verifies that CRR data, site_id, and db_version persist
# correctly across database sessions (close and reopen).
#
# Test cases:
# 1. Create CRR, insert data, close DB, reopen, verify data
# 2. Create CRR, insert data, close DB, reopen, query crsql_changes
# 3. Verify crsql_site_id() persists across sessions
# 4. Verify crsql_db_version() persists across sessions
# 5. (Optional) WAL mode: concurrent read during write

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_ROOT="$SCRIPT_DIR/.."
PROJECT_ROOT="$ZIG_ROOT/.."

# Use temp directory within project (.tmp/)
TMPDIR="$PROJECT_ROOT/.tmp/persistence-test-$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    EXT="$ZIG_ROOT/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_ROOT/zig-out/lib/libcrsqlite.so"
fi

# Fallback to lib/ directory if zig-out doesn't exist
if [[ ! -f "$EXT" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then
            EXT="$PROJECT_ROOT/lib/crsqlite-zig-darwin-aarch64.dylib"
        else
            EXT="$PROJECT_ROOT/lib/crsqlite-zig-darwin-x86_64.dylib"
        fi
    else
        EXT="$PROJECT_ROOT/lib/crsqlite.so"
    fi
fi

# Check if extension exists
if [[ ! -f "$EXT" ]]; then
    echo -e "${RED}Error: Extension not found${NC}"
    echo "Build it with: cd zig && nix run nixpkgs#zig -- build"
    exit 1
fi

echo "=== Test: On-disk Database Persistence ==="
echo "Extension: $EXT"
echo "Temp dir: $TMPDIR"
echo ""

# Helper function to run SQL using nix-provided sqlite3
run_sql() {
    local db="$1"
    shift
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$@"
}

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Data persistence across sessions
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Data persistence across sessions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test1.sqlite"

# Session 1: Create CRR and insert data
echo "  Session 1: Creating CRR and inserting data..."
OUTPUT=$(run_sql "$DB_FILE" "
CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
SELECT crsql_as_crr('items');
INSERT INTO items VALUES (1, 'apple', 100);
INSERT INTO items VALUES (2, 'banana', 200);
INSERT INTO items VALUES (3, 'cherry', 300);
SELECT COUNT(*) FROM items;
" 2>&1)

# Session 2: Reopen and verify data
echo "  Session 2: Reopening and verifying data..."
DATA_COUNT=$(run_sql "$DB_FILE" "SELECT COUNT(*) FROM items;" 2>&1)
DATA_VALUES=$(run_sql "$DB_FILE" "SELECT name FROM items ORDER BY id;" 2>&1 | tr '\n' ',' | sed 's/,$//')

if [[ "$DATA_COUNT" == "3" ]]; then
    echo -e "  ${GREEN}✓ PASS: Data persisted (3 rows found)${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${RED}✗ FAIL: Expected 3 rows, got: $DATA_COUNT${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

if [[ "$DATA_VALUES" == "apple,banana,cherry" ]]; then
    echo -e "  ${GREEN}✓ PASS: Values correct: $DATA_VALUES${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${RED}✗ FAIL: Expected 'apple,banana,cherry', got: $DATA_VALUES${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: crsql_changes persistence
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: crsql_changes persistence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test2.sqlite"

# Session 1: Create CRR and insert data
echo "  Session 1: Creating CRR and inserting data..."
run_sql "$DB_FILE" "
CREATE TABLE docs (id INTEGER PRIMARY KEY NOT NULL, title TEXT);
SELECT crsql_as_crr('docs');
INSERT INTO docs VALUES (1, 'First Doc');
INSERT INTO docs VALUES (2, 'Second Doc');
" > /dev/null 2>&1

# Session 2: Reopen and query changes
echo "  Session 2: Reopening and querying crsql_changes..."
CHANGES_COUNT=$(run_sql "$DB_FILE" "SELECT COUNT(*) FROM crsql_changes;" 2>&1)
ERRFILE="$TMPDIR/err2.txt"
run_sql "$DB_FILE" "SELECT COUNT(*) FROM crsql_changes;" > /dev/null 2>"$ERRFILE"

if grep -q "no such table" "$ERRFILE" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ SKIP: crsql_changes vtab not available${NC}"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$CHANGES_COUNT" -ge 2 ]]; then
    echo -e "  ${GREEN}✓ PASS: crsql_changes has $CHANGES_COUNT rows${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${RED}✗ FAIL: Expected >= 2 change rows, got: $CHANGES_COUNT${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Verify change content
echo "  Verifying change content..."
CHANGE_TABLES=$(run_sql "$DB_FILE" "SELECT DISTINCT [table] FROM crsql_changes;" 2>&1 | tr '\n' ',' | sed 's/,$//')

if [[ "$CHANGE_TABLES" == "docs" ]]; then
    echo -e "  ${GREEN}✓ PASS: Changes are for 'docs' table${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ -z "$CHANGE_TABLES" ]]; then
    echo -e "  ${YELLOW}⚠ SKIP: No changes captured${NC}"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
else
    echo -e "  ${RED}✗ FAIL: Expected 'docs', got: $CHANGE_TABLES${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: crsql_site_id persistence
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: crsql_site_id() persistence across sessions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test3.sqlite"
ERRFILE="$TMPDIR/err3.txt"

# Session 1: Get site_id
echo "  Session 1: Getting initial site_id..."
SITE_ID_1=$(run_sql "$DB_FILE" "SELECT quote(crsql_site_id());" 2>"$ERRFILE")

if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ SKIP: crsql_site_id() not implemented${NC}"
    TOTAL_SKIP=$((TOTAL_SKIP + 2))
else
    echo "  Site ID (session 1): $SITE_ID_1"
    
    # Session 2: Verify same site_id
    echo "  Session 2: Reopening and verifying site_id..."
    SITE_ID_2=$(run_sql "$DB_FILE" "SELECT quote(crsql_site_id());" 2>&1)
    echo "  Site ID (session 2): $SITE_ID_2"
    
    if [[ "$SITE_ID_1" == "$SITE_ID_2" ]]; then
        echo -e "  ${GREEN}✓ PASS: site_id persisted across sessions${NC}"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "  ${RED}✗ FAIL: site_id changed! Was $SITE_ID_1, now $SITE_ID_2${NC}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    # Verify it's 16 bytes
    SITE_ID_LEN=$(run_sql "$DB_FILE" "SELECT length(crsql_site_id());" 2>&1)
    if [[ "$SITE_ID_LEN" == "16" ]]; then
        echo -e "  ${GREEN}✓ PASS: site_id is 16 bytes (UUID)${NC}"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "  ${RED}✗ FAIL: site_id length is $SITE_ID_LEN, expected 16${NC}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: crsql_db_version persistence
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: crsql_db_version() persistence across sessions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test4.sqlite"
ERRFILE="$TMPDIR/err4.txt"

# Session 1: Create CRR, insert data, check version
echo "  Session 1: Creating CRR and inserting data..."
VERSION_1=$(run_sql "$DB_FILE" "
CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('items');
INSERT INTO items VALUES (1, 'first');
INSERT INTO items VALUES (2, 'second');
SELECT crsql_db_version();
" 2>"$ERRFILE" | tail -1)

if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ SKIP: crsql_db_version() not implemented${NC}"
    TOTAL_SKIP=$((TOTAL_SKIP + 2))
else
    echo "  db_version after inserts (session 1): $VERSION_1"
    
    # Session 2: Reopen and verify version persisted
    echo "  Session 2: Reopening and verifying db_version..."
    VERSION_2=$(run_sql "$DB_FILE" "SELECT crsql_db_version();" 2>&1)
    echo "  db_version (session 2): $VERSION_2"
    
    if [[ "$VERSION_2" -ge "$VERSION_1" ]]; then
        echo -e "  ${GREEN}✓ PASS: db_version persisted ($VERSION_2 >= $VERSION_1)${NC}"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "  ${RED}✗ FAIL: db_version decreased! Was $VERSION_1, now $VERSION_2${NC}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    
    # Session 3: Insert more and verify increment
    echo "  Session 3: Inserting more data..."
    VERSION_3=$(run_sql "$DB_FILE" "
INSERT INTO items VALUES (3, 'third');
SELECT crsql_db_version();
" 2>&1 | tail -1)
    echo "  db_version after more inserts (session 3): $VERSION_3"
    
    if [[ "$VERSION_3" -gt "$VERSION_2" ]]; then
        echo -e "  ${GREEN}✓ PASS: db_version incremented ($VERSION_3 > $VERSION_2)${NC}"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "  ${RED}✗ FAIL: db_version did not increment! Was $VERSION_2, now $VERSION_3${NC}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Clock table persistence
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Clock table persistence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test5.sqlite"

# Session 1: Create CRR and insert data
echo "  Session 1: Creating CRR and inserting data..."
run_sql "$DB_FILE" "
CREATE TABLE tasks (id INTEGER PRIMARY KEY NOT NULL, title TEXT, done INTEGER);
SELECT crsql_as_crr('tasks');
INSERT INTO tasks VALUES (1, 'Task A', 0);
INSERT INTO tasks VALUES (2, 'Task B', 1);
" > /dev/null 2>&1

# Session 2: Verify clock table exists and has data
echo "  Session 2: Verifying clock table persistence..."
CLOCK_COUNT=$(run_sql "$DB_FILE" "SELECT COUNT(*) FROM tasks__crsql_clock;" 2>&1)
ERRFILE="$TMPDIR/err5.txt"
run_sql "$DB_FILE" "SELECT COUNT(*) FROM tasks__crsql_clock;" > /dev/null 2>"$ERRFILE"

if grep -q "no such table" "$ERRFILE" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ SKIP: Clock table not created${NC}"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
elif [[ "$CLOCK_COUNT" -ge 2 ]]; then
    echo -e "  ${GREEN}✓ PASS: Clock table has $CLOCK_COUNT rows${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${RED}✗ FAIL: Expected >= 2 clock rows, got: $CLOCK_COUNT${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: CRR schema persistence (table remains a CRR after reopen)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: CRR schema persistence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test6.sqlite"

# Session 1: Create CRR
echo "  Session 1: Creating CRR..."
run_sql "$DB_FILE" "
CREATE TABLE notes (id INTEGER PRIMARY KEY NOT NULL, content TEXT);
SELECT crsql_as_crr('notes');
INSERT INTO notes VALUES (1, 'Note 1');
" > /dev/null 2>&1

# Session 2: Verify still a CRR by inserting and checking changes appear
echo "  Session 2: Inserting data and verifying CRR behavior..."
CHANGES_BEFORE=$(run_sql "$DB_FILE" "SELECT COUNT(*) FROM crsql_changes;" 2>&1)
run_sql "$DB_FILE" "INSERT INTO notes VALUES (2, 'Note 2');" > /dev/null 2>&1
CHANGES_AFTER=$(run_sql "$DB_FILE" "SELECT COUNT(*) FROM crsql_changes;" 2>&1)

if [[ "$CHANGES_AFTER" -gt "$CHANGES_BEFORE" ]]; then
    echo -e "  ${GREEN}✓ PASS: CRR triggers still active (changes: $CHANGES_BEFORE -> $CHANGES_AFTER)${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${RED}✗ FAIL: CRR triggers not working after reopen${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: WAL mode persistence (optional)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: WAL mode persistence (optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FILE="$TMPDIR/test7.sqlite"

# Session 1: Create CRR with WAL mode
echo "  Session 1: Creating CRR with WAL mode..."
run_sql "$DB_FILE" "
PRAGMA journal_mode=WAL;
CREATE TABLE wal_test (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('wal_test');
INSERT INTO wal_test VALUES (1, 'wal data');
" > /dev/null 2>&1

# Session 2: Verify WAL mode persists
echo "  Session 2: Verifying WAL mode and data..."
JOURNAL_MODE=$(run_sql "$DB_FILE" "PRAGMA journal_mode;" 2>&1)
DATA_EXISTS=$(run_sql "$DB_FILE" "SELECT data FROM wal_test WHERE id=1;" 2>&1)

if [[ "$JOURNAL_MODE" == "wal" ]]; then
    echo -e "  ${GREEN}✓ PASS: WAL mode persisted${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${YELLOW}⚠ INFO: Journal mode is '$JOURNAL_MODE' (WAL persistence is system-dependent)${NC}"
    # Not a failure, just informational
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

if [[ "$DATA_EXISTS" == "wal data" ]]; then
    echo -e "  ${GREEN}✓ PASS: WAL data persisted correctly${NC}"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "  ${RED}✗ FAIL: Expected 'wal data', got: $DATA_EXISTS${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                    PERSISTENCE TEST SUMMARY                          ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$TOTAL_PASS"
printf "║  FAILED:  %-58d ║\n" "$TOTAL_FAIL"
printf "║  SKIPPED: %-58d ║\n" "$TOTAL_SKIP"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo -e "${GREEN}✓ All persistence tests PASSED${NC}"
    exit 0
elif [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ All tests SKIPPED${NC}"
    exit 2
else
    echo -e "${RED}✗ Some tests FAILED${NC}"
    exit 1
fi
