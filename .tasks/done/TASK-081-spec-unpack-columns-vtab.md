# TASK-081: Spec (RGRTDD) — `crsql_unpack_columns` virtual table

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] Test fails on current Zig (module missing).
- [x] At minimum, test asserts:
  1. `SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns(12, 'str', x'010203')` returns the sequence `12`, `str`, `x'010203'`.
  2. The vtab is INNOCUOUS (cannot write / no side effects).
  3. Filter requires the hidden `package` constraint (like Rust best-index behavior).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/harness/test-unpack-columns-vtab.sh` with 12 test cases
- Wired into `zig/harness/test-parity.sh`
- Confirmed RED phase: Test 1 fails with "no such table: crsql_unpack_columns", 11 tests skip

## Completion Notes
### 2025-12-20
**Status: RED phase confirmed (spec complete)**

Created spec test file with 12 test cases covering:
1. Module exists
2. Unpack single integer
3. Unpack single string
4. Unpack single blob
5. Unpack multiple values (compound PK simulation)
6. Unpack NULL value
7. Unpack mixed types (preserves type info)
8. Empty package returns no rows
9. Invalid package returns error or empty
10. Module is INNOCUOUS (read-only, no INSERT)
11. Requires package constraint (best-index behavior)
12. Round-trip pack/unpack parity

**Test output:**
```
crsql_unpack_columns Tests Summary: 0 passed, 1 failed, 11 skipped
RED PHASE: Module not yet implemented in Zig (expected)
```

The spec is ready for implementation in TASK-082.
