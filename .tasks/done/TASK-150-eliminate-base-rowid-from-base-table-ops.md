# TASK-150 — Eliminate base_rowid dependency from base table operations

## Goal
Refactor all merge_insert.zig functions that operate on the base table to use PK column values from the pks table instead of relying on a stored `base_rowid` column (which no longer exists in the new schema).

## Status
- State: done (superseded)
- Priority: was high (blocks sync UPDATE/DELETE operations)

## Context
Multiple functions in merge_insert.zig follow this pattern:
1. Given `pk` (__crsql_key from pks table)
2. Look up `base_rowid` from pks table: `SELECT base_rowid FROM pks WHERE pk = ?`
3. Operate on base table using rowid: `UPDATE table SET col = ? WHERE rowid = base_rowid`

This breaks with new schema because:
- The pks table has no `base_rowid` column
- Instead, it has PK column values directly: `(__crsql_key, pk_col1, pk_col2, ...)`
- Base table operations must use PK columns: `UPDATE table SET col = ? WHERE pk_col1 = ? AND pk_col2 = ?`

Affected functions discovered in Round 49 (TASK-119) and Round 58:
- `getBaseRowidFromPk()` - entire function obsolete
- `updateBaseTableColumn()` - uses getBaseRowidFromPk
- `deleteFromBaseTable()` - uses getBaseRowidFromPk
- `rowExistsInBaseTable()` - uses getBaseRowidFromPk
- Cached variants: `*Cached()` versions of above

## Files to Modify
- `zig/src/merge_insert.zig`:
  - `getBaseRowidFromPk()` (line ~385) - DELETE or convert to `getPkValuesFromKey()`
  - `updateBaseTableColumn()` (line ~250)
  - `deleteFromBaseTable()` (line ~415)
  - `rowExistsInBaseTable()` (line ~457)
  - `updateBaseTableColumnCached()` (line ~TBD)
  - `deleteFromBaseTableCached()` (line ~985)
  - `rowExistsInBaseTableCached()` (line ~968)
  - `TableMergeStmts` cached statement buffers (line ~74-78)

## Acceptance Criteria
1. NEW helper function `getPkValuesFromKey()`:
   ```zig
   fn getPkValuesFromKey(db, table_name, __crsql_key, allocator) ![]codec.Value
   // SELECT pk_col1, pk_col2, ... FROM table__crsql_pks WHERE __crsql_key = ?
   // Returns unpacked PK column values in order
   ```

2. `updateBaseTableColumn()` refactored:
   - Call `getPkValuesFromKey(__crsql_key)` to get PK values
   - Build SQL: `UPDATE table SET col = ? WHERE "pk1" = ? AND "pk2" = ?`
   - Bind column value + all PK values
   - Remove all references to `base_rowid`

3. `deleteFromBaseTable()` refactored:
   - Get PK values from pks table
   - Build SQL: `DELETE FROM table WHERE "pk1" = ? AND "pk2" = ?`
   - Remove pks tombstoning logic (handled by clock table in new schema)

4. `rowExistsInBaseTable()` refactored:
   - Get PK values from pks table
   - Build SQL: `SELECT 1 FROM table WHERE "pk1" = ? AND "pk2" = ? LIMIT 1`

5. Test compound PK update:
   ```sql
   CREATE TABLE foo(a INT NOT NULL, b INT NOT NULL, c TEXT, PRIMARY KEY(a,b));
   SELECT crsql_as_crr('foo');
   -- Sync insert row
   INSERT INTO crsql_changes VALUES ('foo', X'090109 02', 'c', 'hello', 1, 1, X'01...', 1, 0);
   -- Sync update column
   INSERT INTO crsql_changes VALUES ('foo', X'0901
0902', 'c', 'world', 2, 2, X'01...', 2, 0);
   SELECT c FROM foo WHERE a=1 AND b=2; -- 'world'
   ```

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration)
- Related: TASK-119 (Round 49 - similar bug with pk vs base_rowid confusion)
- Depends on: TASK-149 (insertIntoPksTableAndGetPk must work first for INSERT path)
- Upstream: `research/zig-cr/92-gap-backlog.md`
- Blocks: TASK-154 (sync parity tests)

## Progress Log
- 2025-12-21: Created from TASK-147 work. Root cause identified: base_rowid column no longer exists, need to query PK values from pks and use in WHERE clauses.

## Completion Notes
- 2025-12-21: **SUPERSEDED by TASK-157**
- The work described in this task was completed as part of TASK-157 (rows_impacted fix).
- All base table operations now use pk directly as rowid (simpler approach than originally planned).
- Tests pass: rows_impacted 18/18, cross-open 24/24, ALTER 6/6.
