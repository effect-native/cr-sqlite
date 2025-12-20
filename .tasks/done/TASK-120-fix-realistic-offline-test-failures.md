# TASK-120: Fix realistic offline test failures

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked
- [x] Complete (fixed by TASK-119)

## Priority
high

## Assigned To
(to be assigned during delegation)

## Parent Docs / Cross-links
- Test script: `zig/harness/test-realistic-offline.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Related: `TASK-119` (similar sync test failures)

## Description
The realistic offline test (`test-realistic-offline.sh`) currently fails with 2 scenarios.

The test demonstrates offline-first sync patterns:
1. Offline accumulation (changes accumulate locally)
2. Sync cursor (incremental sync with db_version)
3. Bidirectional sync (pull/push)
4. Concurrent edit merge

**Investigation needed:**
- Identify which 2 scenarios fail
- Determine if this is related to TASK-119 (same root cause)
- Fix either test assertions or implementation

## Files to Modify
- `zig/harness/test-realistic-offline.sh` (if test bug)
- `zig/src/merge_insert.zig` (if merge logic bug)
- `zig/src/changes_vtab.zig` (if changes query bug)

## Acceptance Criteria
- [x] `bash zig/harness/test-realistic-offline.sh` passes with 0 failures
- [x] All 4 key patterns demonstrated work correctly
- [x] Root cause documented in Completion Notes

## Progress Log
### 2025-12-20
- Test discovered during Round 49 delegation prep
- 2 failures observed, details TBD

## Completion Notes
### 2025-12-20
Fixed by TASK-119. The root cause was the same bug in cached merge functions that affected both realistic sync and realistic offline tests. See TASK-119 for details.
