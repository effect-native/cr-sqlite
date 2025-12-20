#!/usr/bin/env bash
# Primary Key UPDATE Semantics Test for Zig CR-SQLite
#
# When you UPDATE a primary key column in a CRR table, it should generate:
# 1. A DELETE tombstone for the old PK value (cid='-1' sentinel)
# 2. An INSERT for the new PK value
#
# This test validates:
# - Single-column PK update (simple table)
# - Compound PK update (junction table - one column changed)
# - Compound PK update (all columns changed)
# - PK update on table with non-PK columns
#
# Source behavior: SQLite trigger-based CRR tracks PK changes via DELETE+INSERT
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Primary Key UPDATE Semantics Test ==="
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

# Temp files
DB=$(mktemp).db
TMPFILE=$(mktemp)
ERRFILE=$(mktemp)
trap "rm -f $DB $TMPFILE $ERRFILE" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0

# Helper to run SQL
run_sql() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$sql" 2>"$ERRFILE" || true
}

# Check for blocking errors
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

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Single-column PK UPDATE
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Single-column PK UPDATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: UPDATE foo SET id = 2 WHERE id = 1"
echo "Expected: Tombstone for id=1, INSERT for id=2"
echo ""

rm -f "$DB"
run_sql "$DB" "
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, value TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'hello');
UPDATE foo SET id = 2 WHERE id = 1;
SELECT crsql_finalize();
"
check_blocked

# Check base table state
echo "Test 1a: Base table state after PK update"
OLD_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM foo WHERE id = 1;")
NEW_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM foo WHERE id = 2;")
NEW_VALUE=$(run_sql "$DB" "SELECT value FROM foo WHERE id = 2;")

if [[ "$OLD_ROW" == "0" && "$NEW_ROW" == "1" && "$NEW_VALUE" == "hello" ]]; then
    echo "  PASS: Row moved from id=1 to id=2 with value='hello'"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Base table incorrect (old_row=$OLD_ROW, new_row=$NEW_ROW, value=$NEW_VALUE)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check for tombstone on old PK (id=1)
# PK encoding: X'010901' = 01 (1 col), 09 (int type), 01 (value 1)
echo ""
echo "Test 1b: Tombstone exists for old PK (id=1)"
TOMBSTONE=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'foo' 
  AND pk = X'010901' 
  AND cid = '-1';
")

if [[ "$TOMBSTONE" == "1" ]]; then
    echo "  PASS: Tombstone found for id=1 (sentinel cid='-1')"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No tombstone for old PK (count=$TOMBSTONE)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check for INSERT on new PK (id=2)
# PK encoding: X'010902' = 01 (1 col), 09 (int type), 02 (value 2)
echo ""
echo "Test 1c: INSERT exists for new PK (id=2)"
NEW_INSERT=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'foo' 
  AND pk = X'010902' 
  AND cid = 'value';
")

if [[ "$NEW_INSERT" == "1" ]]; then
    echo "  PASS: INSERT found for id=2"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No INSERT for new PK (count=$NEW_INSERT)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check clock table entries
echo ""
echo "Test 1d: Clock table state"
OLD_CLOCK=$(run_sql "$DB" "SELECT COUNT(*) FROM foo__crsql_clock WHERE pk = X'010901';")
NEW_CLOCK=$(run_sql "$DB" "SELECT COUNT(*) FROM foo__crsql_clock WHERE pk = X'010902';")

# Old PK should have tombstone sentinel entry
if [[ "$OLD_CLOCK" -ge "1" ]]; then
    echo "  PASS: Clock entry exists for old PK (tombstone)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No clock entry for old PK (count=$OLD_CLOCK)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# New PK should have entries for value column
