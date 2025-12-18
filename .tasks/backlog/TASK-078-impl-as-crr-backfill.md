# TASK-078: Implement (RGRTDD) — `crsql_as_crr` backfill in Zig

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
- Spec task: `.tasks/backlog/TASK-077-spec-as-crr-backfill.md`
- Rust reference backfill: `core/rs/core/src/backfill.rs`
- Zig implementation: `zig/src/as_crr.zig`
- Registration point: `zig/src/ffi/init.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement backfill behavior for `crsql_as_crr` in Zig.

Design intent:
- Populate `__crsql_pks` and `__crsql_clock` for existing rows.
- Use savepoints for atomicity.
- Keep behavior idempotent (EXCEPT/LEFT JOIN style filters like Rust).

## Files to Modify
- `zig/src/as_crr.zig`
- `zig/src/backfill.zig` (new, if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-as-crr-backfill.sh` passes.
- [ ] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
