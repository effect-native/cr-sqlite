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

1. [x] Test WF-007: Empty string encoding matches
2. [x] Test WF-009: Zero encoding matches
3. [x] Test WF-010: Negative one encoding matches
4. [x] Test WF-011: MAX_INT64 (9223372036854775807) encoding matches
5. [x] Test WF-012: MIN_INT64 (-9223372036854775808) encoding matches
6. [x] Test WF-013: MAX_FLOAT encoding matches
7. [x] Test WF-014: Unicode/emoji encoding matches
8. [x] All tests run as part of CI

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
- 2024-12-20: Implemented test-wire-format-edge-cases.sh

## Completion Notes

**Completed: 2024-12-20**

Created `zig/harness/test-wire-format-edge-cases.sh` with 7 oracle parity tests:

| Test ID | Input | Zig/Rust Output (hex) | Status |
|---------|-------|----------------------|--------|
| WF-007 | Empty string `''` | `0103` | PASS |
| WF-009 | Zero `0` | `0101` | PASS |
| WF-010 | Negative one `-1` | `0141FFFFFFFFFFFFFFFF` | PASS |
| WF-011 | MAX_INT64 | `01417FFFFFFFFFFFFFFF` | PASS |
| WF-012 | MIN_INT64 | `01418000000000000000` | PASS |
| WF-013 | MAX_FLOAT | `01027FEFFFFFFFFFFFFF` | PASS |
| WF-014 | Emoji `🎉` | `010B04F09F8E89` | PASS |

All 7 tests pass - Zig implementation has full parity with Rust/C oracle for these edge cases.

**Integration:**
- Added to `test-parity.sh` test runner
- Tests run automatically as part of CI via `./zig/harness/test-parity.sh`

**Files Modified:**
- NEW: `zig/harness/test-wire-format-edge-cases.sh`
- MODIFIED: `zig/harness/test-parity.sh` (added test integration)
