# TASK-149 — Refactor insertIntoPksTableAndGetPk for new pks schema

## Goal
Adapt `insertIntoPksTableAndGetPk` and related pks table insert functions to work with the new Rust/C-compatible schema where PK column values are stored directly instead of as a packed blob.

## Status
- State: active
- Priority: high (blocks sync operations)

## Context
The sync INSERT path currently fails because `insertIntoPksTableAndGetPk()` tries to insert into the old schema:

OLD SCHEMA:
```sql
INSERT INTO table__crsql_pks (base_rowid, pks) VALUES (?, ?)
```

NEW SCHEMA (no base_rowid, no pks blob):
```sql
INSERT INTO table__crsql_pks (__crsql_key, pk_col1, pk_col2, ...) VALUES (NULL, ?, ?)
-- __crsql_key is auto-increment, pk_col values come from unpacked blob
```

Triggering issue:
- `findPkFromBlob` was refactored (commit 3b9a984d) and now correctly queries new schema
- When it returns `NoRows` for non-existent entry, changes_vtab calls INSERT path
- INSERT path still uses old functions that reference `base_rowid` and `pks` columns

## Files to Modify
- `zig/src/merge_insert.zig`:
  - `insertIntoPksTable()` (line ~658)
  - `insertIntoPksTableAndGetPk()` (line ~671)
  - `TableMergeStmts.sql_insert_pks` buffer and statement (line ~135)

## Acceptance Criteria
1. `insertIntoPksTableAndGetPk()` must:
   - Unpack pk_blob into individual PK column values
   - Build dynamic INSERT with column names: `INSERT INTO pks (__crsql_key, "col1", "col2") VALUES (NULL, ?, ?)`
   - Bind unpacked values in PK order
   - Return the auto-generated `__crsql_key` via `last_insert_rowid()`
   - NOT reference `base_rowid` or `pks` columns

2. Remove `base_rowid` parameter from function signatures:
   - OLD: `insertIntoPksTableAndGetPk(db, table, base_rowid, pks_blob, len)`
   - NEW: `insertIntoPksTableAndGetPk(db, table, pks_blob, len)`

3. Update `TableMergeStmts.sql_insert_pks` to be dynamic per-table (or mark deprecated)

4. Test case passes:
   ```sql
   CREATE TABLE foo (a INT NOT NULL PRIMARY KEY, b TEXT);
   SELECT crsql_as_crr('foo');
   INSERT INTO crsql_changes VALUES ('foo', X'0901', 'b', 'hello', 1, 1, X'01...10', 1, 0);
   SELECT * FROM foo; -- row with a=1, b='hello'
   SELECT * FROM foo__crsql_pks; -- __crsql_key=1, a=1
   ```

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration - done)
- Related: commit 3b9a984d (findPkFromBlob refactor)
- Upstream: `research/zig-cr/92-gap-backlog.md` (schema compatibility)
- Blocks: TASK-154 (sync parity test fixes)

## Progress Log
- 2025-12-21: Created from TASK-147 refactoring work. Compound PK bug fixed, findPkFromBlob refactored, this is next critical blocker.
- 2025-12-21 14:30: Starting implementation. Reading existing code to understand the pattern from findPkFromBlob refactor.

## Completion Notes
(Empty until done.)
