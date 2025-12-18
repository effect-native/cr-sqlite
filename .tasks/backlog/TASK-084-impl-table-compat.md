# TASK-084: Implement (RGRTDD) — Table compatibility checks in Zig

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
- Spec task: `.tasks/backlog/TASK-083-spec-table-compat.md`
- Rust reference: `core/rs/core/src/tableinfo.rs`
- Zig table info extraction: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement Rust-equivalent table compatibility checks in Zig before creating CRR metadata.

Expected approach:
- Query SQLite pragmas (`table_info`, `index_list`, `foreign_key_list`, etc.)
- Enforce the same constraints as Rust.
- Return useful errors.

## Files to Modify
- `zig/src/as_crr.zig`
- `zig/src/table_compat.zig` (new, if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-table-compat.sh` passes.
- [ ] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
