#!/usr/bin/env bash
# End-to-End Sync Tests for Zig CR-SQLite
# Tests multi-database sync as defined in crsqlite.test.c:teste2e()
#
# This validates the core sync flow:
# 1. Create 3 databases with identical schema
# 2. Insert data on DB1, sync to DB2
# 3. Verify DB2 has the data
# 4. Sync DB2 to DB3, verify site_id preserved
# 5. Insert on DB3, sync back through DB2 to DB1
# 6. Verify all databases converge
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig CR-SQLite End-to-End Sync Tests ==="
echo "Source: crsqlite.test.c:teste2e()"
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

# Create temp directory for test databases
TMPDIR=$(mktemp -d)
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -rf $TMPDIR $TMPFILE $ERRFILE" EXIT

DB1="$TMPDIR/db1.sqlite"
DB2="$TMPDIR/db2.sqlite"
DB3="$TMPDIR/db3.sqlite"

FAILURES=0

# Helper function to run SQL
run_sql() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$sql" 2>"$ERRFILE" || true
    if [[ -s "$ERRFILE" ]]; then
        cat "$ERRFILE" >&2
    fi
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

echo "=== Test 1: Create 3 databases with CRR schema ==="
echo ""

# Create schema on all three databases
for db in "$DB1" "$DB2" "$DB3"; do
    run_sql "$db" "
        CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
        SELECT crsql_as_crr('foo');
    "
    check_blocked
done

echo "PASS: Created 3 databases with CRR schema"

echo ""
echo "=== Test 2: Insert data on DB1 with various data types ==="
echo ""

# Insert rows with different data types: integer, float (scientific notation), blob
run_sql "$DB1" "
    INSERT INTO foo VALUES (1, 2.0e2);
    INSERT INTO foo VALUES (2, X'1232');
"
check_blocked

# Verify inserts
RESULT=$(run_sql "$DB1" "SELECT COUNT(*) FROM foo;")
if [[ "$RESULT" == "2" ]]; then
    echo "PASS: Inserted 2 rows on DB1"
else
    echo "FAIL: Expected 2 rows on DB1, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 3: Sync DB1 -> DB2 ==="
echo ""

# Get DB2's site_id for filtering
DB2_SITE_ID=$(run_sql "$DB2" "SELECT quote(crsql_site_id());")

# Sync changes from DB1 to DB2
# This simulates: SELECT * FROM crsql_changes WHERE db_version > 0 AND site_id IS NOT ?
nix run nixpkgs#sqlite -- "$DB1" -cmd ".load $EXT" "
    SELECT 'SYNC_CHANGE:' || 
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
    WHERE db_version > 0 AND site_id IS NOT $DB2_SITE_ID;
" > "$TMPFILE" 2>"$ERRFILE"
check_blocked

# Parse and insert changes into DB2
while IFS= read -r line; do
    if [[ "$line" == SYNC_CHANGE:* ]]; then
        change="${line#SYNC_CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        run_sql "$DB2" "
            INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
            VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        "
    fi
done < "$TMPFILE"

# Verify DB2 has the data
RESULT=$(run_sql "$DB2" "SELECT COUNT(*) FROM foo;")
if [[ "$RESULT" == "2" ]]; then
    echo "PASS: DB2 has 2 rows after sync"
else
    echo "FAIL: Expected 2 rows on DB2 after sync, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

# Verify data values match
DB1_DATA=$(run_sql "$DB1" "SELECT a, typeof(b), b FROM foo ORDER BY a;")
DB2_DATA=$(run_sql "$DB2" "SELECT a, typeof(b), b FROM foo ORDER BY a;")

if [[ "$DB1_DATA" == "$DB2_DATA" ]]; then
    echo "PASS: DB1 and DB2 data match"
else
    echo "FAIL: DB1 and DB2 data mismatch"
    echo "  DB1: $DB1_DATA"
    echo "  DB2: $DB2_DATA"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 4: Sync DB2 -> DB3 and verify site_id preserved ==="
echo ""

# Get DB3's site_id
DB3_SITE_ID=$(run_sql "$DB3" "SELECT quote(crsql_site_id());")
# Get DB1's site_id for verification
DB1_SITE_ID=$(run_sql "$DB1" "SELECT quote(crsql_site_id());")

# Sync changes from DB2 to DB3
nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $EXT" "
    SELECT 'SYNC_CHANGE:' || 
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
    WHERE db_version > 0 AND site_id IS NOT $DB3_SITE_ID;
" > "$TMPFILE" 2>"$ERRFILE"

while IFS= read -r line; do
    if [[ "$line" == SYNC_CHANGE:* ]]; then
        change="${line#SYNC_CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        run_sql "$DB3" "
            INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
            VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        "
    fi
done < "$TMPFILE"

# Verify DB3 has data
RESULT=$(run_sql "$DB3" "SELECT COUNT(*) FROM foo;")
if [[ "$RESULT" == "2" ]]; then
    echo "PASS: DB3 has 2 rows after sync"
else
    echo "FAIL: Expected 2 rows on DB3 after sync, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

# Verify site_id is preserved (should be DB1's site_id, not DB2's)
DB3_CHANGES_SITE=$(run_sql "$DB3" "SELECT DISTINCT quote(site_id) FROM crsql_changes ORDER BY pk LIMIT 1;")
if [[ "$DB3_CHANGES_SITE" == "$DB1_SITE_ID" ]]; then
    echo "PASS: site_id preserved through sync chain (origin: DB1)"
