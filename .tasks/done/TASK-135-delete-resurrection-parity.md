# TASK-135: Add delete/resurrection parity tests

## Priority: P1 (CRITICAL)

## Summary

Test that the full row lifecycle (insert -> delete -> resurrect) produces identical
causal length (cl) values in both implementations, and that cl comparison correctly
determines winners.

## Files to Modify

- `zig/harness/test-resurrection.sh` (expand existing)
  OR
- `zig/harness/test-cl-parity.sh` (new file)

## Acceptance Criteria

1. [x] Test MR-041: Deleted row + insert merge (higher cl) -> Row resurrected
2. [x] Test MR-042: cl=1 (live) vs cl=2 (deleted) -> Deleted wins
3. [x] Test MR-043: cl=2 (deleted) vs cl=3 (resurrected) -> Resurrected wins
4. [x] Both implementations produce identical cl values through lifecycle
5. [x] Both implementations make identical winner decisions

## Test Template

```bash
# MR-042: Live vs Deleted
# Local: cl=1 (row exists), cv=5
# Remote: cl=2 (row deleted), cv=1
# Expected: Remote wins (cl=2 > cl=1), row deleted

# Setup local live row
run_both "INSERT INTO foo VALUES(1, 'test');"
# Verify local cl=1
LOCAL_CL=$(run_both "SELECT cl FROM foo__crsql_clock WHERE col_name='-1' OR ...;")

# Merge delete from remote with cl=2
run_both "INSERT INTO crsql_changes VALUES('foo', pk, '-1', NULL, 1, 99, remote_site, 2, 0);"

# Verify row deleted
ROW_COUNT=$(run_both "SELECT COUNT(*) FROM foo WHERE id=1;")
compare "0" "$ROW_COUNT" "Row should be deleted"

# MR-043: Deleted vs Resurrected
# Continue from above state (local cl=2, deleted)
# Merge resurrection with cl=3
run_both "INSERT INTO crsql_changes VALUES('foo', pk, '-1', NULL, 1, 99, remote_site, 3, 0);"
run_both "INSERT INTO crsql_changes VALUES('foo', pk, 'name', 'resurrected', 1, 99, remote_site, 3, 1);"

# Verify row exists with new value
ROW_COUNT=$(run_both "SELECT COUNT(*) FROM foo WHERE id=1;")
VALUE=$(run_both "SELECT name FROM foo WHERE id=1;")
compare "1" "$ROW_COUNT" "Row should exist"
compare "resurrected" "$VALUE" "Row should have new value"
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (MR-041 through MR-043)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`
- Existing: `zig/harness/test-resurrection.sh`

## Progress Log

- 2024-12-20: Created task card
- 2024-12-20: Implemented `zig/harness/test-cl-parity.sh` with 17 tests

## Completion Notes

**Date**: 2024-12-20

**Implementation**: Created `zig/harness/test-cl-parity.sh`

**Test Results**: All 17 tests PASS

**Tests Implemented**:
1. **Test 1: CL Lifecycle Values Parity** (3 tests)
   - 1a: CL after INSERT matches (cl=1)
   - 1b: CL after DELETE matches (cl=2)
   - 1c: Row deleted in both implementations
   
2. **Test 2: MR-042 - Live vs Deleted** (3 tests)
   - 2a: Verify local cl=1 before merge
   - 2b: Row deleted after remote cl=2 merge
   - 2c: CL updated to 2 after merge
   
3. **Test 3: MR-043 - Deleted vs Resurrected** (4 tests)
   - 3a: Verify local tombstone cl=2
   - 3b: Row resurrected after remote cl=3 merge
   - 3c: Resurrected row has correct value
   - 3d: CL updated to 3 after resurrection
   
4. **Test 4: MR-041 - Full Lifecycle Resurrection Parity** (4 tests)
   - 4a: Starting state (deleted, cl=2)
   - 4b: Row resurrected after Node B merge
   - 4c: Resurrected row has Node B's value
   - 4d: Final CL is 3
   
5. **Test 5: Lower CL Loses** (2 tests)
   - 5a: Row stays deleted (local cl=2 beats remote cl=1)
   - 5b: CL unchanged at 2
   
6. **Test 6: CL in crsql_changes output parity** (1 test)
   - Verifies crsql_changes reports identical cl values

**Key Findings**:
- Both Zig and Rust/C implementations produce identical CL values through the full lifecycle
- Both implementations make identical winner decisions based on CL comparison
- Resurrection logic works correctly when higher CL is received
- Lower CL changes are correctly rejected
- The `foo__crsql_clock` table uses `key` column (not `pk`) for the primary key
- Sentinel row (`col_name='-1'`) only exists after delete (tombstone)
- For live rows, CL is read from `crsql_changes` virtual table
