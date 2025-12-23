# TASK-165 — Test out-of-order sync with delete/resurrect interleaving

## Goal
Verify Zig handles out-of-order change arrival where deletes and resurrections interleave.

## Status
- State: triage
- Priority: high (cross-impl parity, production scenario)

## Context
From Python `test_cl_merging.py::test_pr_299_scenario`:
Real-world scenario where changes arrive out of order due to network delays.

Sequence:
1. Site A: INSERT row
2. Site A: DELETE row
3. Site A: INSERT row (resurrect)
4. Site B receives changes in order: 1, 3, 2 (delete arrives last)

Expected: Row should be live (resurrection has higher CL than delete).

## Files to Modify
- `zig/harness/test-resurrection-parity.sh` (new or extend)

## Acceptance Criteria
1. Simulate out-of-order arrival by manually ordering INSERT INTO crsql_changes
2. Send: INSERT (CL=1), then RESURRECT (CL=3), then DELETE (CL=2)
3. Verify: row is live (higher CL wins)
4. Verify: idempotent (re-apply same changes, same result)
5. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_cl_merging.py`
- GitHub PR: #299 scenario
- Related: TASK-161 through TASK-164

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
