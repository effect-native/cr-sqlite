# TASK-152 — Update tombstone handling to use clock table sentinels (no base_rowid = NULL)

## Goal
Remove `base_rowid = NULL` tombstone logic from merge_insert.zig and update to use clock table sentinel markers for deletion tracking, matching Rust/C implementation.

## Status
- State: triage
- Priority: medium (correctness for DELETE sync)

## Context
OLD TOMBSTONE MECHANISM (Zig with base_rowid):
```sql
-- Mark row as deleted (tombstone)
UPDATE table__crsql_pks SET base_rowid = NULL WHERE pk = ?;

-- Check if tombstoned
SELECT base_rowid FROM table__crsql_pks WHERE pk = ?;
-- base_rowid IS NULL → tombstoned
```

NEW TOMBSTONE MECHANISM (Rust/C via clock sentinels):
- Pks table row is NEVER removed or marked NULL
- Instead, clock table sentinel with `col_name = '-1'` tracks deletion:
  ```sql
  -- Sentinel with even col_version = tombstone (deleted)
  INSERT INTO clock (key, col_name, col_version, ...) VALUES (pk, '-1', 2, ...);

  -- Sentinel with odd col_version = creation marker (exists)
  INSERT INTO clock (key, col_name, col_version, ...) VALUES (pk, '-1', 1, ...);
  ```

Verified in testing:
```
Before DELETE: clock has (key=1, col_name='c', col_version=1)
After DELETE:  clock has (key=1, col_name='-1', col_version=2)
PKS table still has (key=1, a=1, b=2) unchanged
```

Current code locations with old tombstone logic:
- `deleteFromBaseTable()` - sets `base_rowid = NULL` after delete
- `getBaseRowidFromPk()` - checks `base_rowid IS NULL`
- `rowExistsInBaseTable()` - relies on getBaseRowidFromPk tombstone check

## Files to Modify
- `zig/src/merge_insert.zig`:
  - `deleteFromBaseTable()` (line ~415) - remove pks UPDATE
  - `deleteFromBaseTableCached()` (line ~985) - same
  - `getBaseRowidFromPk()` (line ~385) - remove NULL check (or delete function entirely)
  - `rowExistsInBaseTable()` (line ~457) - check clock sentinel instead

## Acceptance Criteria
1. `deleteFromBaseTable()` refactored:
   - Delete from base table using PK WHERE (from TASK-150)
   - Insert clock sentinel: `INSERT INTO clock (key, col_name, col_version, ...) VALUES (?, '-1', ?, ...)`
   - Do NOT update pks table (it remains unchanged)

2. `rowExistsInBaseTable()` checks two sources:
   - Base table query: `SELECT 1 FROM table WHERE pk1=? AND pk2=?`
   - If no row, check clock sentinel:
     - `SELECT col_version FROM clock WHERE key=? AND col_name='-1'`
     - Even col_version → tombstoned (return false)
     - Odd col_version or no sentinel → exists or never created

3. Remove all `base_rowid = NULL` and `base_rowid IS NULL` references

4. Test tombstone sync:
   ```sql
   CREATE TABLE foo(a INT NOT NULL PRIMARY KEY, b TEXT);
   SELECT crsql_as_crr('foo');
   -- Insert via sync
   INSERT INTO crsql_changes VALUES ('foo', X'0901', 'b', 'data', 1, 1, X'01...', 1, 0);
   SELECT * FROM foo; -- row exists
   -- Delete via sync (negative cl)
   INSERT INTO crsql_changes VALUES ('foo', X'0901', '-1', NULL, 2, 2, X'01...', -2, 0);
   SELECT * FROM foo; -- empty
   SELECT col_version FROM foo__crsql_clock WHERE col_name='-1'; -- 2 (even = tombstone)
   SELECT * FROM foo__crsql_pks; -- still has __crsql_key=1, a=1
   ```

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration)
- Related: Explore agent findings on tombstone handling (session above)
- Related: `zig/src/as_crr.zig:472-483` (tombstone design comments)
- Depends on: TASK-150 (base table ops must work first)
- Upstream: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-21: Created from TASK-147 work. Rust/C testing revealed clock sentinel mechanism (col_name='-1', even/odd col_version).

## Completion Notes
(Empty until done.)
