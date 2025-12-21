# TASK-128: Expand parity suite with invalidation findings

## Goal
Once TASK-127 has identified divergences (invalidating the "full parity" hypothesis), we must expand our regression test suite to cover these edge cases permanently.

## Scope
- Analyze the divergence(s) found in TASK-127.
- Create deterministic reproduction cases in the appropriate `zig/harness/test-*.sh` script (or create a new one if needed).
- Fix the divergence in the Zig implementation (if it's a bug) or document it as a known limitation.
- Verify the fix with the new test case.

## Files to Modify
- `zig/harness/test-*.sh` (existing suites)
- `zig/src/*.zig` (implementation fixes)

## Acceptance Criteria
- [x] Deterministic regression tests exist for all divergences found in TASK-127.
- [x] Zig implementation passes these new tests.
- [x] `make -C zig test-parity` includes these new tests.

## Parent Docs
- `research/zig-cr/92-gap-backlog.md`
- `.tasks/done/TASK-127-experimental-parity-invalidation.md`

## Completion Notes

### 2024-12-20: Task Completed

Created `zig/harness/test-edge-cases.sh` with 6 deterministic regression tests covering:
1. Empty blob via INSERT
2. Empty blob via UPDATE
3. Empty string vs empty blob distinction
4. NULL vs empty blob vs empty string
5. Sync round-trip (Zig -> Rust/C)
6. `typeof()` correctness

All tests pass (6/6).
This suite effectively covers the divergence found in TASK-127.

### 2024-12-21: Finalized integration

- Improved test script with separate setup/query helpers for clean output
- Added test-edge-cases.sh to test-parity.sh header comments and execution section
- Tests wired in and run successfully as part of the full parity suite

### Files Modified
- `zig/harness/test-edge-cases.sh` (improved output handling)
- `zig/harness/test-parity.sh` (wired in edge case tests)
