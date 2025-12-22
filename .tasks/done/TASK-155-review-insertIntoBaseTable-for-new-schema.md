# TASK-155 — Review insertIntoBaseTable for new schema compatibility

## Goal
Verify that `insertIntoBaseTable()` in merge_insert.zig works correctly with the new pks schema, or identify and fix any issues with base table row insertion during sync.

## Status
- State: done (superseded)
- Priority: high (part of sync INSERT path)

## Context
Current parity test failures show "insertIntoBaseTable issue" errors. This function is called by changes_vtab.zig when a remote change arrives for a row that doesn't exist locally yet.

Current call pattern in changes_vtab.zig (~line 1700):
```zig
if (find_pk_result returns NoRows) {
    // Row doesn't exist, need to INSERT
    const base_rowid = merge_insert.insertIntoBaseTable(...) catch {
        log.debug("insertIntoBaseTable failed");
        return SQLITE_ERROR;
    };
    const pks_pk = merge_insert.insertIntoPksTableAndGetPk(
        db, table, base_rowid, pk_blob, pk_len
    ) catch ...;
}
```

Potential issues:
1. `insertIntoBaseTable` might return a rowid that's no longer meaningful
   - NEW: rowid is still meaningful for SQLite's internal table access
   - But it should NOT be stored in pks table (TASK-149)

2. Function might try to set PK column values incorrectly
   - Need to unpack pk_blob and insert those values into the base table
   - SQL: `INSERT INTO table (pk_col1, pk_col2, ...) VALUES (?, ?, ...)`

3. Function might not exist or have wrong signature
   - Need to verify current implementation

## Files to Modify
(To be determined after reading current implementation)
- Likely: `zig/src/merge_insert.zig` - `insertIntoBaseTable()`
- Likely: `zig/src/changes_vtab.zig` - caller may need adjustment

## Acceptance Criteria
1. Read current `insertIntoBaseTable()` implementation:
   - Locate function in merge_insert.zig
   - Document current signature and behavior
   - Identify if it properly unpacks pk_blob for PK columns

2. Verify correct INSERT SQL generation:
   - Must unpack pk_blob into individual PK values
   - Must generate: `INSERT INTO table (pk1, pk2) VALUES (?, ?)`
   - Returns SQLite rowid (for internal use, NOT for pks table storage)

3. Update caller in changes_vtab.zig:
   - Capture rowid only if needed for immediate use
   - Do NOT pass rowid to insertIntoPksTableAndGetPk (TASK-149 removes param)

4. Test basic sync insert:
   ```sql
   CREATE TABLE foo(a INT PRIMARY KEY, b TEXT);
   SELECT crsql_as_crr('foo');
   INSERT INTO crsql_changes VALUES ('foo', X'0905', 'b', 'test', 1, 1, X'01...', 1, 0);
   SELECT * FROM foo; -- (5, 'test')
   ```

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration)
- Related: TASK-149 (insertIntoPksTableAndGetPk refactor - receives rowid from this function)
- Related: TASK-150 (base table ops - this is an INSERT, those are UPDATE/DELETE)
- Blocks: TASK-154 (sync parity tests)
- Upstream: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-21: Created from TASK-147 work. "insertIntoBaseTable issue" appears in test failures, needs investigation to confirm if it's a real bug or cascading failure from other refactoring.

## Completion Notes
(Empty until done.)

## Completion Notes
- 2025-12-21: **SUPERSEDED by TASK-157**
- insertIntoBaseTable was reviewed and fixed as part of TASK-157.
- The function now correctly uses the new pks schema.
- Tests pass: rows_impacted 18/18, cross-open 24/24, ALTER 6/6.
