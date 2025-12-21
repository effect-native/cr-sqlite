# TASK-133: Add PK blob format edge case parity tests

## Priority: P1 (CRITICAL)

## Summary

Add oracle parity tests for PK blob encoding in `crsql_changes` with non-integer PKs:
- Text primary keys
- Blob primary keys  
- Compound PKs with mixed types
- Unicode text PKs

## Files to Modify

- `zig/harness/test-oracle-parity.sh` (add new test section)
  OR
- `zig/harness/test-pk-blob-parity.sh` (new file)

## Acceptance Criteria

1. [ ] Test WF-021: Single text PK encoding matches
2. [ ] Test WF-022: Single blob PK encoding matches
3. [ ] Test WF-023: Compound PK (int, int) encoding matches
4. [ ] Test WF-024: Compound PK (int, text) encoding matches
5. [ ] Test WF-025: Compound PK (int, text, blob) encoding matches
6. [ ] Test WF-026: Unicode text PK encoding matches
7. [ ] All tests run as part of CI

## Test Template

```bash
# WF-021: Text PK
setup_rust "CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL); SELECT crsql_as_crr('t');"
setup_zig "CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL); SELECT crsql_as_crr('t');"

run_rust "INSERT INTO t VALUES('hello');"
run_zig "INSERT INTO t VALUES('hello');"

RUST_PK=$(run_rust "SELECT hex(pk) FROM crsql_changes WHERE [table]='t';")
ZIG_PK=$(run_zig "SELECT hex(pk) FROM crsql_changes WHERE [table]='t';")
compare "$RUST_PK" "$ZIG_PK" "Text PK encoding"

# WF-026: Unicode text PK
run_rust "INSERT INTO t VALUES('🎉');"
run_zig "INSERT INTO t VALUES('🎉');"
# Compare pk blobs
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (WF-021 through WF-027)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card

## Completion Notes

(To be filled upon completion)
