# TASK-191 — Port Python Hypothesis Tests to Zig Parity Suite

## Goal
Port the Python property-based tests (`py/correctness/`) to the bash parity harness to invalidate "Zig parity is complete".

## Status
- State: triage
- Priority: HIGH (these tests were designed to find edge cases)
- Discovered: 2025-12-23 (hypothesis invalidation request)

## Hypothesis to Invalidate
The Python tests use `hypothesis` library for property-based testing. They may cover scenarios our bash tests miss.

## Existing Python Tests
Located in `py/correctness/tests/`:
- `test_cl_merging.py` — Causal length merge logic (~1000 lines)
- `test_sentinel_omission.py` — Sentinel emission rules
- `test_sync.py` — Sync protocol edge cases

## Test Approach
1. **Analyze Python tests** for scenarios not covered by bash harness
2. **Identify key properties** being tested:
   - CL merge resolution rules
   - Sentinel creation/omission conditions
   - Multi-peer sync convergence
3. **Translate to bash tests** that compare Zig vs Rust/C oracle

## Files to Create/Modify
- `zig/harness/test-cl-merge-properties.sh` (new)
- `zig/harness/test-sentinel-properties.sh` (new)

## Acceptance Criteria
1. Port at least 3 key property tests from each Python file
2. Run against both Zig and Rust/C oracle
3. Either find divergence OR increase confidence

## Parent Docs / Cross-links
- Python tests: `py/correctness/tests/`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.

## Completion Notes
(Empty until done.)
