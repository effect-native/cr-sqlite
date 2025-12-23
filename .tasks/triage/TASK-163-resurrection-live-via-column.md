# TASK-163 — Test resurrection of live row via column value

## Goal
Verify Zig matches Rust/C oracle when a column update (not sentinel) arrives for an already-live row.

## Status
- State: triage
- Priority: high (cross-impl parity, CL semantics)

## Context
From Python `test_cl_merging.py::test_resurrection_of_live_thing_via_non_sentinel`:
- A row exists and is live
- A column value change arrives with higher CL
- Expected: column is updated, CL is updated

This is the normal UPDATE case but with explicit CL verification.

## Files to Modify
- `zig/harness/test-resurrection-parity.sh` (new or extend)

## Acceptance Criteria
1. Create row with col='original' on Site A
2. Sync to Site B
3. Site A updates col='updated' (col_version=2)
4. Site B receives update
5. Verify: both have col='updated'
6. Verify: clock shows correct col_version and CL
7. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_cl_merging.py`
- Related: TASK-161, TASK-162, TASK-164

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
