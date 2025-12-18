# TASK-090: Oracle Parity — Trigger/clock logic equivalence

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
- Rust trigger gen: `core/rs/core/src/trigger_fns.rs`
- Zig trigger gen: `zig/src/triggers.zig`
- Clock table logic: `zig/src/changes_vtab_read.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that INSERT/UPDATE/DELETE triggers produce identical `__crsql_clock` entries in both implementations.

This is an **oracle test**: Given the same sequence of DML operations on identical schemas, the resulting clock table contents must match exactly (col_version, db_version, seq values).

## Files to Modify
- `zig/harness/test-trigger-parity.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test creates identical CRR table in both Rust/C and Zig DBs.
- [ ] Test performs identical DML sequence:
  1. INSERT row
  2. UPDATE single column
  3. UPDATE multiple columns
  4. DELETE row
  5. Re-INSERT same PK (resurrection)
- [ ] After each step, compare `__crsql_clock` contents:
  - `col_version` matches
  - `db_version` matches
  - `seq` matches
- [ ] Test fails if any clock entry differs.
- [ ] Test covers:
  - Single-column primary key
  - Compound primary key
  - Tables with nullable columns
  - Tables with DEFAULT values

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

## Completion Notes
