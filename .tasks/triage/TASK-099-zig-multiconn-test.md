# TASK-099: Zig multi-connection parity test (missing task card)

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
`research/zig-cr/92-gap-backlog.md` references TASK-099, but the task card file did not exist.

This task adds a multi-connection test against an on-disk database, validating correct behavior when multiple sqlite connections access the same DB file.

Key risk areas:
- per-connection state isolation (e.g., sync bit handling)
- WAL/shared-cache interactions
- triggers and clock table updates across connections

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
