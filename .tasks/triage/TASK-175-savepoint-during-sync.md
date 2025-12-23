# TASK-175 — Test savepoints during sync operations

## Goal
Verify Zig handles savepoints correctly during sync.

## Status
- State: triage
- Priority: medium (transaction correctness)

## Context
Apps may use savepoints for partial rollback:
```sql
BEGIN;
INSERT INTO crsql_changes ...;
SAVEPOINT sp1;
INSERT INTO crsql_changes ...;
ROLLBACK TO sp1;
COMMIT;
```

Questions:
1. Does rollback to savepoint undo clock entries?
2. Is db_version correct after partial rollback?
3. Is rows_impacted correct?

## Files to Modify
- `zig/harness/test-savepoint-sync.sh` (new)

## Acceptance Criteria
1. BEGIN transaction
2. Apply some changes via crsql_changes
3. SAVEPOINT sp1
4. Apply more changes
5. ROLLBACK TO sp1
6. COMMIT
7. Verify: only pre-savepoint changes applied
8. Verify: clock entries correct
9. Verify: db_version reflects only committed changes
10. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Related: TASK-174 (partial sync)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
