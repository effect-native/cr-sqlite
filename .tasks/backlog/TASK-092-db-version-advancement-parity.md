# TASK-092: Oracle Parity — db_version advancement timing

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
- Rust db_version logic: `core/rs/core/src/db_version.rs`
- Zig db_version logic: `zig/src/crsqlite.zig` (crsql_db_version, crsql_next_db_version)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_db_version()` and `crsql_next_db_version()` increment at exactly the same moments in both implementations.

This is an **oracle test**: The db_version is critical for sync protocols. If Zig and Rust/C increment it at different times (e.g., per-statement vs per-transaction), sync will break.

## Files to Modify
- `zig/harness/test-db-version-parity.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test performs identical operations in both implementations and records db_version after each.
- [ ] Operations tested:
  1. Initial state (should be 0 or 1)
  2. Single INSERT → record db_version
  3. Single UPDATE → record db_version
  4. Multiple INSERTs in one transaction → record db_version at COMMIT
  5. DELETE → record db_version
  6. No-op UPDATE (same value) → db_version should NOT change
  7. Merge from remote (crsql_changes INSERT) → record db_version
- [ ] All db_version values match exactly between implementations.
- [ ] `crsql_next_db_version()` returns `db_version + 1` in both.
- [ ] Test fails if any db_version diverges.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

## Completion Notes
