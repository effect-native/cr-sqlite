# TASK-162 — Test resurrection of deleted row via sentinel

## Goal
Verify Zig matches Rust/C oracle when a sentinel resurrects a previously-deleted row.

## Status
- State: triage
- Priority: high (cross-impl parity, CL semantics)

## Context
From Python `test_cl_merging.py::test_resurrection_of_dead_thing_via_sentinel`:
- A row is deleted (tombstone exists)
- A sentinel change arrives with higher CL
- Expected: row is resurrected (tombstone cleared)

## Files to Modify
- `zig/harness/test-resurrection-parity.sh` (new or extend)

## Acceptance Criteria
1. Create row, then delete it (CL=2 tombstone)
2. Sync tombstone to Site B
3. Site A resurrects via INSERT (CL=3 sentinel)
4. Sync resurrection to Site B
5. Verify: row is live on both sites
6. Verify: clock table shows CL=3
7. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_cl_merging.py`
- Related: TASK-161, TASK-163, TASK-164

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
