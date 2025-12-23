# TASK-184 — Fix resurrection via sentinel for tombstoned rows

## Goal
Fix Zig implementation to resurrect tombstoned rows when receiving a sentinel with higher CL.

## Status
- State: triage
- Priority: HIGH (sync incompatibility)
- Discovered: Round 62 (TASK-161 test suite)

## Problem
When a tombstoned row (CL=2) receives a resurrection sentinel (CL=3), Zig does NOT resurrect the row. Rust/C correctly resurrects it.

**Test failure from `test-resurrection-parity.sh`:**
```
Test 2c: Row resurrected after sentinel merge
  FAIL: Resurrected row count - DIVERGENCE
    Zig:    0
    Rust/C: 1
    Expected: 1
```

## Scenario
1. Site A: INSERT row (CL=1) → DELETE row (CL=2) → INSERT row (CL=3) — resurrection
2. Site B: INSERT row (CL=1) → DELETE row (CL=2) — tombstoned
3. Site B receives resurrection sentinel (CL=3) from Site A
4. **Expected**: Row resurrected, CL=3
5. **Actual (Zig)**: Row stays tombstoned

## Root Cause (hypothesis)
The sentinel merge path in `zig/src/merge_insert.zig` likely doesn't handle the case where:
- Local row is tombstoned (has sentinel with lower CL)
- Incoming sentinel has higher CL
- Should trigger resurrection by clearing tombstone status

## Files to Modify
- `zig/src/merge_insert.zig` — sentinel handling in merge path
- Possibly `zig/src/changes_vtab.zig` — xUpdate path

## Acceptance Criteria
1. `bash zig/harness/test-resurrection-parity.sh` — Test 2 passes
2. All other resurrection tests still pass
3. No regressions in `make -C zig test-parity`

## Parent Docs / Cross-links
- Test: `zig/harness/test-resurrection-parity.sh` (Test 2: Dead via sentinel)
- Triggering task: `.tasks/done/TASK-161-resurrection-parity-suite.md`
- Python reference: `py/correctness/tests/test_cl_merging.py::test_resurrection_of_dead_thing_via_sentinel`

## Progress Log
- 2025-12-22: Created from Round 62 divergence discovery.

## Completion Notes
(Empty until done.)
