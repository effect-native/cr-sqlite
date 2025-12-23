# TASK-179 — Test "discord corrosion" 4-node scenario

## Goal
Verify Zig handles complex multi-node sync with interleaved operations.

## Status
- State: triage
- Priority: high (real-world complexity)

## Context
From Python `test_cl_merging.py::test_discord_report_corrosion`:
Complex 4-node scenario that caused data corruption in production:
- Node A, B, C, D
- A→B sync
- B→C sync
- A modifies
- B←A sync (reverse direction)
- Various interleaved operations

This catches subtle CL/merge bugs that simple 2-node tests miss.

## Files to Modify
- `zig/harness/test-multinode-sync.sh` (new)

## Acceptance Criteria
1. Implement the exact sequence from test_discord_report_corrosion
2. Run with Zig extension
3. Run with Rust/C oracle
4. Compare final state of all 4 nodes
5. Verify: data converges correctly
6. Verify: no "corrosion" (data loss or duplication)

## Parent Docs / Cross-links
- Python test: `py/correctness/tests/test_cl_merging.py`
- Related: TASK-165 (out-of-order sync)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
