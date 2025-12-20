# TASK-075: Spec (RGRTDD) — `crsql_automigrate` behavior

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust reference implementation: `core/rs/core/src/automigrate.rs`
- Rust integration tests: `core/rs/integration_check/src/t/automigrate.rs`
- Zig alter path: `zig/src/schema_alter.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define the intended behavior of `crsql_automigrate(schema_sql[, cleanup_sql])` by capturing it in executable tests.

The goal is to make it hard to accidentally ship a “toy” automigrate:
- It must be idempotent.
- It must be atomic.
- It must preserve CRR invariants (when migrating CRR tables it must use the alter flow).

This is a **spec/tests-only** task. Do not implement `crsql_automigrate` here.

## Files to Modify
- `zig/harness/test-automigrate.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Test suite exists that fails on current Zig (missing function).
- [x] Tests describe behavior (no "should").
- [x] At minimum, tests cover:
  1. **Empty schema is a no-op**: `SELECT crsql_automigrate('')` returns `migration complete`.
  2. **Create tables**: schema with a new table results in the table existing.
  3. **Drop tables**: tables not present in desired schema are dropped (excluding `sqlite_%`, `crsql_%`, `__crsql_%`, and `%__crsql_%`).
  4. **Add column**: adding a column via desired schema results in column existing.
  5. **Drop column**: removing a column results in column dropped.
  6. **Index reconciliation**: indices match the desired schema.
  7. **CRR table migration uses alter flow**: if the table is a CRR, automigrate uses `crsql_begin_alter`/`crsql_commit_alter` semantics so triggers remain correct.
  8. **Atomicity**: if the schema is invalid, no partial changes persist.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/harness/test-automigrate.sh` with 17 tests covering:
  1. Empty schema is a no-op (returns "migration complete")
  2. Create tables from schema
  3. Drop tables not in desired schema
  3b. System tables preserved (sqlite_%, crsql_%, __crsql_%, %__crsql_%)
  4. Add column to existing table
  5. Drop column from existing table
  5b. Remaining columns preserved after drop
  6a-6d. Index reconciliation (add, remove, change uniqueness, change columns)
  7a-7b. CRR table migration (uses alter flow, preserves clock entries)
  8a-8b. Atomicity (invalid schema = no partial changes, error returns error)
  9. Idempotent (multiple migrations of same schema succeed)
  10. Complex real-world schema migration
- Wired test into `zig/harness/test-parity.sh`
- All 17 tests FAIL as expected (RED phase) - crsql_automigrate not implemented
- No "should" in test descriptions - all tests describe behavior

## Completion Notes
- Test suite: `zig/harness/test-automigrate.sh`
- All tests in RED phase (expected failures)
- Script exits 0 on RED phase (expected behavior for unimplemented feature)
- Wired into parity suite as SKIPPED until TASK-076 implements the function
