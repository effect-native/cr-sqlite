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

1. [ ] Test ST-002: 100k changes batch - memory stays bounded
2. [ ] Test ST-003: 1000 concurrent row operations - no deadlock
3. [ ] Test ST-004: Rapid INSERT/DELETE cycles - clock stays consistent

## Notes

These tests may take significant time to run. Consider:
- Separate CI job with longer timeout
- Opt-in via environment variable (STRESS_TESTS=1)

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (ST-002 through ST-004)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card

## Completion Notes

(To be filled upon completion)
