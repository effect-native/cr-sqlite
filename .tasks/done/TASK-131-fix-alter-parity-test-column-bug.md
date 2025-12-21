# TASK-131: Fix test-alter-parity.sh column name bug

## Priority: P0 (BLOCKING)

## Summary

The `test-alter-parity.sh` script queries the wrong column name for Zig clock tables,
causing 10 false test failures. Same bug as TASK-130.

## Files to Modify

- `zig/harness/test-alter-parity.sh`

## Acceptance Criteria

1. [x] Find and fix all `pk` references in clock table queries
2. [x] Run test-alter-parity.sh and verify tests pass
3. [x] If any tests fail after fix, those are REAL parity gaps (document them)

## Bug Details

The test uses `pk` when querying Zig clock tables but both implementations use `key`.

## Experiments Unblocked

- AT-001 through AT-004 (ALTER TABLE experiments)

## Parent Docs / Cross-links

- Analysis: `research/zig-cr/97-test-gap-analysis.md`
- Related: TASK-130 (same bug, different file)

## Progress Log

- 2024-12-20: Created task card
- 2024-12-20: Fixed column name bug, all 19 tests pass

## Completion Notes

**Changes Made:**
- Fixed 3 Zig clock table queries using wrong column name `pk` instead of `key`
- Updated 4 comments that incorrectly stated Zig uses "pk" column
- Locations fixed:
  - Line 97: `compare_clocks()` - Zig query now uses `key AS pk`
  - Line 560: Test 9 pre-alter Zig query now uses `key AS pk`  
  - Line 568: Test 9 post-alter Zig query now uses `key AS pk`

**Test Results:**
- **19 PASSED, 0 FAILED**
- All 10 ALTER TABLE parity tests pass
- No REAL parity gaps discovered - Zig implementation matches Rust/C oracle

**Tests Verified:**
1. ADD COLUMN (nullable) ✓
2. ADD COLUMN with DEFAULT ✓
3. DROP COLUMN ✓
4. ADD INDEX / DROP INDEX ✓
5. ALTER on empty table ✓
6. ALTER on 1000+ rows ✓
7. Multiple ALTERs in sequence ✓
8. ADD COLUMN then UPDATE ✓
9. Clock history preservation ✓
10. New column backfill behavior ✓
