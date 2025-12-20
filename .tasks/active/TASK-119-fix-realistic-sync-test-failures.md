# TASK-119: Fix realistic sync/offline test failures (extra rows after merge)

## Status
- [ ] Planned
- [x] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

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
- [ ] `bash zig/harness/test-realistic-sync.sh` passes with 0 failures
- [ ] `bash zig/harness/test-realistic-offline.sh` passes with 0 failures
- [ ] After bidirectional sync, both databases contain exactly the same data
- [ ] No duplicate rows created during merge
- [ ] Root cause documented in Completion Notes

## Progress Log
### 2025-12-20
- Test discovered during Round 49 delegation prep
- Both tests show same symptom: extra rows after merge (6 instead of expected 4-5)
- Consolidated with TASK-120 as likely same root cause

## Completion Notes
