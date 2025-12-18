# TASK-083: Spec (RGRTDD) — Table compatibility checks for `crsql_as_crr`

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
- Rust reference gating: `core/rs/core/src/tableinfo.rs` (is_table_compatible)
- Rust CRR creation: `core/rs/core/src/create_crr.rs`
- Zig CRR creation: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define (in tests) what tables are eligible to become CRRs.

This is important for real systems because invalid tables can silently produce incorrect triggers/merge behavior.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-table-compat.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Tests fail on current Zig (it upgrades without checks).
- [ ] Tests cover rejections that match Rust behavior:
  1. **No primary key**: conversion fails.
  2. **Unique index besides PK**: conversion fails.
  3. **AUTOINCREMENT present**: conversion fails.
  4. **Checked foreign keys**: conversion fails.
  5. **NOT NULL without DEFAULT**: conversion fails.
- [ ] Tests assert error is visible (non-OK return / error message contains a stable substring).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
