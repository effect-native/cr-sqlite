#!/usr/bin/env bash
# Edge Case Tests for Zig CR-SQLite (Oracle Parity)
#
# This test file contains deterministic regression tests for edge cases
# discovered by fuzzing (TASK-127). These tests verify Zig implementation
# matches Rust/C oracle behavior for tricky value types.
#
# Test categories:
# 1. Empty blob handling (X'')
# 2. Empty string vs empty blob distinction
# 3. NULL vs empty blob vs empty string
#
# Context: TASK-128 (create tests), TASK-129 (fix implementation)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Edge Case Parity Tests (Zig vs Rust/C Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "These tests verify edge cases discovered by fuzzing in TASK-127."
echo "They should FAIL until TASK-129 fixes the implementation."
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

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/edge-cases-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0

ERRFILE="$TMPDIR/error.txt"

# Helper to run SQL with Zig extension
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Helper to run SQL with Rust/C extension
run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
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

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Empty blob via INSERT
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Empty blob via INSERT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reproduction: INSERT INTO t VALUES (1, X'');"
echo "Expected: crsql_changes reports X'' (empty blob), not NULL"
echo ""

DB_ZIG_1="$TMPDIR/test1_zig.db"
DB_RUST_1="$TMPDIR/test1_rust.db"

# Run same SQL on both implementations
SQL_1="
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('t') WHERE 0;
INSERT INTO t VALUES (1, X'');
SELECT quote(val) FROM crsql_changes WHERE [table]='t' AND cid='data';
"

ZIG_RESULT_1=$(run_zig "$DB_ZIG_1" "$SQL_1")
RUST_RESULT_1=$(run_rust "$DB_RUST_1" "$SQL_1")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_1" == "$RUST_RESULT_1" ]]; then
    echo "  PASS: Empty blob via INSERT"
    echo "    Both return: $ZIG_RESULT_1"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty blob via INSERT diverges"
    echo "    Zig returns:    '$ZIG_RESULT_1'"
    echo "    Oracle returns: '$RUST_RESULT_1'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Empty blob via UPDATE
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Empty blob via UPDATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reproduction: INSERT non-empty blob, then UPDATE to X''"
echo "Expected: crsql_changes reports X'' after UPDATE, not NULL"
echo ""

DB_ZIG_2="$TMPDIR/test2_zig.db"
DB_RUST_2="$TMPDIR/test2_rust.db"

SQL_2="
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('t') WHERE 0;
INSERT INTO t VALUES (2, X'1234');
UPDATE t SET data = X'' WHERE id = 2;
SELECT quote(val) FROM crsql_changes WHERE [table]='t' AND cid='data' ORDER BY db_version DESC LIMIT 1;
"

ZIG_RESULT_2=$(run_zig "$DB_ZIG_2" "$SQL_2")
RUST_RESULT_2=$(run_rust "$DB_RUST_2" "$SQL_2")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_2" == "$RUST_RESULT_2" ]]; then
    echo "  PASS: Empty blob via UPDATE"
    echo "    Both return: $ZIG_RESULT_2"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty blob via UPDATE diverges"
    echo "    Zig returns:    '$ZIG_RESULT_2'"
    echo "    Oracle returns: '$RUST_RESULT_2'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Empty string vs empty blob distinction
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Empty string vs empty blob distinction"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reproduction: INSERT both '' (empty string) and X'' (empty blob)"
echo "Expected: txt column shows '' (quoted empty string), blb shows X'' (empty blob)"
echo ""

DB_ZIG_3="$TMPDIR/test3_zig.db"
DB_RUST_3="$TMPDIR/test3_rust.db"

SQL_3="
CREATE TABLE t2 (id INTEGER PRIMARY KEY NOT NULL, txt TEXT, blb BLOB);
SELECT crsql_as_crr('t2') WHERE 0;
INSERT INTO t2 VALUES (1, '', X'');
SELECT cid, quote(val) FROM crsql_changes WHERE [table]='t2' AND cid IN ('txt', 'blb') ORDER BY cid;
"

ZIG_RESULT_3=$(run_zig "$DB_ZIG_3" "$SQL_3")
RUST_RESULT_3=$(run_rust "$DB_RUST_3" "$SQL_3")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_3" == "$RUST_RESULT_3" ]]; then
    echo "  PASS: Empty string vs empty blob distinction"
    echo "    Both return:"
    echo "$ZIG_RESULT_3" | sed 's/^/      /'
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty string vs empty blob distinction diverges"
    echo "    Zig returns:"
    echo "$ZIG_RESULT_3" | sed 's/^/      /'
    echo "    Oracle returns:"
    echo "$RUST_RESULT_3" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: NULL vs empty blob vs empty string (triple distinction)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: NULL vs empty blob vs empty string"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reproduction: Multiple rows with NULL, '', X'' in different columns"
echo "Expected: crsql_changes distinguishes all three cases correctly"
echo ""

DB_ZIG_4="$TMPDIR/test4_zig.db"
DB_RUST_4="$TMPDIR/test4_rust.db"

SQL_4="
CREATE TABLE t2 (id INTEGER PRIMARY KEY NOT NULL, txt TEXT, blb BLOB);
SELECT crsql_as_crr('t2');
INSERT INTO t2 VALUES (2, NULL, NULL);
INSERT INTO t2 VALUES (3, '', X'');
SELECT pk, cid, quote(val) FROM crsql_changes 
WHERE [table]='t2' AND cid IN ('txt', 'blb') 
ORDER BY pk, cid;
"

