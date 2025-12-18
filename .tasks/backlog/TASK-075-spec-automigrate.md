# TASK-075: Spec (RGRTDD) — `crsql_automigrate` behavior

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
- [ ] Test suite exists that fails on current Zig (missing function).
- [ ] Tests describe behavior (no “should”).
- [ ] At minimum, tests cover:
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

## Completion Notes
