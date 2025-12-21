# TASK-137: Add boundary value edge case tests

## Priority: P2 (SECONDARY)

## Summary

Test extreme values (MAX/MIN integers, large strings/blobs, unicode) round-trip
correctly through the sync process.

## Files to Modify

- `zig/harness/test-edge-cases.sh` (expand)
  OR
- `zig/harness/test-boundary-values.sh` (new file)

## Acceptance Criteria

1. [ ] Test EC-010: MAX_INT64 roundtrips through sync
2. [ ] Test EC-011: MIN_INT64 roundtrips through sync
3. [ ] Test EC-012: MAX_FLOAT roundtrips through sync
4. [ ] Test EC-013: 1MB text roundtrips through sync
5. [ ] Test EC-014: 1MB blob roundtrips through sync
6. [ ] Test EC-020: Emoji roundtrips through sync
7. [ ] Test EC-021: NULL bytes in text handled correctly
8. [ ] All values identical after sync between implementations

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

## Completion Notes

(To be filled upon completion)
