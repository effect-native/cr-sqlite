# TASK-121: Fix rows_impacted ROLLBACK reset divergence

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Divergence documented in: `.tasks/done/TASK-093-rows-impacted-counter-timing.md`
- Zig implementation: `zig/src/rows_impacted.zig`
- Rust/C reference: `core/src/changes-vtab.c:173` (xRollback is NULL)
- Test: `zig/harness/test-rows-impacted-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Zig implementation incorrectly resets `rows_impacted` on ROLLBACK via `rollback_hook`.
The Rust/C oracle does NOT reset on ROLLBACK (xRollback is NULL).

This causes sync client batching to report incorrect counts after a rolled-back transaction.

## Files to Modify
- `zig/src/rows_impacted.zig`

## Acceptance Criteria
- [x] `rollbackHookCallback` does NOT call `resetCounter()` for `rows_impacted`
- [x] `zig/harness/test-rows-impacted-parity.sh` passes with 0 divergences (18/18 pass)
- [x] Other functionality (db_version, seq) is unaffected by this change

## Progress Log
### 2025-12-20
- Task created from documented divergence in TASK-093
- Fixed: Removed `resetCounter()` call from `rollbackHookCallback` in `zig/src/rows_impacted.zig`
- Verified: All 18 parity tests pass with 0 divergences

## Completion Notes
### 2025-12-20
**Fix applied:** Modified `rollbackHookCallback` in `zig/src/rows_impacted.zig` to NOT reset `rows_impacted` on ROLLBACK.

**Change:** Removed the `resetCounter()` call from the rollback hook while preserving `rollbackDbVersion()` and `resetSeq()` calls.

**Test results:**
```
rows_impacted Parity Test Summary
  PASSED:      18
  FAILED:      0
  DIVERGENCES: 0
```

The Zig implementation now matches the Rust/C oracle behavior where `xRollback` is NULL (does not reset `rows_impacted` counter).

