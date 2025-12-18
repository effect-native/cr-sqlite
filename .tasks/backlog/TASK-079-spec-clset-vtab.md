# TASK-079: Spec (RGRTDD) — `clset` virtual table module

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
- Rust reference: `core/rs/core/src/create_cl_set_vtab.rs`
- Rust integration tests: `core/rs/integration_check/src/t/test_cl_set_vtab.rs`
- Zig: (missing)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define behavior for the `clset` module ("Causal Length Set" virtual table).

This task creates failing tests that define:
- Required naming conventions (`*_schema`).
- Which physical tables are created.
- That the base table is converted to CRR.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-clset-vtab.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test fails on current Zig (module missing).
- [ ] At minimum, tests cover:
  1. `CREATE VIRTUAL TABLE something_schema USING clset(...)` succeeds.
  2. Creating a virtual table without `_schema` suffix fails with a clear error.
  3. After create, physical tables exist:
     - `<base>` (storage)
     - `<base>__crsql_clock`
     - `<base>__crsql_pks`
  4. The base table is a CRR (e.g. `SELECT crsql_is_crr('<base>')` returns true).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
