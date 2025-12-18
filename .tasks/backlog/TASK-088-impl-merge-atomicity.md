# TASK-088: Implement (RGRTDD) — Savepoint-backed atomic batch merge in Zig

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
- Spec task: `.tasks/backlog/TASK-087-spec-merge-atomicity.md`
- Rust reference: `core/rs/core/src/changes_vtab_write.rs`
- Zig merge entrypoint: `zig/src/changes_vtab.zig`
- Zig vtab plumbing: `zig/src/sqlite/vtab.zig` (if xBegin/xCommit/xRollback hooks are used)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement atomicity guarantees for batch apply.

Potential strategies (choose the one that matches SQLite vtab semantics best):
- Use vtab `xBegin/xCommit/xRollback` to wrap the *statement* in a savepoint.
- Or: detect statement boundaries and manage a savepoint per statement.

Must satisfy the tests defined in TASK-087.

## Files to Modify
- `zig/src/changes_vtab.zig`
- `zig/src/sqlite/vtab.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-merge-atomicity.sh` passes.
- [ ] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
