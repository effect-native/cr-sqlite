# TASK-132: Add wire format edge case parity tests

## Priority: P1 (CRITICAL)

## Summary

Add oracle parity tests for wire format edge cases in `crsql_pack_columns`:
- Empty string
- Zero and negative integers
- MIN/MAX INT64
- MAX FLOAT
- Unicode/emoji

## Files to Modify

- `zig/harness/test-oracle-parity.sh` (add new test section)
  OR
- `zig/harness/test-wire-format-edge-cases.sh` (new file)

## Acceptance Criteria

1. [ ] Test WF-007: Empty string encoding matches
2. [ ] Test WF-009: Zero encoding matches
3. [ ] Test WF-010: Negative one encoding matches
4. [ ] Test WF-011: MAX_INT64 (9223372036854775807) encoding matches
5. [ ] Test WF-012: MIN_INT64 (-9223372036854775808) encoding matches
6. [ ] Test WF-013: MAX_FLOAT encoding matches
7. [ ] Test WF-014: Unicode/emoji encoding matches
8. [ ] All tests run as part of CI

## Test Template

```bash
# WF-007: Empty string
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(''));")
ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(''));")
compare "$RUST_RESULT" "$ZIG_RESULT" "Empty string encoding"

# WF-011: MAX_INT64
RUST_RESULT=$(run_rust "SELECT hex(crsql_pack_columns(9223372036854775807));")
ZIG_RESULT=$(run_zig "SELECT hex(crsql_pack_columns(9223372036854775807));")
compare "$RUST_RESULT" "$ZIG_RESULT" "MAX_INT64 encoding"

# etc.
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (WF-007 through WF-015)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card

## Completion Notes

(To be filled upon completion)
