# TASK-158 — Add proper caching for zeroClockOnResurrect

## Goal
Implement proper statement caching for `zeroClockOnResurrectCached()` instead of falling back to uncached version.

## Status
- State: triage
- Priority: low (optimization, not blocking)

## Context
During the build fix session (2025-12-21), `zeroClockOnResurrectCached()` was added as a stub that falls back to the uncached `zeroClockOnResurrect()`. This works but loses the performance benefit of statement caching.

Current implementation:
```zig
pub fn zeroClockOnResurrectCached(
    stmts: *TableMergeStmts,
    pk: i64,
) MergeError!void {
    // Format SQL on first use - need to add sql buffer and stmt handle for this
    // For now, fall back to uncached version
    return zeroClockOnResurrect(stmts.db, stmts.table_name, pk);
}
```

## Files to Modify
- `zig/src/merge_insert.zig`:
  - Add `sql_zero_clock_resurrect: [512]u8` buffer to `TableMergeStmts`
  - Add `zero_clock_resurrect_stmt: ?*api.sqlite3_stmt` handle to `TableMergeStmts`
  - Update `deinit()` to finalize the statement
  - Implement proper caching in `zeroClockOnResurrectCached()`

## Acceptance Criteria
1. `zeroClockOnResurrectCached()` uses cached prepared statement
2. SQL is formatted once on first call, reused thereafter
3. No performance regression (should be faster than current fallback)
4. Statement properly finalized in `deinit()`

## Parent Docs / Cross-links
- Related: Build fix session 2025-12-21
- File: `zig/src/merge_insert.zig`

## Progress Log
- 2025-12-21: Created as optimization follow-up from build fix.

## Completion Notes
(Empty until done.)
