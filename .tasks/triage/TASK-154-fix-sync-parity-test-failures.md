# TASK-154 — Fix sync parity test failures after schema refactoring

## Goal
Run full parity test suite (`make -C zig test-parity`) and fix all failures caused by the pks schema migration. Achieve zero failures for sync operations (INSERT/UPDATE/DELETE via crsql_changes vtab).

## Status
- State: triage
- Priority: high (validation of schema migration work)

## Context
As of 2025-12-21 after TASK-147 partial completion:

PASSING:
- ✅ Cross-open tests (24/24) - direct table modifications work
- ✅ Local writes via triggers - compound PK fixed (commit 255e316e)
- ✅ Core functions (site_id, db_version, finalize)
- ✅ Compound PK encoding test
- ✅ Filter tests, rowid slab tests, fract tests

FAILING (sync operations):
- ❌ rows_impacted suite (9 tests) - "insertIntoBaseTable issue"
- ❌ Some alter tests (4 failed)
- ❌ Some noop tests (3 failed)

Root cause: Sync operations (applying remote changes via `INSERT INTO crsql_changes`) require:
- TASK-149: insertIntoPksTableAndGetPk refactored
- TASK-150: base table operations refactored
- TASK-152: tombstone handling updated

Current test output snippet:
```
Test: SingleInsertSingleTx
  FAIL: SQL error occurred (insertIntoBaseTable issue)
Test: ManyInsertsInATx
  FAIL: SQL error occurred (insertIntoBaseTable issue)
```

## Files to Modify
(To be determined by test failures; scope may expand)
- Primary: Issues in `zig/src/merge_insert.zig` (fixed by TASK-149/150/152)
- Secondary: Potential issues in `zig/src/changes_vtab.zig` if INSERT path needs adjustment
- Tertiary: Test harness scripts if they have stale assumptions

## Acceptance Criteria
1. All sync operation tests pass:
   - rows_impacted suite: 9/9 ✅
   - Alter tests: full pass (or failures documented as separate tasks)
   - Noop tests: full pass

2. Realistic sync scenario works:
   ```sql
   -- Site A: Create and insert
   CREATE TABLE todos(id INT PRIMARY KEY, task TEXT);
   SELECT crsql_as_crr('todos');
   INSERT INTO todos VALUES(1, 'Buy milk');

   -- Site B: Apply remote change
   CREATE TABLE todos(id INT PRIMARY KEY, task TEXT);
   SELECT crsql_as_crr('todos');
   INSERT INTO crsql_changes VALUES (
     'todos', X'0901', 'task', 'Buy milk', 1, 1, X'...', 1, 0
   );
   SELECT * FROM todos; -- (1, 'Buy milk')

   -- Site B: Update
   INSERT INTO crsql_changes VALUES (
     'todos', X'0901', 'task', 'Buy eggs', 2, 2, X'...', 2, 0
   );
   SELECT task FROM todos WHERE id=1; -- 'Buy eggs'

   -- Site B: Delete
   INSERT INTO crsql_changes VALUES (
     'todos', X'0901', '-1', NULL, 3, 3, X'...', -3, 0
   );
   SELECT * FROM todos; -- empty
   ```

3. Test suite exit code:
   ```bash
   make -C zig test-parity
   echo $? # Must be 0
   ```

4. No "SQL logic error" or "insertIntoBaseTable issue" in logs

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration)
- Blocks: Ready-to-release milestone
- Depends on: TASK-149 (insertIntoPksTableAndGetPk)
- Depends on: TASK-150 (base table ops)
- Depends on: TASK-152 (tombstone handling)
- Related: `.tasks/done/TASK-119` (Round 49 realistic sync fix - similar pattern)
- Upstream: `research/zig-cr/92-gap-backlog.md`
- CI requirement: `zig/harness/test-parity.sh` must exit 0

## Progress Log
- 2025-12-21: Created from TASK-147 work. Test baseline: cross-open passing, sync failing. Schema refactoring in progress.

## Completion Notes
(Empty until done.)
