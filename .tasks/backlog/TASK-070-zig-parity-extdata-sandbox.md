# TASK-070: Zig parity — Cover missing C suites (ext-data + sandbox)

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
- Missing suites:
  - `core/src/ext-data.test.c`
  - `core/src/sandbox.test.c`
- Zig parity runner: `zig/harness/test-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Zig parity harness currently focuses on the `rows-impacted`, `changes-vtab`, rowid slab, alter, noop, and fract behaviors.

To invalidate the hypothesis that the Zig port is "done", we need parity coverage for the remaining C-level suites that exercise real-world failure modes:

- **ext-data**: per-connection extension data lifecycle and correctness under multiple connections.
- **sandbox**: safety rails / invariants the extension expects from SQLite (and that users will hit in production).

This task adds parity scripts for these suites (or ports their assertions into `zig/harness/test-parity.sh`) so Zig behavior is continuously compared against the C/Rust reference.

## Files to Modify
- `zig/harness/test-parity.sh`
- `zig/harness/test-ext-data.sh` (new)
- `zig/harness/test-sandbox.sh` (new)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-parity.sh` runs ext-data + sandbox coverage (no silent gaps).
- [ ] `make -C zig test-parity` passes locally.
- [ ] Failures (if found) are turned into follow-up tasks with tight `Files to Modify`.
- [ ] Evidence captured in this card:
  - commands run
  - pasted failing output (if any)

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".

## Completion Notes
