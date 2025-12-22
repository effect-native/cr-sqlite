# TASK-158 — Add proper caching for zeroClockOnResurrect

## Goal
Implement proper statement caching for `zeroClockOnResurrectCached()` instead of falling back to uncached version.

## Status
- State: done
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
- 2025-12-21: Implemented proper caching following existing pattern.

## Completion Notes

**Completed: 2025-12-21**

### Changes Made to `zig/src/merge_insert.zig`:

1. **Added SQL buffer** (line ~48):
   ```zig
   sql_zero_clock_resurrect: [512]u8 = undefined,
   ```

2. **Added statement handle** (line ~60):
   ```zig
   zero_clock_resurrect_stmt: ?*api.sqlite3_stmt = null,
   ```

3. **Updated `deinit()`** to finalize the new statement:
   ```zig
   if (self.zero_clock_resurrect_stmt) |stmt| _ = api.finalize(stmt);
   ```

4. **Implemented proper caching** in `zeroClockOnResurrectCached()`:
   - Formats SQL on first use when stmt is null
   - Uses `getOrPrepare()` to get/prepare cached statement
   - Binds pk parameter and executes

### Pattern Followed
The implementation follows the same caching pattern used by:
- `getLocalClCached()`
- `getLocalColVersionCached()`
- `setWinnerClockCached()`
- `dropNonSentinelClocksCached()`

### Verification
- `make -C zig build` — compiles successfully
- `bash zig/harness/test-oracle-parity.sh` — 18 passed, 0 failed
- `make -C zig test-parity` — all parity tests pass (rows_impacted, compound PK, core functions, filters, rowid slab, alter, noops, fract)
