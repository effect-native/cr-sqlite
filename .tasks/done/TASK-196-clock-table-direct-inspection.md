# TASK-196 — Deep Clock Table Inspection Tests

## Goal
Directly compare clock table internals between Zig and Rust/C to invalidate "Zig parity is complete".

## Status
- State: done
- Priority: MEDIUM (internal implementation detail, but affects sync)
- Discovered: 2025-12-23 (hypothesis invalidation request)
- Completed: 2025-12-25

## Hypothesis to Invalidate
"Zig creates identical clock table entries as Rust/C for all operations."

**RESULT: Hypothesis PARTIALLY INVALIDATED**
- A `seq` value divergence was discovered (see Divergence Found below)
- All other clock fields match exactly (key, col_name, col_version, db_version)

## Divergence Found

### `seq` Value Off-by-One

**Rust/C**: INSERT triggers start `seq` at 0
**Zig**: INSERT triggers start `seq` at 1

This affects:
- Single INSERT (seq=0,1 vs seq=1,2 for 2-column table)
- Bulk INSERT (pattern repeats)
- ALTER ADD COLUMN (backfill entries)
- Compound PK inserts

This does NOT affect:
- DELETE (sentinel seq matches)
- Resurrection (seq matches after delete+insert)
- Sync receive (seq values from remote are preserved)
- UPDATE operations (seq values are reset correctly)
- col_version, db_version, key encoding

### Impact Assessment
- **Low**: The `seq` value is used for ordering changes within the same `db_version`
- **Sync-safe**: Remote changes preserve their original seq values
- **Edge case**: Could affect merge ordering if two peers have same db_version but differ by seq

## Test Script Created

`zig/harness/test-clock-internals.sh` - 14 test cases covering:

1. Single INSERT clock entries
2. Bulk INSERT (10 rows)
3. UPDATE single column
4. UPDATE multiple columns
5. UPDATE with same value (no-op)
6. DELETE single row
7. Resurrection (DELETE then re-INSERT)
8. ALTER ADD COLUMN
9. Sync receive (INSERT INTO crsql_changes)
10. Compound Primary Key
11. Transaction batching
12. col_version increment behavior
13. Site ID ordinals after sync
14. crsql_changes vtab output parity

## Test Results

```
PASSED:         27
FAILED:         0
seq divergences: 7 (known issue: Zig starts seq at 1, Rust at 0)
```

All tests pass when `seq` differences are treated as known divergence.

## Files Created
- `zig/harness/test-clock-internals.sh` (new)

## Acceptance Criteria
1. ~~Byte-identical clock entries~~ **PARTIALLY MET** - seq differs, others match
2. Same db_version progression ✅
3. Same site_id ordinal assignments ✅
4. Either find divergence OR confirm internal parity ✅ **DIVERGENCE FOUND**

## Parent Docs / Cross-links
- Clock table schema: TASK-123 (fixed pk→key rename)
- Trigger parity: `test-trigger-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- **NEW**: Follow-up task needed to fix seq off-by-one in Zig INSERT triggers

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.
- 2025-12-25: Created test script `test-clock-internals.sh` with 14 test cases
- 2025-12-25: Discovered `seq` value divergence (Zig starts at 1, Rust at 0)
- 2025-12-25: All 27 tests pass (7 with known seq divergence)

## Completion Notes
- **Tests created**: 14 test cases (27 individual assertions)
- **Pass/fail**: 27 PASS, 0 FAIL
- **Divergence discovered**: `seq` starts at 1 in Zig vs 0 in Rust/C for INSERT
- **Recommendation**: Create follow-up task to fix seq value initialization in Zig INSERT triggers
- **Date**: 2025-12-25
