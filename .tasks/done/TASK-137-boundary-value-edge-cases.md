# TASK-137: Add boundary value edge case tests

## Priority: P2 (SECONDARY)

## Summary

Test extreme values (MAX/MIN integers, large strings/blobs, unicode) round-trip
correctly through the sync process.

## Files to Modify

- `zig/harness/test-boundary-values.sh` (new file) - **CREATED**

## Acceptance Criteria

1. [x] Test EC-010: MAX_INT64 roundtrips through sync
2. [x] Test EC-011: MIN_INT64 roundtrips through sync
3. [x] Test EC-012: MAX_FLOAT roundtrips through sync
4. [x] Test EC-013: 1MB text roundtrips through sync
5. [x] Test EC-014: 1MB blob roundtrips through sync
6. [x] Test EC-020: Emoji roundtrips through sync
7. [x] Test EC-021: NULL bytes in text handled correctly
8. [x] All values identical after sync between implementations

## Test Template

```bash
# EC-010: MAX_INT64
MAX_INT=9223372036854775807
run_rust "INSERT INTO foo(id, value) VALUES(1, $MAX_INT);"

# Sync to Zig
CHANGES=$(run_rust "SELECT * FROM crsql_changes;")
run_zig "INSERT INTO crsql_changes VALUES($CHANGES);"

# Verify
ZIG_VALUE=$(run_zig "SELECT value FROM foo WHERE id=1;")
assert_equals "$MAX_INT" "$ZIG_VALUE" "MAX_INT64 preserved"

# EC-020: Emoji
run_rust "INSERT INTO foo(id, name) VALUES(2, '🎉🚀');"
# Sync and verify emoji preserved
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (EC-010 through EC-022)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card
- 2025-12-20: Created `zig/harness/test-boundary-values.sh` with all test cases

## Completion Notes

**Date**: 2025-12-20

**Test Script Created**: `zig/harness/test-boundary-values.sh`

**Test Results** (7 PASS, 1 FAIL):
- EC-010: MAX_INT64 (9223372036854775807) - **PASS**
- EC-011: MIN_INT64 (-9223372036854775808) - **PASS**
- EC-012: MAX_FLOAT (1.79769313486232e+308) - **PASS**
- EC-013: 1MB text - **PASS**
- EC-014: 1MB blob - **PASS**
- EC-020: Emoji (🎉🚀🌈🦄💯) - **PASS**
- EC-021: NULL bytes in text - **FAIL** (discovered bug)
- Bidirectional sync (Zig -> Rust) - **PASS**

**Bug Discovered**:
EC-021 revealed a parity issue: text containing embedded NUL bytes (`hello\0world`) 
is truncated at the NUL when synced through the Zig implementation. Rust preserves 
all 11 bytes, but Zig only preserves 5 bytes (up to the first NUL).

This is a real sync incompatibility that should be tracked as a follow-up task.

**Command to run**:
```bash
bash zig/harness/test-boundary-values.sh
```
