# TASK-082: Implement (RGRTDD) — `crsql_unpack_columns` vtab in Zig

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
- [x] `zig/harness/test-unpack-columns-vtab.sh` passes.
- [x] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Implemented `crsql_unpack_columns` virtual table in `zig/src/unpack_columns_vtab.zig`
- Registered module in `zig/src/ffi/init.zig`
- All 12 tests in `test-unpack-columns-vtab.sh` pass
- Parity tests pass with no regressions

## Completion Notes
Implementation complete. Created `zig/src/unpack_columns_vtab.zig` (624 lines) with:
- Read-only (INNOCUOUS) eponymous virtual table
- Schema: `CREATE TABLE x(cell ANY, package BLOB hidden)`
- xBestIndex: Requires EQ constraint on `package` column, returns SQLITE_CONSTRAINT otherwise
- xFilter: Decodes packed blob using codec format (same as codec.zig)
- xColumn: Returns appropriate SQLite type for each unpacked value (integer, float, text, blob, null)
- xUpdate is null (read-only), causing INSERT to fail as expected

Test results:
```
crsql_unpack_columns Tests Summary: 12 passed, 0 failed, 0 skipped
All crsql_unpack_columns tests passed!
```

All 12 tests pass:
1. Module exists
2. Unpack single integer (42)
3. Unpack single string ('hello')
4. Unpack single blob (x'DEADBEEF')
5. Unpack multiple values (compound PK simulation)
6. Unpack NULL value
7. Unpack mixed types preserves type info
8. Empty package returns no rows
9. Invalid package returns error
10. Module is INNOCUOUS (INSERT fails)
11. Requires package constraint (SELECT without WHERE fails)
12. Round-trip pack/unpack parity
