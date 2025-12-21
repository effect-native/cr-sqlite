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
- [ ] Deterministic regression tests exist for all divergences found in TASK-127.
- [ ] Zig implementation passes these new tests.
- [ ] `make -C zig test-parity` includes these new tests.

## Parent Docs
- `research/zig-cr/92-gap-backlog.md`
- `.tasks/backlog/TASK-127-experimental-parity-invalidation.md`
