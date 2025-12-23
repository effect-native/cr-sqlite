# TASK-163 — Test resurrection of deleted row via column value

## Goal
Verify Zig matches Rust/C oracle when a column update resurrects a deleted row.

## Status
- State: triage
- Priority: high (cross-impl parity, CL semantics)

## Context
From Python `test_cl_merging.py::test_resurrection_of_dead_thing_via_non_sentinel`:
- A row was deleted (tombstone exists)
- A column value change arrives with higher CL
- Expected: row is resurrected with that column value

This is the tricky case where a column update must also resurrect.

## Files to Modify
- `zig/harness/test-resurrection-parity.sh` (new or extend)

## Acceptance Criteria
1. Create row, delete it (CL=2 tombstone)
2. From a different site, send UPDATE with CL=3
3. Verify: row is resurrected
4. Verify: column has the new value
5. Verify: clock shows CL=3
6. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_cl_merging.py`
- Related: TASK-161, TASK-162, TASK-163

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
