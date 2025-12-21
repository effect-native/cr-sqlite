# TASK-134: Add merge value comparison parity tests

## Priority: P1 (CRITICAL)

## Summary

When `col_version` is equal between local and remote, the implementations must use
the same value comparison algorithm to determine the winner. This tests that behavior
for all SQLite types.

## Files to Modify

- `zig/harness/test-merge.sh` (add value comparison section)
  OR
- `zig/harness/test-merge-value-parity.sh` (new file)

## Acceptance Criteria

1. [ ] Test MR-020: String comparison (lexicographic) - 'apple' vs 'banana'
2. [ ] Test MR-021: Integer comparison - 100 vs 99
3. [ ] Test MR-022: NULL vs value - document winner
4. [ ] Test MR-023: Value vs NULL - document winner
5. [ ] Test MR-024: Float comparison - 3.14 vs 3.15
6. [ ] Test MR-025: Blob comparison - X'AA' vs X'BB'
7. [ ] All tests verify Zig matches C/Rust winner selection

## Test Template

```bash
# MR-020: String comparison
# Setup: Insert 'apple', sync with 'banana' at same cv
# Both should select 'banana' (lexicographically larger)

# 1. Create local row with 'apple'
run_rust "INSERT INTO foo(id, name) VALUES(1, 'apple');"
run_zig "INSERT INTO foo(id, name) VALUES(1, 'apple');"

# 2. Get local state
LOCAL_CV=$(run_both "SELECT col_version FROM foo__crsql_clock WHERE col_name='name';")

# 3. Merge remote 'banana' with same cv
REMOTE_SITE=$(gen_random_site_id)
run_rust "INSERT INTO crsql_changes VALUES('foo', pk, 'name', 'banana', $LOCAL_CV, 99, $REMOTE_SITE, 1, 0);"
run_zig "INSERT INTO crsql_changes VALUES('foo', pk, 'name', 'banana', $LOCAL_CV, 99, $REMOTE_SITE, 1, 0);"

# 4. Verify both selected 'banana'
RUST_VALUE=$(run_rust "SELECT name FROM foo WHERE id=1;")
ZIG_VALUE=$(run_zig "SELECT name FROM foo WHERE id=1;")
compare "$RUST_VALUE" "$ZIG_VALUE" "String comparison winner"
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (MR-020 through MR-025)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card

## Completion Notes

(To be filled upon completion)
