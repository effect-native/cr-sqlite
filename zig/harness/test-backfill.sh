#!/usr/bin/env bash
# Test: Backfill behavior when crsql_as_crr() is called on tables with existing data
#
# When a table already has rows BEFORE being converted to a CRR, backfill must
# create clock entries for all existing rows. This test validates:
# 1. Empty table → no backfill needed (baseline)
# 2. Table with 1 row → 1 clock entry created
# 3. Table with N rows → N clock entries created
# 4. Backfilled rows have col_version=1, db_version=1
# 5. crsql_changes vtab returns backfilled data
# 6. Re-applying crsql_as_crr() does not create duplicates
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Backfill Verification (crsql_as_crr on existing data)"
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
ERRFILE=$(mktemp "$TMPDIR/backfill-err.XXXXXX")
trap "rm -f $ERRFILE" EXIT

PASS=0
FAIL=0

run_sql() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_sql_all() {
    local sql="$1"
    nix run nixpkgs#sqlite -- :memory: -cmd ".load $LIB" "$sql" 2>"$ERRFILE" || true
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Empty table baseline (no backfill needed)
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 1: crsql_as_crr() on empty table (baseline)"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
SELECT crsql_as_crr('items');
SELECT COUNT(*) FROM items__crsql_clock;
")
if grep -q "no such function" "$ERRFILE" 2>/dev/null; then
    echo "  SKIP: Required functions not implemented"
    echo ""
    echo "All backfill tests SKIPPED (functions not implemented)"
    exit 2
elif grep -q "no such table" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: Clock table not created"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "0" ]]; then
    echo "  PASS: Empty table has 0 clock entries"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 0 clock entries, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Single row backfill
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 2: crsql_as_crr() on table with 1 row"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
SELECT crsql_as_crr('items');
SELECT COUNT(*) FROM items__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: 1 row backfilled → 1 clock entry"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 1 clock entry, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Multiple rows backfill
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 3: crsql_as_crr() on table with 5 rows"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
INSERT INTO items VALUES (2, 'banana');
INSERT INTO items VALUES (3, 'cherry');
INSERT INTO items VALUES (4, 'date');
INSERT INTO items VALUES (5, 'elderberry');
SELECT crsql_as_crr('items');
SELECT COUNT(*) FROM items__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "5" ]]; then
    echo "  PASS: 5 rows backfilled → 5 clock entries"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 5 clock entries, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Verify col_version = 1 for backfilled rows
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 4: Backfilled rows have col_version = 1"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
INSERT INTO items VALUES (2, 'banana');
SELECT crsql_as_crr('items');
SELECT MIN(col_version), MAX(col_version) FROM items__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1|1" ]]; then
    echo "  PASS: All backfilled rows have col_version = 1"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected col_version 1|1, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Verify db_version = 1 for backfilled rows
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 5: Backfilled rows have db_version = 1"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
INSERT INTO items VALUES (2, 'banana');
SELECT crsql_as_crr('items');
SELECT MIN(db_version), MAX(db_version) FROM items__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1|1" ]]; then
    echo "  PASS: All backfilled rows have db_version = 1"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version 1|1, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Verify crsql_changes vtab returns backfilled data
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 6: crsql_changes returns backfilled rows"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
INSERT INTO items VALUES (2, 'banana');
SELECT crsql_as_crr('items');
SELECT COUNT(*) FROM crsql_changes WHERE \"table\" = 'items';
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: crsql_changes returns 2 backfilled changes"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 2 changes in crsql_changes, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Verify backfill values match original data
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 7: Backfilled values in crsql_changes match original data"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
SELECT crsql_as_crr('items');
SELECT val FROM crsql_changes WHERE \"table\" = 'items' AND cid = 'name';
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "apple" ]]; then
    echo "  PASS: Backfilled value matches original ('apple')"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 'apple', got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: Re-applying crsql_as_crr() does not create duplicates
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 8: Re-applying crsql_as_crr() does not create duplicates"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
INSERT INTO items VALUES (2, 'banana');
SELECT crsql_as_crr('items');
SELECT crsql_as_crr('items');
SELECT crsql_as_crr('items');
SELECT COUNT(*) FROM items__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: Clock table still has exactly 2 entries after re-apply"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 2 clock entries (no duplicates), got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 9: Backfill with multiple columns (non-PK)
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 9: Backfill with multiple non-PK columns"
RESULT=$(run_sql "
CREATE TABLE products (id PRIMARY KEY NOT NULL, name, price, qty);
INSERT INTO products VALUES (1, 'apple', 1.50, 100);
SELECT crsql_as_crr('products');
SELECT COUNT(*) FROM products__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
# Should be 3 clock entries: one per non-PK column (name, price, qty)
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: 1 row with 3 non-PK columns → 3 clock entries"
    PASS=$((PASS + 1))
elif [[ "$RESULT" == "1" ]]; then
    # Alternative: some implementations use 1 clock entry per row
    echo "  PASS: 1 row → 1 clock entry (row-level tracking)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 3 (or 1) clock entries, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 10: Verify crsql_db_version() after backfill
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 10: crsql_db_version() is 1 after backfill"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
INSERT INTO items VALUES (2, 'banana');
SELECT crsql_as_crr('items');
SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "1" ]]; then
    echo "  PASS: db_version = 1 after backfill"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version = 1, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 11: Backfill then insert new row increments db_version
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 11: Insert after backfill increments db_version to 2"
RESULT=$(run_sql "
CREATE TABLE items (id PRIMARY KEY NOT NULL, name);
INSERT INTO items VALUES (1, 'apple');
SELECT crsql_as_crr('items');
INSERT INTO items VALUES (2, 'banana');
SELECT crsql_db_version();
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "2" ]]; then
    echo "  PASS: db_version = 2 after backfill + new insert"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected db_version = 2, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 12: Compound primary key backfill
# ═══════════════════════════════════════════════════════════════════════════
echo "Test 12: Backfill with compound primary key"
RESULT=$(run_sql "
CREATE TABLE order_items (order_id NOT NULL, item_id NOT NULL, qty, PRIMARY KEY (order_id, item_id));
INSERT INTO order_items VALUES (1, 100, 5);
INSERT INTO order_items VALUES (1, 101, 3);
INSERT INTO order_items VALUES (2, 100, 7);
SELECT crsql_as_crr('order_items');
SELECT COUNT(*) FROM order_items__crsql_clock;
")
if grep -q "Error:" "$ERRFILE" 2>/dev/null; then
    echo "  FAIL: SQL error occurred"
    cat "$ERRFILE"
    FAIL=$((FAIL + 1))
elif [[ "$RESULT" == "3" ]]; then
    echo "  PASS: 3 rows with compound PK → 3 clock entries"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 3 clock entries, got: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Backfill Tests Summary: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "All backfill tests passed!"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All backfill tests SKIPPED (functions not implemented)"
    exit 2
else
    echo "Some backfill tests FAILED"
    exit 1
fi