ZIG_RESULT_4=$(run_zig "$DB_ZIG_4" "$SQL_4")
RUST_RESULT_4=$(run_rust "$DB_RUST_4" "$SQL_4")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_4" == "$RUST_RESULT_4" ]]; then
    echo "  PASS: NULL vs empty blob vs empty string"
    echo "    Both return:"
    echo "$ZIG_RESULT_4" | sed 's/^/      /'
    PASS=$((PASS + 1))
else
    echo "  FAIL: NULL vs empty blob vs empty string diverges"
    echo "    Zig returns:"
    echo "$ZIG_RESULT_4" | sed 's/^/      /'
    echo "    Oracle returns:"
    echo "$RUST_RESULT_4" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 5: Empty blob sync round-trip
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Empty blob sync round-trip (Zig -> Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reproduction: Zig INSERT empty blob, extract changes, apply to Oracle"
echo "Expected: Oracle receives X'' not NULL"
echo ""

DB_ZIG_5="$TMPDIR/test5_zig.db"
DB_RUST_5="$TMPDIR/test5_rust.db"

# Create table in both DBs
SQL_SETUP_5="
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('t');
"

run_zig "$DB_ZIG_5" "$SQL_SETUP_5"
run_rust "$DB_RUST_5" "$SQL_SETUP_5"

# Insert empty blob in Zig
run_zig "$DB_ZIG_5" "INSERT INTO t VALUES (1, X'');"

# Extract the change record from Zig
ZIG_CHANGE=$(run_zig "$DB_ZIG_5" "
SELECT [table], hex(pk), cid, quote(val), col_version, db_version, hex(site_id), cl, seq 
FROM crsql_changes WHERE [table]='t' AND cid='data';
")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
else
    # Parse the change and apply to Oracle
    # Format: table|hex_pk|cid|quoted_val|col_ver|db_ver|hex_site|cl|seq
    TABLE=$(echo "$ZIG_CHANGE" | cut -d'|' -f1)
    HEX_PK=$(echo "$ZIG_CHANGE" | cut -d'|' -f2)
    CID=$(echo "$ZIG_CHANGE" | cut -d'|' -f3)
    QUOTED_VAL=$(echo "$ZIG_CHANGE" | cut -d'|' -f4)
    COL_VER=$(echo "$ZIG_CHANGE" | cut -d'|' -f5)
    DB_VER=$(echo "$ZIG_CHANGE" | cut -d'|' -f6)
    HEX_SITE=$(echo "$ZIG_CHANGE" | cut -d'|' -f7)
    CL=$(echo "$ZIG_CHANGE" | cut -d'|' -f8)
    SEQ=$(echo "$ZIG_CHANGE" | cut -d'|' -f9)
    
    # Apply to Oracle
    run_rust "$DB_RUST_5" "
    INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
    VALUES ('$TABLE', X'$HEX_PK', '$CID', $QUOTED_VAL, $COL_VER, $DB_VER, X'$HEX_SITE', $CL, $SEQ);
    "
    
    # Check what Oracle received
    RUST_FINAL=$(run_rust "$DB_RUST_5" "SELECT quote(data) FROM t WHERE id=1;")
    
    if [[ "$RUST_FINAL" == "X''" ]]; then
        echo "  PASS: Empty blob synced correctly to Oracle"
        echo "    Oracle received: $RUST_FINAL"
        PASS=$((PASS + 1))
    elif [[ "$RUST_FINAL" == "NULL" ]]; then
        echo "  FAIL: Empty blob lost during sync (converted to NULL)"
        echo "    Zig change val: $QUOTED_VAL"
        echo "    Oracle received: $RUST_FINAL"
        FAIL=$((FAIL + 1))
    else
        echo "  FAIL: Unexpected value after sync"
        echo "    Zig change val: $QUOTED_VAL"
        echo "    Oracle received: $RUST_FINAL"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 6: typeof() verification for empty values
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: typeof() verification for empty values"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reproduction: Check typeof(val) in crsql_changes for empty values"
echo "Expected: X'' has typeof='blob', '' has typeof='text', NULL has typeof='null'"
echo ""

DB_ZIG_6="$TMPDIR/test6_zig.db"
DB_RUST_6="$TMPDIR/test6_rust.db"

SQL_6="
CREATE TABLE t3 (id INTEGER PRIMARY KEY NOT NULL, v1 BLOB, v2 TEXT, v3 BLOB);
SELECT crsql_as_crr('t3');
INSERT INTO t3 VALUES (1, X'', '', NULL);
SELECT cid, typeof(val), quote(val) FROM crsql_changes 
WHERE [table]='t3' AND cid IN ('v1', 'v2', 'v3') 
ORDER BY cid;
"

ZIG_RESULT_6=$(run_zig "$DB_ZIG_6" "$SQL_6")
RUST_RESULT_6=$(run_rust "$DB_RUST_6" "$SQL_6")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_6" == "$RUST_RESULT_6" ]]; then
    echo "  PASS: typeof() verification matches"
    echo "    Both return:"
    echo "$ZIG_RESULT_6" | sed 's/^/      /'
    PASS=$((PASS + 1))
else
    echo "  FAIL: typeof() verification diverges"
    echo "    Zig returns:"
    echo "$ZIG_RESULT_6" | sed 's/^/      /'
    echo "    Oracle returns:"
    echo "$RUST_RESULT_6" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Edge Case Parity Test Summary"
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
    echo "RED PHASE: $FAIL test(s) failing as expected"
    echo ""
    echo "These failures are expected until TASK-129 fixes the Zig implementation."
    echo "The primary bug: empty blobs (X'') are incorrectly reported as NULL."
    echo ""
    echo "Fix required in: zig/src/changes_vtab.zig or zig/src/triggers.zig"
    exit 1
fi

echo "All edge case parity tests PASSED"
exit 0
