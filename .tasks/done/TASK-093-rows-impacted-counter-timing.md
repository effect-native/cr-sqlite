# TASK-093: Oracle Parity — rows_impacted counter reset timing

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(completed by agent)

## Parent Docs / Cross-links
- Rust rows_impacted: `core/rs/core/src/changes_vtab.rs` (xCommit resets, xRollback=NULL)
- C changes-vtab: `core/src/changes-vtab.c:173` (xRollback is 0/NULL)
- Zig rows_impacted: `zig/src/rows_impacted.zig` (commit_hook + rollback_hook)
- Test: `zig/harness/test-rows-impacted-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_rows_impacted()` resets at the same moments in both implementations.

This is an **oracle test**: The counter reset timing matters for sync clients that batch changes. If Zig resets on COMMIT but Rust/C resets on statement completion (or vice versa), clients will get wrong counts.

## Files to Modify
- `zig/harness/test-rows-impacted-parity.sh` (new or extend existing) ✓ CREATED
- `zig/harness/test-parity.sh` (wire into suite) ✓ UPDATED
- `research/zig-cr/92-gap-backlog.md` ✓ UPDATED

## Acceptance Criteria
- [x] Test performs identical merge sequences and checks `crsql_rows_impacted()` at each checkpoint.
- [x] Scenarios tested:
  1. Insert one change via `crsql_changes` → check count (should be 1) ✓ PASS
  2. Insert two more changes → check count (should be 3 total) ✓ PASS
  3. COMMIT transaction → check count (should be 0 after reset) ✓ PASS
  4. New transaction, insert change → check count ✓ PASS
  5. ROLLBACK transaction → check count behavior ✓ DIVERGENCE FOUND
- [x] Counter values match exactly between implementations at each checkpoint.
  - **DIVERGENCE**: ROLLBACK behavior differs (Rust/C keeps count, Zig resets to 0)
- [x] Document the expected reset semantics (per-statement, per-transaction, or manual).
- [x] Test fails if any counter value diverges.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

### 2025-12-17
- Created `zig/harness/test-rows-impacted-parity.sh` with 9 test scenarios
- Wired into `zig/harness/test-parity.sh`
- Updated `research/zig-cr/92-gap-backlog.md`
- Test results: 17 PASS, 1 FAIL (ROLLBACK divergence)

## Completion Notes

### Test Results
```
PASSED:      17
FAILED:      1
DIVERGENCES: 1 (critical - will break sync client batching)
```

### Documented Reset Semantics (per Rust/C oracle)
- Counter accumulates within a transaction (multiple INSERTs sum up)
- Counter resets to 0 on COMMIT (via vtab xCommit)
- Counter does NOT reset on ROLLBACK (xRollback is NULL in Rust/C!)
- Counter only increments when a row is ACTUALLY changed (not for no-ops)
- Losing merges (lower col_version) do NOT increment counter
- Winning merges (higher col_version) DO increment counter

### Known Divergence (BUG in Zig implementation)
The Zig implementation incorrectly resets `rows_impacted` on ROLLBACK via `rollback_hook`.
The Rust/C implementation has `xRollback = 0` (NULL) in `changes-vtab.c:173`, meaning
the counter is NOT reset on rollback.

**Fix required in `zig/src/rows_impacted.zig`:**
The `rollbackHookCallback` function should NOT call `resetCounter()` for `rows_impacted`.
(Note: It may still need to reset db_version and seq for other reasons.)
