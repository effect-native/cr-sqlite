# TASK-080: Implement (RGRTDD) — `clset` virtual table module in Zig

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Spec task: `.tasks/backlog/TASK-079-spec-clset-vtab.md`
- Rust reference: `core/rs/core/src/create_cl_set_vtab.rs`
- Registration point: `zig/src/ffi/init.zig`
- Zig CRR creation: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement the `clset` module in Zig so that tests from TASK-079 pass.

Important notes from Rust behavior:
- Virtual table name must end with `_schema`.
- It creates a base storage table and upgrades it to a CRR.
- It declares a schema vtab interface with hidden columns.

## Files to Modify
- `zig/src/clset_vtab.zig` (new)
- `zig/src/ffi/init.zig`
- `zig/src/as_crr.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-clset-vtab.sh` passes.
- [ ] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
