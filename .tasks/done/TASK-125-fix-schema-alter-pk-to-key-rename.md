# TASK-125: Fix schema_alter.zig pk→key column rename for clock table

## Status
- [x] Completed

## Priority
high (blocks alter and merge tests)

## Assigned To
(completed)

## Parent Docs / Cross-links
- Caused by: `.tasks/done/TASK-123-fix-clock-table-schema-parity.md`
- Test failures: `zig/harness/test-alter.sh` (Test 2b), `zig/harness/test-noops.sh` (Test 3)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
TASK-123 renamed the clock table column from `pk` to `key` in `as_crr.zig`, but missed updating `schema_alter.zig`. This causes SQL errors when:

1. **test-alter.sh Test 2b**: "table bar2__crsql_clock has no column named pk"
2. **test-noops.sh Test 3**: "setWinnerClockCached failed" (SQL logic error)

The issue is that `schema_alter.zig` still references `"pk"` in clock table SQL at:
- Line 264: CREATE TABLE clock definition
- Line 270: PRIMARY KEY clause
- Lines 468-473: INSERT INTO clock
- Lines 578, 590: INSERT OR REPLACE INTO clock

## Files to Modify
- `zig/src/schema_alter.zig` — update all clock table `"pk"` references to `"key"`

## Acceptance Criteria
- [x] All `"pk"` references in clock table SQL changed to `"key"` 
- [x] Clock table creation includes `STRICT` and index (matching TASK-123)
- [x] `bash zig/harness/test-alter.sh` — 6/6 pass
- [x] `bash zig/harness/test-noops.sh` — 4/4 pass
- [x] No regressions in `make -C zig test-parity`

## Progress Log

### 2024-12-20: Completed

#### Changes Made to `zig/src/schema_alter.zig`:

1. **Line 264-272**: Changed clock table CREATE TABLE definition
   - `"pk"` → `"key"` in column definition
   - `PRIMARY KEY ("pk", "col_name")` → `PRIMARY KEY ("key", "col_name")`
   - Added `STRICT` mode to match as_crr.zig

2. **Added db_version index** (new lines after clock table creation):
   - Added `CREATE INDEX IF NOT EXISTS "{s}__crsql_clock_dbv_idx" ON "{s}__crsql_clock" ("db_version")`
   - Matches as_crr.zig schema

3. **Lines 468-473 (backfillColumn)**: Updated INSERT INTO clock
   - `("pk", ...)` → `("key", ...)`
   - `WHERE c."pk" = p."pk"` → `WHERE c."key" = p."pk"` 
   - Note: `p."pk"` stays as is because it references the pks table's pk column

4. **Lines 578, 590 (createInsertTrigger)**: Updated INSERT OR REPLACE INTO clock
   - `("pk", ...)` → `("key", ...)`

#### Test Results:
- `bash zig/harness/test-alter.sh`: 6/6 pass
- `bash zig/harness/test-noops.sh`: 4/4 pass
- No regressions in parity tests (filter, rowid-slab, fract tests all pass)

## Completion Notes
- Date: 2024-12-20
- All acceptance criteria met
- The clock table in schema_alter.zig now matches the schema defined in as_crr.zig:
  - Uses `"key"` column (not `"pk"`)
  - Includes `WITHOUT ROWID, STRICT`
  - Includes `_dbv_idx` index on `db_version`
