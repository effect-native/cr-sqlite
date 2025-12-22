# TASK-159 — Fix crsql_commit_alter "failed to compact clock table" error

## Goal
Fix the ALTER TABLE tests that fail with "failed to compact clock table" error during `crsql_commit_alter()`.

## Status
- State: done
- Priority: medium (ALTER functionality broken)

## Context
Discovered during Round 59 (2025-12-21). After fixing rows_impacted, the ALTER tests fail:

```
Test 1: Basic Alter Flow (Add Column)
  FAIL: SQL error occurred
Error: stepping, crsql_commit_alter: failed to compact clock table

Test 2b: Triggers Re-enabled After commit_alter
  FAIL: SQL error occurred
Error: stepping, crsql_commit_alter: failed to compact clock table

Test 3b: Begin/Commit Alter Flow Works
  FAIL: SQL error occurred
Error: stepping, crsql_commit_alter: failed to compact clock table

Test 4: Changes Sync After Alter
  FAIL: SQL error occurred
Error: stepping, crsql_commit_alter: failed to compact clock table
```

4 out of 6 ALTER tests fail.

## Possible Root Causes
1. The `compactClockTable()` function in `schema_alter.zig` may be querying columns that don't exist
2. Schema mismatch between clock table expectations and actual schema
3. The column name `pk` vs `key` mismatch (we renamed to `key` in as_crr.zig)

## Files to Investigate
- `zig/src/schema_alter.zig` - `compactClockTable()` function
- `zig/src/as_crr.zig` - clock table schema definition
- `zig/harness/test-alter.sh` - test harness

## Acceptance Criteria
1. All 6 ALTER tests pass
2. No regressions in other tests (rows_impacted 18/18, cross-open 24/24)

## Parent Docs / Cross-links
- Related: TASK-157 (rows_impacted fix introduced this visibility)
- Related: TASK-147 (schema migration parent task)
- File: `zig/src/schema_alter.zig`

## Progress Log
- 2025-12-21: Created from Round 59 test results.
- 2025-12-21: Fixed. Root cause was schema mismatch between `schema_alter.zig` and `as_crr.zig`.

## Completion Notes

### Root Cause
The `schema_alter.zig` file had multiple schema mismatches with the actual tables created by `as_crr.zig`:

1. **`deleteOrphanedPkLookasides`** used column `pk` but the pks table has `__crsql_key`
2. **`createInsertTrigger`, `createUpdateTrigger`, `createDeleteTrigger`** functions in schema_alter.zig were duplicates that used a completely different schema:
   - Used `("pk", "pks")` columns but pks table has `(__crsql_key, <pk_columns...>)`
   - Used inline SQL for clock entries but as_crr.zig uses `crsql_after_*` helper functions

### Fix Applied
1. Fixed `deleteOrphanedPkLookasides` to use `__crsql_key` instead of `pk`
2. Made trigger functions in `as_crr.zig` public: `dropTriggers`, `createInsertTrigger`, `createUpdateTrigger`, `createDeleteTrigger`
3. Modified `schema_alter.zig` to import and use the as_crr trigger functions instead of maintaining duplicate (incorrect) implementations

### Files Modified
- `zig/src/as_crr.zig` - Made 4 functions public (`pub fn`)
- `zig/src/schema_alter.zig` - 
  - Added import for `as_crr`
  - Fixed `pk` → `__crsql_key` in deleteOrphanedPkLookasides
  - Removed duplicate trigger creation functions
  - Updated calls to use `as_crr.dropTriggers`, `as_crr.createInsertTrigger`, etc.

### Test Results
- ALTER tests: 6/6 PASS ✓
- rows_impacted tests: 18/18 PASS ✓
- cross-open tests: 24/24 PASS ✓
