# TASK-071: Zig parity — Cover remaining C suites (crsqlite + is-crr)

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
- C test runner: `core/src/tests.c`
- Suites to cover:
  - `core/src/crsqlite.test.c`
  - `core/src/is-crr.test.c`
- Zig parity runner: `zig/harness/test-parity.sh`
- Existing Zig harness scripts: `zig/harness/test-is-crr.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The C reference test runner (`core/src/tests.c`) includes suites for base extension behaviors (`crsqlite`) and CRR detection (`is-crr`).

Some of this may already be covered by existing Zig harness scripts, but the parity runner must make this explicit and non-optional.

This task ensures:
- We have Zig-side tests that correspond to the C suite assertions.
- `zig/harness/test-parity.sh` actually runs them (so we’re not "green" due to missing coverage).

## Files to Modify
- `zig/harness/test-parity.sh`
- `zig/harness/test-crsqlite.sh` (new, if needed)
- `zig/harness/test-is-crr.sh` (if wiring/assertions need adjustments)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `make -C zig test-parity` exercises `crsqlite` and `is_crr` equivalently to the C runner.
- [ ] No parity suite remains uncovered from the set in `core/src/*.test.c`.
- [ ] Evidence captured in this card: commands + outputs.

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".

## Completion Notes
