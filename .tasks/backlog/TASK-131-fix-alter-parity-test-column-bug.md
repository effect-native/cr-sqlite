# TASK-131: Fix test-alter-parity.sh column name bug

## Priority: P0 (BLOCKING)

## Summary

The `test-alter-parity.sh` script queries the wrong column name for Zig clock tables,
causing 10 false test failures. Same bug as TASK-130.

## Files to Modify

- `zig/harness/test-alter-parity.sh`

## Acceptance Criteria

1. [ ] Find and fix all `pk` references in clock table queries
2. [ ] Run test-alter-parity.sh and verify tests pass
3. [ ] If any tests fail after fix, those are REAL parity gaps (document them)

## Bug Details

The test uses `pk` when querying Zig clock tables but both implementations use `key`.

## Experiments Unblocked

- AT-001 through AT-004 (ALTER TABLE experiments)

## Parent Docs / Cross-links

- Analysis: `research/zig-cr/97-test-gap-analysis.md`
- Related: TASK-130 (same bug, different file)

## Progress Log

- 2024-12-20: Created task card

## Completion Notes

(To be filled upon completion)
