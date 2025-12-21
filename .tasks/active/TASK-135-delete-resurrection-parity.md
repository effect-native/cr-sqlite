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

1. [ ] Test MR-041: Deleted row + insert merge (higher cl) -> Row resurrected
2. [ ] Test MR-042: cl=1 (live) vs cl=2 (deleted) -> Deleted wins
3. [ ] Test MR-043: cl=2 (deleted) vs cl=3 (resurrected) -> Resurrected wins
4. [ ] Both implementations produce identical cl values through lifecycle
5. [ ] Both implementations make identical winner decisions

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

## Completion Notes

(To be filled upon completion)
