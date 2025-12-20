# TASK-119: Fix realistic sync/offline test failures (extra rows after merge)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(to be assigned during delegation)

## Parent Docs / Cross-links
- Test scripts:
  - `zig/harness/test-realistic-sync.sh` (2 failures)
  - `zig/harness/test-realistic-offline.sh` (2 failures)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Related: Backfill tests `zig/harness/test-backfill.sh`
- Follow-up for TASK-120 (consolidated — same root cause)

## Description
Both realistic test scripts fail with the same pattern: **extra rows after merge**.

### test-realistic-sync.sh (2 failures)
**Observed behavior:**
- After Alice and Bob sync, both have 6 todos instead of 4
- Data shows extra empty rows (id 101, 102 appear twice — once with data, once empty)

**Expected behavior:**
- After sync, both should have exactly 4 unique todos:
  - Alice's: id=1 "Buy groceries", id=2 "Walk the dog"
  - Bob's: id=101 "Call mom", id=102 "Fix bike"

### test-realistic-offline.sh (2 failures)
**Observed behavior:**
- Field worker and server have 6 inspections instead of 5
- Extra rows created during merge

**Hypothesis (shared root cause):**
This could be related to:
1. Merge logic creating duplicate entries when applying changes
2. Sentinel rows being incorrectly materialized as real rows
3. `INSERT INTO crsql_changes` creating base table rows it shouldn't
4. Test script logic issue (query or assertion bug)

## Files to Modify
- `zig/harness/test-realistic-sync.sh` (if test bug)
- `zig/harness/test-realistic-offline.sh` (if test bug)
- `zig/src/merge_insert.zig` (if merge logic bug)
- `zig/src/changes_vtab.zig` (if changes query bug)

## Acceptance Criteria
- [x] `bash zig/harness/test-realistic-sync.sh` passes with 0 failures
- [x] `bash zig/harness/test-realistic-offline.sh` passes with 0 failures
- [x] After bidirectional sync, both databases contain exactly the same data
- [x] No duplicate rows created during merge
- [x] Root cause documented in Completion Notes

## Progress Log
### 2025-12-20
- Test discovered during Round 49 delegation prep
- Both tests show same symptom: extra rows after merge (6 instead of expected 4-5)
- Consolidated with TASK-120 as likely same root cause

## Completion Notes
### 2025-12-20

#### Root Cause
The cached merge functions in `zig/src/merge_insert.zig` were using the `pk` (auto-increment key from `__crsql_pks` table) directly as the base table `rowid`, but they are NOT the same thing:

- `pk` = auto-increment key in `__crsql_pks` table (used in clock table references)
- `base_rowid` = actual rowid in the user's base table (e.g., `todos.rowid`)

The pks table maps `pk` → `base_rowid` via the `pks` column (packed PK blob).

Three cached functions had this bug:
1. `rowExistsInBaseTableCached()` - was checking `SELECT 1 FROM table WHERE rowid = pk` instead of looking up `base_rowid` first
2. `deleteFromBaseTableCached()` - was deleting with wrong rowid, also missing tombstone marking
3. `updateBaseTableColumn()` - was updating with wrong rowid

The uncached versions of these functions correctly looked up `base_rowid` from the pks table before operating on the base table, but the cached versions skipped this step.

This caused:
- During sync, when checking if a row exists (`rowExistsInBaseTableCached`), it would check the wrong rowid and falsely report "row doesn't exist"
- This triggered the resurrection code path, which would INSERT a new row instead of UPDATE
- When updating columns (`updateBaseTableColumn`), it would update the wrong row or no row at all

#### Fix Applied
Modified three functions in `zig/src/merge_insert.zig`:

1. **`rowExistsInBaseTableCached`** (lines 950-964): Added lookup of `base_rowid` via `getBaseRowidFromPk()` before checking base table

2. **`deleteFromBaseTableCached`** (lines 966-999): Added lookup of `base_rowid`, plus tombstone marking logic that was missing

3. **`updateBaseTableColumn`** (lines 250-302): Added lookup of `base_rowid` via `getBaseRowidFromPk()` before UPDATE

#### Test Results
- `bash zig/harness/test-realistic-sync.sh` - PASSED (0 failures)
- `bash zig/harness/test-realistic-offline.sh` - PASSED (0 failures)
- `make -C zig test-parity` - All parity tests continue to pass
