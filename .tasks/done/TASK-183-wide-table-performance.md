# TASK-183 — Test wide tables (50+ columns) performance

## Goal
Verify Zig handles wide tables without performance degradation.

## Status
- State: done
- Priority: low (performance, not correctness)

## Context
Current tests use 2-4 column tables. Real enterprise schemas often have 50-100+ columns.

Questions:
1. Clock table performance with many column entries per row
2. crsql_changes SELECT performance on wide tables
3. Schema migration time on wide tables

## Files to Modify
- `zig/harness/test-wide-table.sh` (new)

## Acceptance Criteria
1. [x] Create table with 100 columns
2. [x] Insert 1000 rows
3. [x] Measure: time to insert
4. [x] Measure: time to query crsql_changes
5. [x] Measure: clock table size
6. [x] Compare Zig vs Rust/C oracle
7. [x] Document any performance gaps > 2x

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-23: Implemented `zig/harness/test-wide-table.sh`
  - All tests pass (CI mode: 12/12, Full mode: 11/11)
  - **CRITICAL FINDING**: Zig has 64-column limit (fails at 64+ columns)
  - **PERFORMANCE GAP**: crsql_changes SELECT is 7.45x slower than Rust/C

## Completion Notes

### Test Created
- File: `zig/harness/test-wide-table.sh`
- Tests 8 scenarios: schema create, bulk insert, changes query, clock table, single-column update, performance comparison, clock correctness, sync

### Performance Results (Full Mode: 63 cols x 1000 rows)

| Operation          | Zig       | Rust/C    | Ratio   |
|--------------------|-----------|-----------|---------|
| Schema create      | 0.113s    | 0.104s    | 1.08x   |
| Bulk insert        | 0.630s    | 0.412s    | 1.52x   |
| Changes COUNT      | 0.109s    | 0.168s    | 0.64x   |
| **Changes SELECT** | **1.508s**| **0.202s**| **7.45x** |
| Single col UPDATE  | 0.144s    | 0.135s    | 1.07x   |
| Sync export (Zig)  | 1.756s    | N/A       | -       |
| Sync import (Zig)  | 14.025s   | N/A       | -       |

### Findings

1. **Column Limit (CRITICAL)**
   - Zig extension fails at 64+ columns with "failed to create pks table"
   - Rust/C handles 100+ columns without issue
   - **Follow-up needed**: Investigate Zig pks table creation limit
   - Likely cause: hardcoded buffer or column array size in Zig

2. **Performance Gap (WARNING)**
   - `crsql_changes SELECT *` is **7.45x slower** in Zig vs Rust/C
   - Other operations are within acceptable range (< 2x)
   - **Follow-up needed**: Profile Zig crsql_changes vtab row iteration

3. **Clock Table Correctness**
   - Clock entries match exactly (63000 Zig = 63000 Rust/C)
   - All columns properly tracked
   - col_version correctly updated on UPDATE

4. **Sync Integrity**
   - Wide table sync A->B works correctly
   - All 1000 rows synced successfully
   - Spot checks pass

### Recommended Follow-ups
1. **TASK-XXX**: Investigate and fix 64-column limit in Zig extension
2. **TASK-XXX**: Optimize crsql_changes SELECT performance (7.45x gap)
