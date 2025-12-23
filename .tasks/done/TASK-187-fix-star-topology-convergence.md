# TASK-187 — Fix star topology sync convergence failure

## Goal
Fix Zig implementation to correctly converge in hub-and-spoke (star) topology sync patterns.

## Status
- State: COMPLETE
- Priority: HIGH (multi-node sync broken)
- Discovered: Round 62 (TASK-179 test suite)

## Problem
In a hub-and-spoke topology where all nodes sync only through a central hub, Zig nodes fail to converge to the same state. Rust/C converges correctly.

**Test failure from `test-multinode-sync.sh`:**
```
Test 3: Star topology - FAIL

  Hub data: 1|updated_by_b|c2|c3|c4
            3|d1|d2|d3|d4
  B data:   1|updated_by_b|c2|c3|c4
            3|d1|d2|d3|d4
  C data:   1|c1|c2|c3|c4           <-- wrong! didn't get B's update
            3|d1|d2|d3|d4
  D data:   2|d1|d2|d3|d4           <-- completely wrong rows
            3|updated_by_b|b2|b3|b4

  FAIL: Hub and C diverged
  FAIL: Hub and D diverged
```

## Scenario
1. Create 4 databases: Hub, B, C, D
2. B, C, D each create unique rows
3. All sync to Hub (Hub has all rows)
4. Hub syncs back to all spokes (all should have same data)
5. B updates row 1, C deletes row 2
6. Sync through Hub again
7. **Expected**: All 4 nodes converge to same state
8. **Actual (Zig)**: C didn't get B's update, D has completely wrong data

## Root Cause Analysis

**Three bugs found and fixed:**

### Bug 1: site_id not preserved when relaying changes through hub
- Location: `zig/src/merge_insert.zig` in `setWinnerClock` and `setWinnerClockCached`
- Problem: The code was always storing `site_id = 0` (local) instead of preserving the original remote site_id
- Fix: Added lookup via `site_identity.getOrCreateSiteOrdinal()` to convert the 16-byte site_id blob to an ordinal and store it correctly

### Bug 2: `getLocalColVersion` filtering incorrectly by site_id
- Location: `zig/src/merge_insert.zig` in `getLocalColVersion` and `getLocalColVersionCached`
- Problem: Was filtering with `WHERE site_id = 0` which ignored remote changes
- Fix: Removed the site_id filter since clock table has unique constraint on (key, col_name)

### Bug 3 (MAIN BUG): Using `rowid` instead of PK column for table operations
- Location: `zig/src/merge_insert.zig` in `updateBaseTableColumn`, `rowExistsInBaseTable`, `deleteFromBaseTable`, and cached variants
- Problem: For tables with `a PRIMARY KEY NOT NULL` (not `INTEGER PRIMARY KEY`), SQLite's rowid is NOT aliased to the PK column. The code was using `WHERE rowid = ?` but rowid ≠ PK value.
- Example: Row with a=2 inserted first gets rowid=1, row with a=1 inserted second gets rowid=2. Using `WHERE rowid=1` updates the wrong row!
- Fix: Changed all operations to use `WHERE "pk_column" = ?` instead of `WHERE rowid = ?`

## Files Modified
- `zig/src/merge_insert.zig` — Main changes for site_id handling and rowid→PK column fix

## Acceptance Criteria
1. ✅ `bash zig/harness/test-multinode-sync.sh` — Test 3 (star topology) passes
2. ✅ All other multinode tests still pass
3. ✅ No regressions in `test-sentinel-parity.sh`
4. ✅ No regressions in `test-resurrection-parity.sh`
5. ✅ No regressions in `test-fract-parity.sh`

## Parent Docs / Cross-links
- Test: `zig/harness/test-multinode-sync.sh` (Test 3: Star topology)
- Triggering task: `.tasks/done/TASK-179-multinode-sync.md`
- Python reference: `py/correctness/tests/test_cl_merging.py`

## Progress Log
- 2025-12-22: Created from Round 62 divergence discovery.
- 2025-12-22: Fixed Bug 1 - site_id not preserved in setWinnerClock/setWinnerClockCached
- 2025-12-22: Fixed Bug 2 - getLocalColVersion filtering incorrectly by site_id
- 2025-12-22: Fixed Bug 3 - rowid vs PK column mismatch in updateBaseTableColumn, rowExistsInBaseTable, deleteFromBaseTable
- 2025-12-22: All tests pass

## Completion Notes
- Fixed: 2025-12-22
- Root cause was primarily Bug 3: SQLite's rowid is only aliased to the PK column for `INTEGER PRIMARY KEY`. For other PK types like `PRIMARY KEY NOT NULL`, rowid is independent. The fix queries using actual PK column names.
- All multinode sync tests now pass with parity to Rust/C oracle.
