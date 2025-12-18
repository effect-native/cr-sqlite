# TASK-094: Oracle Parity — ALTER TABLE preserves clock history

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
- Rust alter logic: `core/rs/core/src/alter.rs`
- Zig alter logic: `zig/src/schema_alter.zig`
- Existing alter tests: `zig/harness/test-alter.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_begin_alter` / `crsql_commit_alter` preserves existing clock history and correctly backfills new columns.

This is an **oracle test**: Schema evolution is critical for long-lived databases. If Zig loses clock history during ALTER or fails to backfill new columns, data will be lost or sync will break.

## Files to Modify
- `zig/harness/test-alter-parity.sh` (new or extend `test-alter.sh`)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test creates CRR table, inserts data, records clock state.
- [ ] Test performs ALTER operations via `crsql_begin_alter`/`crsql_commit_alter`:
  1. ADD COLUMN (nullable)
  2. ADD COLUMN with DEFAULT
  3. DROP COLUMN
  4. ADD INDEX
  5. DROP INDEX
- [ ] After each ALTER:
  - Existing clock entries are preserved (same col_version, db_version for unchanged columns)
  - New columns have clock entries backfilled (col_version = 1, current db_version)
  - Dropped columns have clock entries removed
- [ ] Clock state matches exactly between implementations.
- [ ] Test covers edge cases:
  - ALTER on empty table
  - ALTER on table with 1000+ rows (batching behavior)
  - Multiple ALTERs in sequence
  - ALTER that adds column then immediately updates it
- [ ] Test fails if clock history diverges.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

## Completion Notes
