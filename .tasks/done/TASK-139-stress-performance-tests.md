# TASK-139: Add stress/performance tests

## Priority: P3 (NICE TO HAVE)

## Summary

Add tests for performance edge cases to ensure implementations behave similarly
under load.

## Files to Modify

- `zig/harness/test-large-data.sh` (expand)
  OR
- `zig/harness/test-stress.sh` (new file)

## Acceptance Criteria

1. [x] Test ST-002: 100k changes batch - memory stays bounded
2. [x] Test ST-003: 1000 concurrent row operations - no deadlock
3. [x] Test ST-004: Rapid INSERT/DELETE cycles - clock stays consistent

## Notes

These tests may take significant time to run. Consider:
- Separate CI job with longer timeout
- Opt-in via environment variable (STRESS_TESTS=1)

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (ST-002 through ST-004)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card
- 2024-12-20: Implemented `zig/harness/test-stress.sh`

## Completion Notes

**Date:** 2024-12-20

**Implementation:**
Created `zig/harness/test-stress.sh` with three stress test scenarios:

1. **ST-002: Large Batch Changes**
   - Tests 100k inserts (or 10k in CI mode) in a single transaction
   - Verifies memory stays bounded (completes without OOM)
   - Validates row count, changes count, and db_version

2. **ST-003: Concurrent Row Operations**
   - Tests 1000 rows (or 100 in CI mode) with INSERT + UPDATE + UPDATE cycles
   - Uses timeout to detect deadlocks
   - Validates row count, counter values, data updates, and clock table

3. **ST-004: Rapid INSERT/DELETE Cycles**
   - Tests 100 cycles (or 20 in CI mode) of INSERT-DELETE on same row
   - Validates final value, db_version advance, causal length (cl), and changes table
   - Verifies clock state is valid for merge

**Design decisions:**
- Opt-in full stress mode via `STRESS_TESTS=1` environment variable
- CI mode uses reduced iterations for faster runs (10k/100/20 vs 100k/1000/100)
- Uses `.tmp/test-stress/` for temp files (never `/tmp/`)
- Uses `nix run nixpkgs#sqlite` for clean Zig extension loading
- 60-second timeout for deadlock detection

**Test Results (CI mode):**
```
ST-002: 10k inserts in 0.19s - PASS
ST-003: 100 rows x 3 ops in 0.10s - PASS
ST-004: 20 cycles in 0.09s - PASS
Total: 12/12 tests passed
```
