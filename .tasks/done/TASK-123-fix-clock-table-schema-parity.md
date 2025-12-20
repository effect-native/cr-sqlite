# TASK-123: Fix clock table schema parity with oracle

## Status
- [x] Completed

## Priority
medium

## Assigned To
(completed)

## Parent Docs / Cross-links
- Divergence documented in: `.tasks/done/TASK-074-cross-impl-compat-expanded.md`
- Test: `zig/harness/test-oracle-parity.sh` (Test 2)
- Zig clock table creation: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Zig `__crsql_clock` table schema differs from the Rust/C oracle in two ways:

1. **Column naming**: Zig uses `pk` column, Rust/C uses `key` column
2. **Index**: Rust/C has an index on the clock table, Zig has 0 indexes
3. **Strict**: Rust/C uses STRICT tables, Zig does not

These differences may cause cross-implementation database sharing issues.

## Files to Modify
- `zig/src/as_crr.zig` - clock table creation

## Acceptance Criteria
- [x] `__crsql_clock` table schema matches oracle exactly
- [x] Column names match (change `pk` to `key` - careful with pks table relation!)
- [x] Index structure matches oracle (add `_dbv_idx` on `db_version`)
- [x] Strict mode enabled
- [x] `zig/harness/test-oracle-parity.sh` Test 2 passes

## Progress Log
- 2025-12-20: Fixed clock table schema parity

## Completion Notes
### Changes Made
Renamed the `pk` column to `key` in the `__crsql_clock` table to match the Rust/C oracle.
Added `STRICT` mode to the table definition. Added `_dbv_idx` index on `db_version`.

Updated all SQL references to the clock table column in:
- `zig/src/as_crr.zig` - clock table creation, triggers, backfill
- `zig/src/merge_insert.zig` - merge statement caches and helper functions
- `zig/src/schema_alter.zig` - alter table triggers and cleanup
- `zig/src/changes_vtab.zig` - changes virtual table queries

Note: The `pk` column in the `__crsql_pks` table was NOT renamed (it's a different
table with a different purpose - it maps packed PK blobs to auto-increment keys).

### Test Output
```
Test 2: Clock Table Schema Parity
Test 2a: __crsql_clock table columns
  PASS: __crsql_clock schema matches
Test 2b: __crsql_clock index structure
  PASS: __crsql_clock index count matches (1)
```

### Zig Clock Table Schema (now matches oracle):
```sql
CREATE TABLE IF NOT EXISTS "test__crsql_clock" (
  "key" INTEGER NOT NULL,
  "col_name" TEXT NOT NULL,
  "col_version" INTEGER NOT NULL,
  "db_version" INTEGER NOT NULL,
  "site_id" INTEGER NOT NULL DEFAULT 0,
  "seq" INTEGER NOT NULL,
  PRIMARY KEY ("key", "col_name")
) WITHOUT ROWID, STRICT;
CREATE INDEX "test__crsql_clock_dbv_idx" ON "test__crsql_clock" ("db_version");
```
