# TASK-166 — Test sentinel omission on INSERT

## Goal
Verify Zig does NOT emit sentinel (cid='-1') on normal INSERT operations.

## Status
- State: triage
- Priority: high (wire format parity)

## Context
From Python `test_sentinel_omission.py::test_omitted_on_insert`:
- INSERT should create clock entries for each column
- INSERT should NOT create a sentinel row (cid='-1')
- Sentinel is only for delete/resurrect tracking

## Files to Modify
- `zig/harness/test-sentinel-parity.sh` (new)

## Acceptance Criteria
1. INSERT a row into CRR table
2. Query crsql_changes
3. Verify: changes exist for each column
4. Verify: NO change with cid='-1' exists
5. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/test_sentinel_omission.py`
- Related: TASK-167, TASK-168, TASK-169

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
