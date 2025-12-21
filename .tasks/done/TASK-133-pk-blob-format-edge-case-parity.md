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

1. [x] Test WF-021: Single text PK encoding matches
2. [x] Test WF-022: Single blob PK encoding matches
3. [x] Test WF-023: Compound PK (int, int) encoding matches
4. [x] Test WF-024: Compound PK (int, text) encoding matches
5. [x] Test WF-025: Compound PK (int, text, blob) encoding matches
6. [x] Test WF-026: Unicode text PK encoding matches
7. [x] All tests run as part of CI

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
- 2024-12-20: Implemented all tests, all 9 tests passing

## Completion Notes

**Completed:** 2024-12-20

### Summary

Created `zig/harness/test-pk-blob-parity.sh` with oracle parity tests for PK blob encoding in `crsql_changes`:

### Tests Implemented

1. **WF-021**: Single text PK (`'hello'`) - PK blob: `010B0568656C6C6F`
2. **WF-022**: Single blob PK (`X'DEADBEEF'`) - PK blob: `010C04DEADBEEF`
3. **WF-023**: Compound PK (int, int) `(123, 456)` - PK blob: `02097B1101C8`
4. **WF-024**: Compound PK (int, text) `(42, 'world')` - PK blob: `02092A0B05776F726C64`
5. **WF-025**: Compound PK (int, text, blob) `(99, 'mixed', X'CAFE')` - PK blob: `0309630B056D697865640C02CAFE`
6. **WF-026**: Unicode text PK (basic + emoji) - Both match
7. **WF-027**: Empty string PK (`''`) - PK blob: `0103`
8. **WF-028**: Empty blob PK (`X''`) - PK blob: `0104`

### Test Results

```
  PASS:    9
  FAIL:    0
  SKIP:    0

All PK blob format parity tests PASSED
```

### Integration

- Added test to `test-parity.sh` main test suite
- Tests run automatically as part of CI via the parity test runner

### Wire Format Notes

The PK blob format follows the pack_columns encoding:
- First byte: number of columns
- For each column:
  - Type marker (09=int, 0B=text, 0C=blob, 03=empty text, 04=empty blob, 05=null)
  - Length (for variable-length types)
  - Data

Both Zig and Rust/C implementations produce identical PK blobs for all tested cases.
