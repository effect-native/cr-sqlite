# TASK-109: Obsolete placeholder for TASK-099

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Gap backlog entry: `research/zig-cr/92-gap-backlog.md`
- Existing harness patterns (on-disk DB scripts): `zig/harness/test-multiconn.sh` (if/when created by other tasks)
- Related task: `.tasks/active/TASK-098-zig-ondisk-db-tests.md`

## Description
Obsolete placeholder.

This file previously existed only because `research/zig-cr/92-gap-backlog.md` referenced TASK-099 but a task card was missing at that time.

Canonical card:
- `.tasks/done/TASK-099-zig-multiconn-test.md`

## Files to Modify
- `zig/harness/test-multiconn.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)

## Acceptance Criteria
- [ ] Test uses an on-disk DB file under `.tmp/` (not `/tmp`).
- [ ] Test opens at least two connections sequentially (or concurrently if feasible) and validates:
  - [ ] changes from connection A are visible to connection B
  - [ ] CRR triggers fire correctly across connections
  - [ ] `crsql_db_version` / `__crsql_clock` reflect expected updates
- [ ] If possible, compare behavior against sqlite-cr oracle.

## Progress Log
### 2025-12-20
- Task card created because it was missing but referenced by the gap backlog.

## Completion Notes

Obsolete placeholder task card.

- Reason: a canonical TASK-099 exists with completion notes at `.tasks/done/TASK-099-zig-multiconn-test.md`.
- This card is kept only to preserve the historical note that the backlog link was once broken.
