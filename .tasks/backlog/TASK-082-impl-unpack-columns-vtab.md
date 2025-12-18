# TASK-082: Implement (RGRTDD) — `crsql_unpack_columns` vtab in Zig

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
- Spec task: `.tasks/backlog/TASK-081-spec-unpack-columns-vtab.md`
- Rust reference: `core/rs/core/src/unpack_columns_vtab.rs`
- Zig pack/unpack: `zig/src/codec.zig`, `zig/src/pack_columns.zig`
- Registration point: `zig/src/ffi/init.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement `crsql_unpack_columns` module in Zig.

Key behaviors to match:
- It is a virtual table with schema `CREATE TABLE x(cell ANY, package BLOB hidden)`.
- It requires a usable constraint on the hidden `package` column.
- It iterates unpacked columns as rows.

## Files to Modify
- `zig/src/unpack_columns_vtab.zig` (new)
- `zig/src/ffi/init.zig`
- `zig/src/codec.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/harness/test-unpack-columns-vtab.sh` passes.
- [ ] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
