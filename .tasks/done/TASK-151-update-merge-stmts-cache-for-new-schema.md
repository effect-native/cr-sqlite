# TASK-151 — Update TableMergeStmts cached statement variants for new schema

## Goal
Refactor the `TableMergeStmts` statement cache and all `*Cached()` function variants to work with the new pks schema (no base_rowid, no pks blob, PK columns stored directly).

## Status
- State: done (superseded)
- Priority: was medium (performance optimization)

## Context
`TableMergeStmts` provides per-table statement caching to avoid thousands of prepare/finalize cycles during sync. For a 1000-change sync, this reduces ~4000+ prepares to ~4 per table (significant perf win).

Current cached statements affected by schema change:
```zig
struct TableMergeStmts {
    find_pk_stmt: ?*sqlite3_stmt = null,        // SELECT pk FROM pks WHERE pks = ?
    row_exists_base_stmt: ?*sqlite3_stmt = null, // SELECT 1 FROM table WHERE rowid = ?
    delete_base_stmt: ?*sqlite3_stmt = null,     // DELETE FROM table WHERE rowid = ?
    // ... others
    sql_find_pk: [512]u8,     // SQL buffer for find_pk
    sql_insert_pks: [1024]u8, // SQL buffer for insert_pks
}
```

Problem: These SQL buffers and statements are built once per table and expect old schema (pks blob, base_rowid). They need dynamic construction per PK column count.

## Files to Modify
- `zig/src/merge_insert.zig`:
  - `TableMergeStmts` struct definition (line ~51)
  - `TableMergeStmts.init()` (line ~100)
  - `findPkFromBlobCached()` (line ~947)
  - `rowExistsInBaseTableCached()` (line ~968)
  - `deleteFromBaseTableCached()` (line ~985)
  - `updateBaseTableColumnCached()` (if exists)

## Acceptance Criteria
1. Option A (simple): Mark cached variants as TODO and use uncached:
   - Document that caching is temporarily disabled pending schema stabilization
   - All `*Cached()` functions call uncached variants
   - Remove stale SQL buffers from `TableMergeStmts`

2. Option B (optimal): Implement full caching for new schema:
   - `TableMergeStmts.init()` takes `TableInfo` parameter
   - Dynamically build SQL with PK column count:
     - `find_pk`: `SELECT __crsql_key FROM pks WHERE col1=? AND col2=?`
     - `row_exists`: `SELECT 1 FROM table WHERE col1=? AND col2=?`
     - `delete`: `DELETE FROM table WHERE col1=? AND col2=?`
   - Store prepared statements (still cached, but schema-aware)

3. Performance regression test:
   - Sync 1000 changes to same table
   - Verify statement reuse (check prepare count in profiling)
   - Compare to baseline (should be ~same if caching works)

4. Choose Option A for MVP (unblock sync), Option B for optimization pass

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration)
- Depends on: TASK-149 (insertIntoPksTableAndGetPk)
- Depends on: TASK-150 (base table ops refactor)
- Related: `zig/src/merge_insert.zig:7-17` (statement caching design doc)
- Upstream: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-21: Created from TASK-147 work. Statement caching is perf-critical but can be temporarily disabled to unblock schema migration.

## Completion Notes
(Empty until done.)

## Completion Notes
- 2025-12-21: **SUPERSEDED by TASK-157**
- The cached statement fixes were completed as part of TASK-157.
- SQL buffers are now properly initialized before getOrPrepare calls.
- Tests pass: rows_impacted 18/18, cross-open 24/24, ALTER 6/6.
