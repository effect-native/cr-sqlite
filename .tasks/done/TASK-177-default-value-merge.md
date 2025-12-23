# TASK-177 — DEFAULT value merge semantics tests

## Goal
Verify Zig handles DEFAULT column values correctly during merge.

## Status
- State: done
- Priority: high (schema evolution)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
From Python `test_sync.py`. When columns have DEFAULT values, merge behavior must be consistent.

## Files to Modify
- `zig/harness/test-default-merge.sh` (new, ~200 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Explicit value beats DEFAULT (when explicit has higher col_version)
2. DEFAULT value handling after ALTER ADD COLUMN
3. Zig and Rust/C produce identical behavior

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-default-merge.sh - DEFAULT value merge semantics

test_explicit_beats_default() {
    # Site A: table with col DEFAULT 'default_val'
    # Site A: INSERT without specifying col (uses default)
    # Site B: INSERT same PK with col='explicit'
    # Sync A to B (or B to A)
    # Verify: explicit wins (higher col_version)
}

test_default_after_alter() {
    # Site A: ALTER ADD COLUMN foo DEFAULT 'new_default'
    # Site A: existing rows get default value
    # Site B: UPDATE existing row's foo column
    # Sync
    # Verify: explicit update wins
}
```

## Parent Docs / Cross-links
- Python tests: `py/correctness/tests/test_sync.py`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-23: Implemented test script, wired into test-parity.sh, all 6 tests PASS.

## Completion Notes
- Created `zig/harness/test-default-merge.sh` (~350 lines) with 6 test cases
- Added test entry to `zig/harness/test-parity.sh` (header + runner section)
- All tests PASS for both Zig and Rust/C implementations (full parity)

### Test Cases Implemented
1. **test_explicit_beats_default** - Explicit value (2) beats DEFAULT (0) ✓
2. **test_larger_default_loses** - Larger DEFAULT (4) wins on tie-break ✓
3. **test_default_after_alter** - Explicit c=3 wins over DEFAULT after ALTER ADD COLUMN ✓
4. **test_no_phantom_clock** - No clock entries created for DEFAULT column after ALTER ✓
5. **test_update_creates_clock** - Explicit UPDATE creates clock entry ✓
6. **test_sync_after_update** - Sync propagates explicit UPDATE over DEFAULT ✓

### Key Findings
- Both implementations correctly handle DEFAULT values during merge
- DEFAULT values do NOT create phantom clock entries after ALTER ADD COLUMN
- Explicit values (with clock entries) always beat DEFAULT values (without clock entries)
- Value tie-breaks (same col_version) favor the greater value

### Commands to Reproduce
```bash
cd zig/harness && bash test-default-merge.sh
```
