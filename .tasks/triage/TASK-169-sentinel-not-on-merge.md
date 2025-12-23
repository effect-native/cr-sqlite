# TASK-169 — Test sentinel NOT created during merge (sync)

## Goal
Verify Zig does NOT create new sentinel when applying remote changes.

## Status
- State: triage
- Priority: high (sync correctness)

## Context
From Python `test_sentinel_omission.py::test_not_created_on_merge`:
- When applying changes via INSERT INTO crsql_changes
- We should NOT create NEW sentinels
- We should only propagate existing sentinels

Creating sentinels during merge would corrupt CL tracking.

## Files to Modify
- `zig/harness/test-sentinel-parity.sh` (new or extend)

## Acceptance Criteria
1. Site A: INSERT row
2. Sync to Site B via crsql_changes
3. Verify: Site B has row but NO sentinel in its clock
4. Site A: DELETE row (creates sentinel CL=2)
5. Sync delete to Site B
6. Verify: Site B has sentinel with CL=2 (propagated, not new)
7. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_sentinel_omission.py`
- Related: TASK-166, TASK-167, TASK-168

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
