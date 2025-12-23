# TASK-183 — Test wide tables (50+ columns) performance

## Goal
Verify Zig handles wide tables without performance degradation.

## Status
- State: triage
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
1. Create table with 100 columns
2. Insert 1000 rows
3. Measure: time to insert
4. Measure: time to query crsql_changes
5. Measure: clock table size
6. Compare Zig vs Rust/C oracle
7. Document any performance gaps > 2x

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
