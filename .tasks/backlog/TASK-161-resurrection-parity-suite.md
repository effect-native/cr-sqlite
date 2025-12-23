# TASK-161 — Resurrection parity test suite (consolidated)

## Goal
Create comprehensive resurrection tests verifying Zig matches Rust/C oracle for all CL (causal length) scenarios.

## Status
- State: backlog
- Priority: high (cross-impl parity, CL semantics)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
Consolidates TASK-161 through TASK-165 into a single test file. These scenarios from Python `test_cl_merging.py` are not covered in Zig harness:

1. **Live row via sentinel**: Sentinel arrives for already-live row
2. **Dead row via sentinel**: Sentinel resurrects tombstoned row
3. **Live row via column**: Column update on live row (normal case with CL verification)
4. **Dead row via column**: Column update resurrects tombstoned row
5. **Out-of-order sync**: Changes arrive in wrong order (delete after resurrect)

## Files to Modify
- `zig/harness/test-resurrection-parity.sh` (new, ~400 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Each of 5 scenarios implemented as separate test function
2. Each test runs against both Zig and Rust/C oracle
3. Each test compares final state (data, clock entries, CL values)
4. All tests PASS with identical behavior
5. Test output clearly documents any divergences found

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-resurrection-parity.sh - CL resurrection scenarios

test_live_via_sentinel() {
    # Site A: INSERT row (CL=1)
    # Site A: DELETE row (CL=2) 
    # Site A: INSERT row (CL=3) - resurrection
    # Site B: has live row (CL=1)
    # Site B: receives resurrection sentinel (CL=3)
    # Verify: both live, CL=3
}

test_dead_via_sentinel() {
    # Create, delete (tombstone CL=2)
    # Send resurrection sentinel (CL=3)
    # Verify: resurrected, CL=3
}

test_live_via_column() {
    # Normal UPDATE case but verify CL advances
}

test_dead_via_column() {
    # Tombstoned row receives column update with higher CL
    # Should resurrect with that column value
}

test_out_of_order() {
    # Send changes in order: INSERT(CL=1), RESURRECT(CL=3), DELETE(CL=2)
    # Verify: row is live (CL=3 wins)
}
```

## Parent Docs / Cross-links
- Python tests: `py/correctness/tests/test_cl_merging.py`
- Supersedes: TASK-162, TASK-163, TASK-164, TASK-165
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Consolidated from 5 individual tasks for efficient parallel execution.

## Completion Notes
(Empty until done.)
