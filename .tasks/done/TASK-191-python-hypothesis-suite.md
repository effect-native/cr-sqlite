# TASK-191 — Port Python Hypothesis Tests to Zig Parity Suite

## Goal
Port the Python property-based tests (`py/correctness/`) to the bash parity harness to invalidate "Zig parity is complete".

## Status
- State: done
- Priority: HIGH (these tests were designed to find edge cases)
- Discovered: 2025-12-23 (hypothesis invalidation request)
- Completed: 2025-12-25

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
- 2025-12-25: Analyzed Python Hypothesis tests:
  - `test_cl_merging.py` — ~1014 lines covering CL merge rules, resurrection, PKO tables
  - `test_sentinel_omission.py` — ~140 lines covering sentinel emission rules
  - `test_sync.py` — ~566 lines covering sync protocol, defaults, merging
- 2025-12-25: Created `zig/harness/test-cl-merge-properties.sh` with 6 property tests
- 2025-12-25: Created `zig/harness/test-sentinel-properties.sh` with 8 property tests
- 2025-12-25: All 33 test assertions pass (18 CL + 15 sentinel)

## Completion Notes
### Properties Ported from Python Hypothesis Tests

**CL Merge Properties (test-cl-merge-properties.sh):**
1. Larger CL always wins regardless of col_version (test_larger_cl_wins_all)
2. Same CL uses col_version as tiebreaker (test_larger_col_version_same_cl)
3. Same CL + col_version uses value as tiebreaker (test_larger_col_value_same_cl_and_col_version)
4. Equivalent states merge as no-op (test_equivalent_delete_cls_is_noop)
5. Three-node proxy topology converges (test_ordered_delta_merge_proxy)
6. Primary-key only tables sync correctly (test_pko_*)

**Sentinel Properties (test-sentinel-properties.sh):**
1. No sentinel on INSERT (test_omitted_on_insert)
2. Sentinel created on DELETE (test_created_on_delete)
3. No sentinel on REPLACE (test_not_created_on_replace)
4. No sentinel on merge (test_not_created_on_merge)
5. No sentinel on noop merge (test_not_created_on_noop_merge)
6. Delete sentinel propagates correctly (test_sentinel_propagated_when_present)
7. Default value merge behavior (test_merging_on_defaults)
8. Update merge without creating sentinel (test_not_created_on_update_merge)

### Test Results
```
CL Merge Properties: 18 passed, 0 failed, 0 skipped
Sentinel Properties: 15 passed, 0 failed, 0 skipped
Total: 33 test assertions passed
```

### Divergences Found
**None.** The Zig implementation matches the Rust/C oracle for all tested properties.

### Key Python Properties NOT Yet Ported (Future Work)
- Random out-of-order merge (test_out_of_order_merge) — requires randomization
- Bidirectional random merge (test_out_of_order_merge_bidi)
- merge-equal-values config (test_merge_same_w_tie_breaker) — config flag support
- Discord/Corrosion edge case (test_discord_report_corrosion) — complex multi-step scenario
