# TASK-074: Cross-implementation wire compatibility — Expand beyond happy path

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
- Existing script: `zig/harness/test-cross-platform-compat.sh`
- C sync helper reference: `core/src/crsqlite.test.c` (syncLeftToRight)
- Feature matrix: `research/zig-cr/90-feature-matrix.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
A real system will often have heterogeneous peers (mobile, server, browser) and long-lived on-disk databases.

We already have a Zig↔Rust/C compatibility script, but it’s easy for it to be effectively "green" because:
- it can SKIP if the Rust/C extension isn’t built
- it may not cover important edge cases (deletes, PK updates, schema evolution, numeric/text encoding edge cases)

This task strengthens the compatibility proof by expanding the scenario set and making sure CI/local runs cannot silently skip the Rust/C side.

## Files to Modify
- `zig/harness/test-cross-platform-compat.sh`
- `core/Makefile` (only if needed to provide a reproducible build target for the Rust/C loadable extension)
- `.github/workflows/zig-tests.yaml` (optional: ensure Rust/C artifact exists for compat test)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Script reliably finds/builds the Rust/C extension (no silent SKIP in CI).
- [ ] New compatibility assertions added for at least:
  - deletes + resurrection behavior
  - primary key updates
  - compound primary keys
  - float edge cases (sci notation), blobs, NULLs
  - schema evolution (add/remove columns with `crsql_commit_alter`/equivalent)
- [ ] Both directions tested: Zig→Rust/C and Rust/C→Zig.

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".

## Completion Notes