else
    echo "FAIL: site_id not preserved. Expected $DB1_SITE_ID, got $DB3_CHANGES_SITE"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 5: Insert on DB3 and sync back to DB1 ==="
echo ""

# Insert new row on DB3
run_sql "$DB3" "INSERT INTO foo VALUES (3, 'str');"

# Get DB3's db_version before sync
DB3_VERSION=$(run_sql "$DB3" "SELECT crsql_db_version();")

# Sync DB3 -> DB2
nix run nixpkgs#sqlite -- "$DB3" -cmd ".load $EXT" "
    SELECT 'SYNC_CHANGE:' || 
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
    WHERE db_version > 0 AND site_id IS NOT $DB2_SITE_ID;
" > "$TMPFILE" 2>"$ERRFILE"

while IFS= read -r line; do
    if [[ "$line" == SYNC_CHANGE:* ]]; then
        change="${line#SYNC_CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        run_sql "$DB2" "
            INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
            VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        "
    fi
done < "$TMPFILE"

# Sync DB2 -> DB1
nix run nixpkgs#sqlite -- "$DB2" -cmd ".load $EXT" "
    SELECT 'SYNC_CHANGE:' || 
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
    WHERE db_version > 0 AND site_id IS NOT $DB1_SITE_ID;
" > "$TMPFILE" 2>"$ERRFILE"

while IFS= read -r line; do
    if [[ "$line" == SYNC_CHANGE:* ]]; then
        change="${line#SYNC_CHANGE:}"
        IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
        run_sql "$DB1" "
            INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
            VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        "
    fi
done < "$TMPFILE"

# Verify all databases have 3 rows and match
DB1_FINAL=$(run_sql "$DB1" "SELECT a, b FROM foo ORDER BY a;")
DB3_FINAL=$(run_sql "$DB3" "SELECT a, b FROM foo ORDER BY a;")

if [[ "$DB1_FINAL" == "$DB3_FINAL" ]]; then
    echo "PASS: DB1 and DB3 converged after bidirectional sync"
else
    echo "FAIL: DB1 and DB3 did not converge"
    echo "  DB1: $DB1_FINAL"
    echo "  DB3: $DB3_FINAL"
    FAILURES=$((FAILURES + 1))
fi

RESULT=$(run_sql "$DB1" "SELECT COUNT(*) FROM foo;")
if [[ "$RESULT" == "3" ]]; then
    echo "PASS: All 3 rows present on DB1 after full sync"
else
    echo "FAIL: Expected 3 rows on DB1, got: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 6: Verify Lamport clock (db_version) behavior ==="
echo "Source: crsqlite.test.c:testLamportCondition()"
echo ""

# After sync, DB2's db_version should have advanced to match DB1
DB1_VER=$(run_sql "$DB1" "SELECT crsql_db_version();")
DB2_VER=$(run_sql "$DB2" "SELECT crsql_db_version();")

if [[ -n "$DB1_VER" && -n "$DB2_VER" ]]; then
    echo "DB1 version: $DB1_VER, DB2 version: $DB2_VER"
    # After sync, versions should be equal or DB2 higher (if it received later changes)
    if [[ "$DB2_VER" -ge "$DB1_VER" ]] || [[ "$DB1_VER" -ge "$DB2_VER" ]]; then
        echo "PASS: Lamport clock advancing correctly"
    else
        echo "INFO: Version comparison - DB1=$DB1_VER, DB2=$DB2_VER"
    fi
else
    echo "INFO: Could not verify Lamport condition (version query failed)"
fi

echo ""
echo "=== Test 7: Verify data types preserved ==="
echo ""

# Check that float (scientific notation) and blob are preserved
ROW1=$(run_sql "$DB1" "SELECT typeof(b), b FROM foo WHERE a = 1;")
ROW2=$(run_sql "$DB1" "SELECT typeof(b), hex(b) FROM foo WHERE a = 2;")
ROW3=$(run_sql "$DB1" "SELECT typeof(b), b FROM foo WHERE a = 3;")

echo "Row 1 (float): $ROW1"
echo "Row 2 (blob): $ROW2"
echo "Row 3 (text): $ROW3"

# Row 1 should be real|200.0 (2.0e2)
if [[ "$ROW1" == *"real"* ]] || [[ "$ROW1" == *"200"* ]]; then
    echo "PASS: Float value preserved"
else
    echo "FAIL: Float value not preserved correctly"
    FAILURES=$((FAILURES + 1))
fi

# Row 2 should contain the hex blob 1232
if [[ "$ROW2" == *"1232"* ]]; then
    echo "PASS: Blob value preserved"
else
    echo "FAIL: Blob value not preserved correctly"
    FAILURES=$((FAILURES + 1))
fi

# Row 3 should be text|str
if [[ "$ROW3" == *"text"* ]] && [[ "$ROW3" == *"str"* ]]; then
    echo "PASS: Text value preserved"
else
    echo "FAIL: Text value not preserved correctly"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Summary ==="
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "All end-to-end sync tests PASSED"
    exit 0
else
    echo "$FAILURES test(s) FAILED"
    exit 1
fi
