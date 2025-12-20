# TASK-125: Fix schema_alter.zig pk→key column rename for clock table

## Status
- [ ] Planned

## Priority
high (blocks alter and merge tests)

## Assigned To
(unassigned)

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
- [ ] All `"pk"` references in clock table SQL changed to `"key"` 
- [ ] Clock table creation includes `STRICT` and index (matching TASK-123)
- [ ] `bash zig/harness/test-alter.sh` — 6/6 pass
- [ ] `bash zig/harness/test-noops.sh` — 4/4 pass
- [ ] No regressions in `make -C zig test-parity`
