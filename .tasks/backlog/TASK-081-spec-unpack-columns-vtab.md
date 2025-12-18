# TASK-081: Spec (RGRTDD) — `crsql_unpack_columns` virtual table

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
- Rust reference implementation: `core/rs/core/src/unpack_columns_vtab.rs`
- Rust pack/unpack code: `core/rs/core/src/pack_columns.rs`
- Zig pack code: `zig/src/pack_columns.zig`
- Zig codec helpers: `zig/src/codec.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define the behavior of the `crsql_unpack_columns` virtual table.

This vtab is a debugging/inspection tool and is part of the “real system” ergonomics: it helps users validate and troubleshoot packed PK formats.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-unpack-columns-vtab.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test fails on current Zig (module missing).
- [ ] At minimum, test asserts:
  1. `SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns(12, 'str', x'010203')` returns the sequence `12`, `str`, `x'010203'`.
  2. The vtab is INNOCUOUS (cannot write / no side effects).
  3. Filter requires the hidden `package` constraint (like Rust best-index behavior).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
