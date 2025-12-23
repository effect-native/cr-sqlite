# TASK-187 — Fix star topology sync convergence failure

## Goal
Fix Zig implementation to correctly converge in hub-and-spoke (star) topology sync patterns.

## Status
- State: triage
- Priority: HIGH (multi-node sync broken)
- Discovered: Round 62 (TASK-179 test suite)

## Problem
In a hub-and-spoke topology where all nodes sync only through a central hub, Zig nodes fail to converge to the same state. Rust/C converges correctly.

**Test failure from `test-multinode-sync.sh`:**
```
Test 3: Star topology - FAIL

  Hub data: 1|updated_by_b|c2|c3|c4
            3|d1|d2|d3|d4
  B data:   1|updated_by_b|c2|c3|c4
            3|d1|d2|d3|d4
  C data:   1|c1|c2|c3|c4           <-- wrong! didn't get B's update
            3|d1|d2|d3|d4
  D data:   2|d1|d2|d3|d4           <-- completely wrong rows
            3|updated_by_b|b2|b3|b4

  FAIL: Hub and C diverged
  FAIL: Hub and D diverged
```

## Scenario
1. Create 4 databases: Hub, B, C, D
2. B, C, D each create unique rows
3. All sync to Hub (Hub has all rows)
4. Hub syncs back to all spokes (all should have same data)
5. B updates row 1, C deletes row 2
6. Sync through Hub again
7. **Expected**: All 4 nodes converge to same state
8. **Actual (Zig)**: C didn't get B's update, D has completely wrong data

## Root Cause (hypothesis)
Likely issues:
1. Site ID filtering not correctly applied when relaying changes through hub
2. Version vector not properly tracking which changes came from which site
3. Possible confusion between local vs remote site_id in change application

## Files to Modify
- `zig/src/changes_vtab.zig` — site_id filtering in xFilter/xUpdate
- `zig/src/merge_insert.zig` — change application with site_id tracking
- Possibly `zig/src/site_identity.zig` — site ordinal handling

## Acceptance Criteria
1. `bash zig/harness/test-multinode-sync.sh` — Test 3 (star topology) passes
2. All other multinode tests still pass
3. No regressions in `make -C zig test-parity`

## Parent Docs / Cross-links
- Test: `zig/harness/test-multinode-sync.sh` (Test 3: Star topology)
- Triggering task: `.tasks/done/TASK-179-multinode-sync.md`
- Python reference: `py/correctness/tests/test_cl_merging.py`

## Progress Log
- 2025-12-22: Created from Round 62 divergence discovery.

## Completion Notes
(Empty until done.)
