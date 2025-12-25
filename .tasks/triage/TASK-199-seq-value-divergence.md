# TASK-199 — seq Value Divergence (Zig=1, Rust=0)

## Goal
Investigate and potentially fix the `seq` column value divergence between Zig and Rust/C implementations.

## Status
- State: triage
- Priority: MEDIUM (affects sync ordering in edge cases)
- Discovered: 2025-12-23 (TASK-192 prior DB parity testing)

## Problem

When performing single operations, the `seq` column in `crsql_changes` differs:
- **Rust/C**: `seq=0`
- **Zig**: `seq=1`

This was previously documented in TASK-130 (resurrection semantics) but may have broader implications.

## Impact

The `seq` column determines ordering when multiple changes have the same `db_version`. If Zig starts at 1 and Rust at 0, sync ordering could differ in edge cases involving:
- Multiple changes in same transaction
- Resurrection (DELETE + INSERT same PK)
- Bulk operations

## Evidence

From TASK-192 cross-implementation testing:
```
Rust/C crsql_changes: tbl|pk|col|val|col_version|db_version|site_id|cl|seq
                      foo|1 |x  |42 |1          |1         |...    |1 |0

Zig crsql_changes:    foo|1 |x  |42 |1          |1         |...    |1 |1
```

## Questions to Answer

1. Is `seq=0` or `seq=1` semantically correct for single operations?
2. Does the sync protocol rely on specific `seq` values?
3. What happens when Zig and Rust exchange changes with different `seq` bases?

## Files to Investigate

- `zig/src/triggers.zig` — seq assignment logic
- `zig/src/changes_vtab.zig` — seq in crsql_changes output
- `core/src/changes-vtab.c` — Rust/C implementation for comparison

## Acceptance Criteria

1. [ ] Document the intended semantics of `seq`
2. [ ] Determine if divergence affects sync correctness
3. [ ] Either fix Zig to match Rust OR document as acceptable divergence

## Parent Docs / Cross-links

- Discovery: `.tasks/done/TASK-192-prior-db-oracle-parity.md`
- Related: `.tasks/done/TASK-130-fix-trigger-parity-test-column-bug.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from TASK-192 findings.

## Completion Notes
(Empty until done.)
