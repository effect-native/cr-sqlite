# TASK-167 — Test sentinel created on DELETE

## Goal
Verify Zig creates sentinel (cid='-1') when a row is deleted.

## Status
- State: triage
- Priority: high (wire format parity)

## Context
From Python `test_sentinel_omission.py::test_created_on_delete`:
- DELETE should create a sentinel row (cid='-1') in clock table
- This sentinel marks the row as tombstoned
- The sentinel has a CL value for resurrection comparison

## Files to Modify
- `zig/harness/test-sentinel-parity.sh` (new or extend)

## Acceptance Criteria
1. INSERT a row into CRR table
2. DELETE the row
3. Query crsql_changes
4. Verify: sentinel change with cid='-1' exists
5. Verify: sentinel has correct CL (should be 2)
6. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_sentinel_omission.py`
- Related: TASK-166, TASK-168, TASK-169

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
