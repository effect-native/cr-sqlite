# TASK-161 — Test resurrection of live row via sentinel

## Goal
Verify Zig matches Rust/C oracle when a sentinel (cid='-1') change is applied to an already-live row.

## Status
- State: triage
- Priority: high (cross-impl parity, CL semantics)

## Context
From Python `test_cl_merging.py::test_resurrection_of_live_thing_via_sentinel`:
- A row exists and is live
- A sentinel change arrives with higher CL
- Expected: row stays live, CL is updated

This tests the interaction between causal length and sentinel handling.

## Files to Modify
- `zig/harness/test-resurrection-parity.sh` (new)

## Acceptance Criteria
1. Test creates row on Site A
2. Site B receives row via sync
3. Site A deletes row (creates sentinel with CL=2)
4. Site A re-inserts row (creates sentinel with CL=3)
5. Meanwhile Site B still has live row (CL=1)
6. Site B receives resurrection sentinel (CL=3)
7. Verify: row is live on both, CL matches
8. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_cl_merging.py`
- Related: TASK-162, TASK-163, TASK-164
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
