# TASK-076: Implement (RGRTDD) — `crsql_automigrate` in Zig

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
- Spec task: `.tasks/backlog/TASK-075-spec-automigrate.md`
- Rust reference: `core/rs/core/src/automigrate.rs`
- Zig alter functions: `zig/src/schema_alter.zig`
- Registration point: `zig/src/ffi/init.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement `crsql_automigrate` in Zig so that the RGRTDD tests from TASK-075 pass.

Mirror Rust semantics where possible:
- Create an in-memory database to parse/validate desired schema.
- Strip CRR statements when validating in memory.
- Use a savepoint for atomic migration.
- Apply diffs (drop tables/cols, add cols, reconcile indices).
- For CRR tables, wrap modifications with begin/commit alter.

## Files to Modify
- `zig/src/automigrate.zig` (new)
- `zig/src/ffi/init.zig`
- `zig/src/root.zig` (if module wiring required)
- `zig/src/schema_alter.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-automigrate.sh` passes.
- [ ] No regression in `make -C zig test-parity`.
- [ ] Failure modes are surfaced as SQLite errors (message + error code) consistent with Rust behavior.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
