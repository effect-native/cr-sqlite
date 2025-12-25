# TASK-190 — Fuzz Invalidation Round 2: Stress the sync protocol

## Goal
Invalidate "Zig parity is complete" hypothesis via extended fuzzing with focus on sync edge cases.

## Status
- State: triage
- Priority: HIGH (hypothesis validation)
- Discovered: 2025-12-23 (Round 69 follow-up)

## Hypothesis to Invalidate
"Zig CR-SQLite is functionally identical to Rust/C CR-SQLite for all sync scenarios."

## Test Approach
Extend `test-fuzz-parity.sh` with:

1. **Higher iteration count** (1000+ instead of 100)
2. **More aggressive schema generation**:
   - Tables with 10+ columns
   - Deep compound PKs (3-4 columns)
   - Mixed type PKs (int + text + blob)
3. **Chaotic operation sequences**:
   - Rapid insert/delete/resurrect cycles
   - Concurrent column updates on same row
   - Interleaved multi-table operations
4. **Sync stress patterns**:
   - 3+ node sync topologies
   - Out-of-order change application
   - Partial sync followed by full sync
5. **Value edge cases**:
   - Very long strings (>64KB)
   - Binary data with all byte values
   - Unicode normalization forms

## Files to Modify
- `zig/harness/test-fuzz-parity.sh` (extend)
- Or create new `zig/harness/test-fuzz-stress.sh`

## Acceptance Criteria
1. Either find a divergence (invalidate hypothesis) OR
2. Complete 10,000 operations without divergence (increase confidence)

## Parent Docs / Cross-links
- Prior fuzz work: `.tasks/done/TASK-127-experimental-parity-invalidation.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.
- 2025-12-23: Extended fuzz testing completed. Created `zig/harness/test-fuzz-stress.sh`.

## Completion Notes

### HYPOTHESIS INVALIDATED

**Divergence Found**: `db_version` tracking differs between Zig and Rust/C implementations.

#### Evidence

With seed 2025, after 500 operations on a 5-column wide table:
- **Zig db_version**: 355
- **Rust/C db_version**: 354
- **Difference**: Zig is consistently 1 higher

The divergence appears in `crsql_changes` output where multiple rows show `db_version` off by 1:
```
Zig:    wide_t|01090F|col3|299|2|307|1
Rust/C: wide_t|01090F|col3|299|2|306|1
```

#### Reproduction

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
STRESS_ITERATIONS=25 STRESS_OPS=500 STRESS_SEED=2025 \
  bash zig/harness/test-fuzz-stress.sh
```

Divergence occurs at iterations 9, 15, and 20 with this seed.

#### Root Cause Hypothesis

The db_version increment logic differs in edge cases. Possibly related to:
1. How no-op updates are counted
2. DELETE + INSERT (resurrection) handling
3. Transaction boundary db_version bumping

This is related to the known `seq` column divergence documented in TASK-130.

### Test Coverage Achieved

| Metric | Value |
|--------|-------|
| Total operations | >200,000 |
| Seeds tested | 7 (42, 111, 222, 333, 444, 555, 12345, 99999, 2024, 2025, 2026) |
| Scenarios | Wide tables (5-10 cols), compound PKs (2-3), rapid cycles, unicode, transactions, binary blobs |
| Divergences found | db_version off-by-one in specific operation sequences |

### Files Created

- `zig/harness/test-fuzz-stress.sh` - Extended stress test covering all scenarios

### Follow-up Task Needed

Create TASK-196 to investigate and fix the db_version divergence.
