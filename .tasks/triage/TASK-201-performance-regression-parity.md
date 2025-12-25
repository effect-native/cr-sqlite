# TASK-201 — Performance Regression Parity Tests

## Goal
Identify performance divergences that might indicate algorithmic differences.

## Status
- State: triage
- Priority: LOW (functional parity > perf parity, but perf gaps may indicate bugs)
- Discovered: 2025-12-23 (hypothesis invalidation request)

## Hypothesis to Invalidate
"Zig performs within 2x of Rust/C for all operations."

Large performance gaps may indicate:
- Missing optimizations (acceptable)
- Algorithmic differences (may cause functional divergence)
- N+1 query patterns (bug)

## Test Scenarios

### Known Issue (from TASK-183)
- crsql_changes SELECT on wide tables: ~2-7x slower in Zig
- COUNT is fast, SELECT * is slow
- May indicate inefficient column iteration

### Operations to Benchmark
1. **Bulk INSERT** (1000, 10000, 100000 rows)
2. **Bulk UPDATE** (same row counts)
3. **crsql_changes SELECT** (various filters)
4. **Sync apply** (1000, 10000 changes)
5. **ALTER ADD COLUMN** on large table
6. **VACUUM** on CRR database

### Metrics to Capture
- Wall clock time
- Number of SQLite operations (via sqlite3_trace)
- Memory peak (if measurable)

## Files to Create
- `zig/harness/test-perf-comparison.sh` (new)

## Acceptance Criteria
1. Document perf ratios for each operation
2. Flag any operation >10x slower as potential bug
3. Either find performance divergence indicating bug OR confirm acceptable perf

## Parent Docs / Cross-links
- Wide table perf: `.tasks/done/TASK-183-wide-table-performance.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.

## Completion Notes
(Empty until done.)
