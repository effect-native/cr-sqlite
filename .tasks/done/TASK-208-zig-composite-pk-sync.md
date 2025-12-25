# TASK-208 — Zig: Fix INSERT INTO crsql_changes for Composite Primary Keys

## Goal
Fix the Zig implementation to support sync for tables with composite primary keys.

## Status
- State: DONE
- Priority: MEDIUM (blocks inventory-style apps with Zig)
- Discovered: 2025-12-25 (TASK-205 analysis)
- Completed: 2025-12-25

## Problem

The Zig implementation fails when applying changes via `INSERT INTO crsql_changes` for tables with composite primary keys:

```sql
-- This works (single column PK):
CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO crsql_changes (...) VALUES (...);  -- OK

-- This fails (composite PK):
CREATE TABLE stock (sku TEXT, location TEXT, qty INTEGER, PRIMARY KEY (sku, location));
INSERT INTO crsql_changes (...) VALUES (...);  -- Error: SQL logic error
```

## Root Cause

TASK-202 fixed single-column PK sync, but the fix only handles single PK values. The merge insert functions in Zig need to be updated to:

1. Detect composite PKs (multiple columns in PK)
2. Decode all PK column values from the pk blob
3. Build proper WHERE clauses with all PK columns
4. Bind all PK values with correct types

## Files to Modify

- `zig/src/merge_insert.zig` — Update merge functions to handle composite PKs
- `zig/src/changes_vtab.zig` — Update change application for composite PKs

## Acceptance Criteria

1. [x] `bash zig/harness/test-app-inventory.sh` shows Zig PASS (not XFAIL)
2. [x] Composite INTEGER,INTEGER PK works
3. [x] Composite TEXT,TEXT PK works
4. [x] Composite TEXT,INTEGER,TEXT PK works
5. [x] Existing single PK tests continue to pass

## Test Cases

```bash
# Quick composite PK test:
cd /Users/tom/Developer/effect-native/cr-sqlite
TMPDIR=".tmp/test-composite-pk-$$"
mkdir -p "$TMPDIR"
ZIG_EXT="zig/zig-out/lib/libcrsqlite.dylib"

# Create and populate
nix run nixpkgs#sqlite -- "$TMPDIR/a.db" -cmd ".load $ZIG_EXT" "
CREATE TABLE t (a TEXT, b TEXT, val INTEGER, PRIMARY KEY (a,b));
SELECT crsql_as_crr('t');
INSERT INTO t VALUES ('x','y',100);
SELECT quote(pk), quote(site_id) FROM crsql_changes;
"

# Try to sync
PK=X'...'  # from above
SITE=X'...'  # from above
nix run nixpkgs#sqlite -- "$TMPDIR/b.db" -cmd ".load $ZIG_EXT" "
CREATE TABLE t (a TEXT, b TEXT, val INTEGER, PRIMARY KEY (a,b));
SELECT crsql_as_crr('t');
INSERT INTO crsql_changes VALUES ('t', $PK, 'val', 100, 1, 1, $SITE, 1, 1);
SELECT * FROM t;  -- Should show: x|y|100
"

rm -rf "$TMPDIR"
```

## Parent Docs / Cross-links

- Related: `.tasks/done/TASK-202-fix-crsql-changes-insert-failure.md` (single PK fix)
- Related: `.tasks/done/TASK-205-fix-inventory-app-test.md` (documents xfail)
- Test: `zig/harness/test-app-inventory.sh`

## Progress Log
- 2025-12-25: Created from TASK-205 analysis.
- 2025-12-25: Implemented composite PK support in merge_insert.zig.

## Completion Notes

**Changes Made:**

Added composite primary key support to `zig/src/merge_insert.zig`:

1. **New helper function `buildCompositePkWhereClause`**: Builds WHERE clauses using tuple comparison with subquery:
   ```sql
   WHERE ("col1", "col2") = (SELECT "col1", "col2" FROM "table__crsql_pks" WHERE __crsql_key = ?)
   ```

2. **Updated `rowExistsInBaseTable`**: Now checks for composite PKs when `getPkColumnName` returns null and uses the composite WHERE clause builder.

3. **Updated `deleteFromBaseTable`**: Same pattern - handles composite PKs with tuple comparison.

4. **Updated `updateBaseTableColumn`**: Same pattern - handles composite PKs with tuple comparison.

5. **Updated `insertRowForSentinelResurrection`**: For composite PKs, builds INSERT ... SELECT with all PK columns from the pks table.

6. **Updated `insertRowForResurrection`**: For composite PKs, queries all PK values from pks table and binds them all to the INSERT statement.

7. **Updated `insertOrUpdateColumn`**: Decodes all PK values from pk blob and builds INSERT with all PK columns.

8. **Updated `insertPkOnlyRow`**: Same pattern - handles composite PKs for PK-only tables.

9. **Added helper functions `bindValue` and `bindValueAtIndex`**: Extract common value binding logic.

**Test Results:**
- `test-app-inventory.sh`: All 4 tests PASS (was XFAIL)
- `test-app-todo.sh`: All tests PASS (regression check)
- `test-app-chat.sh`: All tests PASS (regression check)
