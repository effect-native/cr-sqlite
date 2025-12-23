# TASK-175 — Test savepoints during sync operations

## Goal
Verify Zig handles savepoints correctly during sync.

## Status
- State: done
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
- 2025-12-23: Created test suite `zig/harness/test-savepoint-sync.sh` with 8 test cases.

## Completion Notes
### Test Suite Created: `zig/harness/test-savepoint-sync.sh`

**Test Cases Implemented:**
1. Basic Savepoint with Rollback - PASS (Zig + Rust)
2. Nested Savepoints (sp1 -> sp2) - PASS (Zig + Rust)
3. RELEASE SAVEPOINT (keeps changes) - PASS (Zig + Rust)
4. Multiple Savepoints with Partial Rollback - PASS (Zig + Rust)
5. rows_impacted After Partial Rollback - PASS (Zig + Rust)
6. Clock Entries After Savepoint Rollback - PASS (Zig + Rust)
7. db_version After Savepoint Rollback - **DIVERGENCE** (Zig FAIL, Rust PASS)
8. Rollback to Savepoint Then Add More Data - PASS (Zig + Rust)

**Summary: 15 passed, 1 failed, 0 skipped, 1 divergence**

### Divergence Found (Test 7)
The Zig implementation has a bug in db_version handling during savepoint operations:
- **Rust/C**: db_version correctly advances from 0 -> 1 after COMMIT
- **Zig**: db_version stays at 0 after COMMIT

This is a real bug that should be filed as a follow-up task. The db_version should advance
when changes are committed, even when using savepoints.

### Answers to Original Questions:
1. **Does rollback to savepoint undo clock entries?** YES - verified in Test 6
2. **Is db_version correct after partial rollback?** NO (Zig bug) - db_version doesn't advance
3. **Is rows_impacted correct?** YES - verified in Test 5 (both impls return 3 after rollback, 0 after commit)

### Follow-up Required
File new task for Zig db_version bug when using savepoints with crsql_changes inserts.
