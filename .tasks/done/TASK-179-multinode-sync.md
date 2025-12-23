# TASK-179 — Multi-node "discord corrosion" scenario test

## Goal
Verify Zig handles complex multi-node sync patterns that caused production bugs.

## Status
- State: active
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
- 2025-12-22: Implemented `test-multinode-sync.sh` (~400 lines) with 3 tests:
  1. `test_discord_corrosion` - Exact sequence from Python test (3 nodes)
  2. `test_discord_4node` - Extended 4-node discord with out-of-order sync
  3. `test_star_topology` - Hub-and-spoke sync pattern
- 2025-12-22: Wired into `test-parity.sh`
- 2025-12-22: Test results:
  - Discord Corrosion: Zig PASS, Rust/C PASS, PARITY ✓
  - 4-Node Extended: Zig PASS, Rust/C PASS, PARITY ✓
  - Star Topology: Zig FAIL, Rust/C PASS, DIVERGENCE ✗
- 2025-12-22: **DISCOVERED DIVERGENCE** in Star Topology test - Zig produces
  different row data than Rust/C oracle. Nodes C and D have incorrect data.

## Completion Notes
### Files Created/Modified
- `zig/harness/test-multinode-sync.sh` (new, ~400 lines)
- `zig/harness/test-parity.sh` (added test invocation)

### Test Results Summary
```
Results: 5 passed, 1 failed, 0 skipped
```

### Divergences Found
1. **Star Topology Test**: Zig fails to converge correctly
   - Rust/C (correct): All nodes have `1|updated_by_b|b2|b3|b4` and `3|d1|d2|d3|d4`
   - Zig (wrong): Nodes have mixed/incorrect data:
     - Hub: `1|updated_by_b|c2|c3|c4` (wrong columns from C)
     - C: `1|c1|c2|c3|c4` (didn't get B's update)
     - D: Completely wrong rows (`2|...` instead of `1|...`)

2. **Minor observation**: In Discord Corrosion test step 8, Zig shows different
   col_version values (`2|2`) vs Rust/C (`3|3`), though final data converges.

### Commands to Reproduce
```bash
# Run just the multinode sync test
bash zig/harness/test-multinode-sync.sh

# Run full parity suite
bash zig/harness/test-parity.sh
```

### Next Steps (Triage)
The Star Topology divergence should be investigated as a potential sync bug in
the Zig implementation. The issue appears to be in how site_id filtering works
when multiple spokes sync through a hub.
