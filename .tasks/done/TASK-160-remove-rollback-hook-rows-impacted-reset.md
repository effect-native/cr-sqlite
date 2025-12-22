# TASK-160 — Remove rollback_hook reset for rows_impacted counter

## Goal
Remove the `resetCounter()` call from the rollback hook to match Rust/C oracle behavior where `xRollback` is NULL and does not reset the counter.

## Status
- State: done
- Priority: low (parity divergence, tests pass but behavior differs)

## Context
Documented during TASK-157 fix (Round 59). The test harness notes:

```
KNOWN DIVERGENCE:
  Zig incorrectly resets rows_impacted on ROLLBACK via rollback_hook.
  This should be removed to match Rust/C behavior (xRollback=NULL).
```

Current behavior:
- Zig: `rows_impacted` counter resets on ROLLBACK (via rollback_hook callback)
- Rust/C: `rows_impacted` counter does NOT reset on ROLLBACK (xRollback is NULL)

This divergence doesn't break functionality but is a semantic difference that could matter for edge cases.

## Files to Modify
- `zig/src/rows_impacted.zig` — Remove `resetCounter()` call from `rollbackHookCallback`

## Acceptance Criteria
1. ROLLBACK does not reset `rows_impacted` counter
2. All 18 rows_impacted tests still pass
3. No regressions in other tests

## Parent Docs / Cross-links
- Related: TASK-157 (rows_impacted fix)
- Test: `zig/harness/test-rows-impacted-parity.sh`

## Progress Log
- 2025-12-21: Created from Round 59 divergence documentation.
- 2025-12-21: Verified fix already implemented during TASK-157.

## Completion Notes
**Already Fixed**: The `rollbackHookCallback` in `zig/src/rows_impacted.zig:60-65` does NOT call `resetCounter()`.

Current implementation (lines 57-65):
```zig
/// Rollback hook callback - resets pending db_version and seq
/// NOTE: rows_impacted is NOT reset on ROLLBACK (matches Rust/C oracle behavior
/// where xRollback is NULL in changes-vtab.c:173)
fn rollbackHookCallback(pArg: ?*anyopaque) callconv(.c) void {
    _ = pArg;
    site_identity.rollbackDbVersion();
    site_identity.resetSeq();
    // rows_impacted is intentionally NOT reset on ROLLBACK
}
```

Test verification:
- `bash zig/harness/test-rows-impacted-parity.sh` — 18/18 PASS
- Test 5 specifically confirms: "ROLLBACK -> counter is NOT reset" with "Values match between implementations"

Note: The test script `test-rows-impacted-parity.sh` has an outdated "KNOWN DIVERGENCE" message at the bottom that should be removed, but this is a documentation cleanup issue, not a behavior issue.

Completed: 2025-12-21
