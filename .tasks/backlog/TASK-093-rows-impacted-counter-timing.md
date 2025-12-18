# TASK-093: Oracle Parity — rows_impacted counter reset timing

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
- Rust rows_impacted: `core/rs/core/src/rows_impacted.rs`
- Zig rows_impacted: `zig/src/crsqlite.zig`
- Existing tests: `zig/harness/test-rows-impacted.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_rows_impacted()` resets at the same moments in both implementations.

This is an **oracle test**: The counter reset timing matters for sync clients that batch changes. If Zig resets on COMMIT but Rust/C resets on statement completion (or vice versa), clients will get wrong counts.

## Files to Modify
- `zig/harness/test-rows-impacted-parity.sh` (new or extend existing)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test performs identical merge sequences and checks `crsql_rows_impacted()` at each checkpoint.
- [ ] Scenarios tested:
  1. Insert one change via `crsql_changes` → check count (should be 1)
  2. Insert two more changes → check count (should be 3 total, or 2 if reset after first)
  3. COMMIT transaction → check count (should be 0 after reset, or preserved)
  4. New transaction, insert change → check count
  5. ROLLBACK transaction → check count behavior
- [ ] Counter values match exactly between implementations at each checkpoint.
- [ ] Document the expected reset semantics (per-statement, per-transaction, or manual).
- [ ] Test fails if any counter value diverges.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

## Completion Notes
