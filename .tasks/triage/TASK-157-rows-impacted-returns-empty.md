# TASK-157 — Fix crsql_rows_impacted() returning empty string instead of integer

## Goal
Fix `crsql_rows_impacted()` to return proper integer values. Currently returns empty string, breaking 9 rows_impacted parity tests.

## Status
- State: triage
- Priority: high (blocking parity tests)

## Context
Discovered during build fix session (2025-12-21). After fixing compilation errors from TASK-149, the rows_impacted tests fail with:

```
Test: SingleInsertSingleTx
  FAIL: Expected 1, got: 
Test: ManyInsertsInATx
  FAIL: Expected 3, got: 
Test: CountResetsOnCommit
  FAIL: Expected 0 after commit, got: 
Test: UpdateThatDoesNotChangeAnything
  FAIL: Expected 0 for no-op, got: 
Test: LowerColVersionLoses
  FAIL: Expected 0, got: 
Test: ValueWin
  FAIL: Expected 1, got: 
Test: ClockWin
  FAIL: Expected 1, got: 
Test: Delete
  FAIL: Expected 1, got: 
Test: DeleteThatDoesNotChangeAnything
  FAIL: Expected 0, got: 
```

Note: The "got:" values are empty strings, not integers.

## Possible Root Causes
1. The `crsql_rows_impacted()` function may not be properly incrementing the counter
2. The counter may be getting reset unexpectedly
3. The function may be returning NULL/empty instead of the counter value
4. Changes to `changes_vtab.zig` may have broken the `rows_impacted.incrementRowsImpacted()` calls

## Files to Investigate
- `zig/src/rows_impacted.zig` - counter implementation
- `zig/src/changes_vtab.zig` - where `incrementRowsImpacted()` is called
- `zig/harness/test-parity.sh` - test harness (verify test expectations)

## Acceptance Criteria
1. All 9 rows_impacted tests pass:
   - SingleInsertSingleTx: returns 1
   - ManyInsertsInATx: returns 3
   - CountResetsOnCommit: returns 0 after commit
   - UpdateThatDoesNotChangeAnything: returns 0
   - LowerColVersionLoses: returns 0
   - ValueWin: returns 1
   - ClockWin: returns 1
   - Delete: returns 1
   - DeleteThatDoesNotChangeAnything: returns 0

2. `crsql_rows_impacted()` returns integer, not empty string

## Parent Docs / Cross-links
- Parent: TASK-154 (sync parity test failures)
- Related: TASK-149 build fix session
- File: `zig/src/rows_impacted.zig`

## Progress Log
- 2025-12-21: Created from build fix session. Observed empty return values.

## Completion Notes
(Empty until done.)
