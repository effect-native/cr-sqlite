# TASK-168 — Test sentinel NOT created on INSERT OR REPLACE

## Goal
Verify Zig does NOT create sentinel on INSERT OR REPLACE.

## Status
- State: triage
- Priority: medium (edge case)

## Context
From Python `test_sentinel_omission.py::test_not_created_on_replace`:
- INSERT OR REPLACE is logically an UPDATE (or INSERT if new)
- It should NOT create a sentinel
- Only explicit DELETE creates sentinel

## Files to Modify
- `zig/harness/test-sentinel-parity.sh` (new or extend)

## Acceptance Criteria
1. INSERT a row
2. INSERT OR REPLACE same PK with different values
3. Query crsql_changes
4. Verify: column changes exist
5. Verify: NO sentinel (cid='-1') exists
6. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_sentinel_omission.py`
- Related: TASK-166, TASK-167, TASK-169

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