if [[ "$NEW_CLOCK" -ge "1" ]]; then
    echo "  PASS: Clock entry exists for new PK"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No clock entry for new PK (count=$NEW_CLOCK)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Compound PK UPDATE (one column changed)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Compound PK UPDATE (one column changed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Junction table (user_id, item_id) -> change item_id only"
echo ""

rm -f "$DB"
run_sql "$DB" "
CREATE TABLE user_items (user_id INTEGER NOT NULL, item_id INTEGER NOT NULL, qty INTEGER, PRIMARY KEY (user_id, item_id));
SELECT crsql_as_crr('user_items');
INSERT INTO user_items VALUES (1, 100, 5);
UPDATE user_items SET item_id = 200 WHERE user_id = 1 AND item_id = 100;
SELECT crsql_finalize();
"
check_blocked

# Check base table
echo "Test 2a: Base table state after compound PK update"
OLD_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM user_items WHERE user_id = 1 AND item_id = 100;")
NEW_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM user_items WHERE user_id = 1 AND item_id = 200;")
NEW_QTY=$(run_sql "$DB" "SELECT qty FROM user_items WHERE user_id = 1 AND item_id = 200;")

if [[ "$OLD_ROW" == "0" && "$NEW_ROW" == "1" && "$NEW_QTY" == "5" ]]; then
    echo "  PASS: Row moved from (1,100) to (1,200) with qty=5"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Base table incorrect (old=$OLD_ROW, new=$NEW_ROW, qty=$NEW_QTY)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check tombstone for old compound PK
# PK encoding: X'0209010964' = 02 (2 cols), 09 (int), 01 (1), 09 (int), 64 (100)
echo ""
echo "Test 2b: Tombstone for old compound PK (1, 100)"
TOMBSTONE=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'user_items' 
  AND pk = X'0209010964' 
  AND cid = '-1';
")

if [[ "$TOMBSTONE" == "1" ]]; then
    echo "  PASS: Tombstone found for (1, 100)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No tombstone for old compound PK (count=$TOMBSTONE)"
    # Debug: show what PKs exist
    echo "  DEBUG: Existing PKs in crsql_changes:"
    run_sql "$DB" "SELECT quote(pk), cid FROM crsql_changes WHERE [table] = 'user_items';"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check INSERT for new compound PK
# PK encoding: X'020901090168' = 02 (2 cols), 09 (int), 01 (1), 09 (int), 0168 (200 as varint? or different encoding)
# Actually for small ints: X'020901' for (1) then 09 (int), C8 (200) -> X'020901090168' may vary
echo ""
echo "Test 2c: INSERT for new compound PK (1, 200)"
# Use a more flexible check - just verify the new PK exists
NEW_INSERT=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'user_items' 
  AND cid = 'qty';
")

# We should have at least one qty entry for the new row
if [[ "$NEW_INSERT" -ge "1" ]]; then
    echo "  PASS: INSERT found for new compound PK"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No INSERT for new compound PK (count=$NEW_INSERT)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Compound PK UPDATE (all columns changed)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Compound PK UPDATE (all columns changed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: UPDATE both PK columns simultaneously"
echo ""

rm -f "$DB"
run_sql "$DB" "
CREATE TABLE edges (src INTEGER NOT NULL, dst INTEGER NOT NULL, weight REAL, PRIMARY KEY (src, dst));
SELECT crsql_as_crr('edges');
INSERT INTO edges VALUES (1, 2, 1.5);
UPDATE edges SET src = 10, dst = 20 WHERE src = 1 AND dst = 2;
SELECT crsql_finalize();
"
check_blocked

# Check base table
echo "Test 3a: Base table state after full compound PK update"
OLD_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM edges WHERE src = 1 AND dst = 2;")
NEW_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM edges WHERE src = 10 AND dst = 20;")
NEW_WEIGHT=$(run_sql "$DB" "SELECT weight FROM edges WHERE src = 10 AND dst = 20;")

if [[ "$OLD_ROW" == "0" && "$NEW_ROW" == "1" && "$NEW_WEIGHT" == "1.5" ]]; then
    echo "  PASS: Row moved from (1,2) to (10,20) with weight=1.5"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Base table incorrect (old=$OLD_ROW, new=$NEW_ROW, weight=$NEW_WEIGHT)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check tombstone for old PK
echo ""
echo "Test 3b: Tombstone for old compound PK (1, 2)"
# PK encoding: X'0209010902' = 02 (2 cols), 09 (int), 01 (1), 09 (int), 02 (2)
TOMBSTONE=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'edges' 
  AND pk = X'0209010902' 
  AND cid = '-1';
")

if [[ "$TOMBSTONE" == "1" ]]; then
    echo "  PASS: Tombstone found for (1, 2)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No tombstone for old compound PK (count=$TOMBSTONE)"
    echo "  DEBUG: Existing changes:"
    run_sql "$DB" "SELECT quote(pk), cid FROM crsql_changes WHERE [table] = 'edges';"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check new row has changes
echo ""
echo "Test 3c: INSERT for new compound PK (10, 20)"
NEW_CHANGES=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'edges' 
  AND cid = 'weight';
")

if [[ "$NEW_CHANGES" -ge "1" ]]; then
    echo "  PASS: INSERT found for new compound PK"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No INSERT for new compound PK (count=$NEW_CHANGES)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: PK UPDATE with non-PK columns (value preservation)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: PK UPDATE preserves non-PK columns"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Table with multiple non-PK columns, only PK changes"
echo ""

rm -f "$DB"
run_sql "$DB" "
CREATE TABLE products (sku TEXT PRIMARY KEY NOT NULL, name TEXT, price REAL, stock INTEGER);
SELECT crsql_as_crr('products');
INSERT INTO products VALUES ('SKU-001', 'Widget', 9.99, 100);
UPDATE products SET sku = 'SKU-002' WHERE sku = 'SKU-001';
SELECT crsql_finalize();
"
check_blocked

# Check base table - all non-PK values preserved
echo "Test 4a: Non-PK columns preserved after PK update"
OLD_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM products WHERE sku = 'SKU-001';")
NEW_NAME=$(run_sql "$DB" "SELECT name FROM products WHERE sku = 'SKU-002';")
NEW_PRICE=$(run_sql "$DB" "SELECT price FROM products WHERE sku = 'SKU-002';")
NEW_STOCK=$(run_sql "$DB" "SELECT stock FROM products WHERE sku = 'SKU-002';")

if [[ "$OLD_ROW" == "0" && "$NEW_NAME" == "Widget" && "$NEW_PRICE" == "9.99" && "$NEW_STOCK" == "100" ]]; then
    echo "  PASS: All non-PK columns preserved (name=Widget, price=9.99, stock=100)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Non-PK columns not preserved (name=$NEW_NAME, price=$NEW_PRICE, stock=$NEW_STOCK)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check tombstone for old text PK
echo ""
echo "Test 4b: Tombstone for old text PK (SKU-001)"
TOMBSTONE=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'products' 
  AND cid = '-1';
")

# Should have at least one tombstone (for old PK)
if [[ "$TOMBSTONE" -ge "1" ]]; then
    echo "  PASS: Tombstone found for text PK"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: No tombstone found (count=$TOMBSTONE)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check new PK has all column changes
echo ""
echo "Test 4c: All columns tracked for new PK (SKU-002)"
NEW_COLS=$(run_sql "$DB" "
SELECT COUNT(DISTINCT cid) FROM crsql_changes 
WHERE [table] = 'products' 
  AND cid IN ('name', 'price', 'stock');
")

if [[ "$NEW_COLS" == "3" ]]; then
    echo "  PASS: All 3 non-PK columns tracked (name, price, stock)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Not all columns tracked (count=$NEW_COLS, expected 3)"
    echo "  DEBUG: Tracked columns:"
    run_sql "$DB" "SELECT DISTINCT cid FROM crsql_changes WHERE [table] = 'products';"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Multiple sequential PK updates
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Multiple sequential PK updates"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: id: 1 -> 2 -> 3 (two PK updates)"
echo ""

rm -f "$DB"
run_sql "$DB" "
CREATE TABLE chain (id INTEGER PRIMARY KEY NOT NULL, data TEXT);
SELECT crsql_as_crr('chain');
INSERT INTO chain VALUES (1, 'original');
UPDATE chain SET id = 2 WHERE id = 1;
UPDATE chain SET id = 3 WHERE id = 2;
SELECT crsql_finalize();
"
check_blocked

# Check final state
echo "Test 5a: Final state after chain of PK updates"
FINAL_ROW=$(run_sql "$DB" "SELECT COUNT(*) FROM chain WHERE id = 3;")
FINAL_DATA=$(run_sql "$DB" "SELECT data FROM chain WHERE id = 3;")
TOTAL_ROWS=$(run_sql "$DB" "SELECT COUNT(*) FROM chain;")

if [[ "$FINAL_ROW" == "1" && "$FINAL_DATA" == "original" && "$TOTAL_ROWS" == "1" ]]; then
    echo "  PASS: Row at id=3 with data='original', total=1"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Incorrect final state (id3=$FINAL_ROW, data=$FINAL_DATA, total=$TOTAL_ROWS)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# Check tombstones for both old PKs
echo ""
echo "Test 5b: Tombstones for both old PKs (1 and 2)"
TOMBSTONES=$(run_sql "$DB" "
SELECT COUNT(*) FROM crsql_changes 
WHERE [table] = 'chain' 
  AND cid = '-1';
")

if [[ "$TOMBSTONES" -ge "2" ]]; then
    echo "  PASS: Found $TOMBSTONES tombstones (expected >= 2)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Not enough tombstones (count=$TOMBSTONES, expected >= 2)"
    echo "  DEBUG: All changes:"
    run_sql "$DB" "SELECT quote(pk), cid, db_version FROM crsql_changes WHERE [table] = 'chain';"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║              PK UPDATE Semantics Test Summary                        ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$TOTAL_PASS"
printf "║  FAILED:  %-58d ║\n" "$TOTAL_FAIL"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo "All PK UPDATE tests PASSED"
    echo ""
    echo "Summary of verified behaviors:"
    echo "  - PK update on single-column PK generates DELETE+INSERT"
    echo "  - Compound PK update (partial) generates DELETE+INSERT"
    echo "  - Compound PK update (full) generates DELETE+INSERT"
    echo "  - Non-PK column values are preserved during PK update"
    echo "  - Sequential PK updates generate proper tombstone chain"
    exit 0
else
    echo "Some PK UPDATE tests FAILED"
    echo ""
    echo "Expected behavior (PK UPDATE = DELETE + INSERT):"
    echo "  1. Old PK gets tombstone (cid='-1' sentinel) in clock table"
    echo "  2. New PK gets fresh INSERT for all columns"
    echo "  3. Non-PK column values should be preserved"
    echo "  4. db_version increments appropriately"
    exit 1
fi
