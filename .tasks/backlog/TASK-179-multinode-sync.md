# TASK-179 — Multi-node "discord corrosion" scenario test

## Goal
Verify Zig handles complex multi-node sync patterns that caused production bugs.

## Status
- State: backlog
- Priority: high (real-world complexity)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
From Python `test_cl_merging.py::test_discord_report_corrosion`. This 4-node scenario caught bugs that simple 2-node tests missed.

## Files to Modify
- `zig/harness/test-multinode-sync.sh` (new, ~300 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Implement exact sequence from Python test
2. 4 databases (A, B, C, D) with interleaved operations
3. Bidirectional sync in various orders
4. Verify: all nodes converge to same state
5. Verify: no data loss or duplication
6. Zig and Rust/C produce identical final state

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-multinode-sync.sh - Complex multi-node scenarios

test_discord_corrosion() {
    # Create 4 databases
    # A: INSERT row
    # A→B sync
    # B→C sync
    # A: UPDATE row
    # B←A sync (reverse)
    # A: DELETE row
    # C→D sync
    # A→D sync
    # ... (full sequence from Python test)
    # Verify: all 4 converge
}

test_star_topology() {
    # Hub-and-spoke: A is hub
    # B, C, D all sync only with A
    # Operations on B, C, D
    # Sync through A
    # Verify: convergence
}
```

## Parent Docs / Cross-links
- Python tests: `py/correctness/tests/test_cl_merging.py`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
