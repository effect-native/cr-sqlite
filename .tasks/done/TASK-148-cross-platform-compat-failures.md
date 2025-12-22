# TASK-148 — Fix cross-platform compat test failures (resurrection + text newlines)

## Goal
Fix the 2 compatibility failures discovered by `zig/harness/test-cross-platform-compat.sh` after it was converted from SKIP to FAIL mode.

## Status
- State: done
- Priority: high

## Problem Statement
`bash zig/harness/test-cross-platform-compat.sh` now runs (doesn't SKIP) and found 2 real failures:

1. **Test G: Resurrection** — Row resurrection failed (row wasn't visible after sync)
2. **Test M: Text Edge Cases** — text with newlines not syncing properly

## Root Causes

### Test G: Resurrection Bug
The Zig merge functions (`rowExistsInBaseTable`, `deleteFromBaseTable`, `insertRowForResurrection`, `updateBaseTableColumn`) were using `__crsql_key` as if it equaled the base table's rowid. This is incorrect for tables with `INTEGER PRIMARY KEY` where the rowid equals the declared PK column value.

For example:
- `CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data TEXT)`
- `INSERT INTO t VALUES (99, 'hello')` → base rowid = 99
- `t__crsql_pks` stores: `__crsql_key=1, id=99`
- `t__crsql_clock` uses `key=1` (the __crsql_key)

When resurrecting, the code was trying to insert with `id=1` instead of `id=99`.

**Fix**: Added `getPkValueFromKey()` function that looks up the actual PK value from the pks table, and updated all base table operations to use this lookup.

### Test M: Text with Newlines (Harness Bug)
The Zig implementation correctly stores and exports text with newlines. The issue was in the test harness's bash parsing:
- `quote(val)` produces `'line1\nline2'` (with literal newline)
- `read -r line` in bash only reads one line at a time
- The parsing broke mid-value, leaving the change half-applied

**Fix**: Updated the test harness to use `replace(quote(val), char(10), '\n')` to escape newlines in export, and `replace($val, '\n', char(10))` to unescape on import.

## Files Modified
- `zig/src/merge_insert.zig` — Added `getPkValueFromKey()` and fixed base table operations
- `zig/harness/test-cross-platform-compat.sh` — Fixed newline handling in Test M

## Acceptance Criteria
1. ✅ `bash zig/harness/test-cross-platform-compat.sh` passes all tests (0 failures)
2. ✅ Text with newlines exports correctly from Zig
3. ✅ Resurrection sync works correctly

## Parent Docs / Cross-links
- `zig/harness/test-cross-platform-compat.sh`
- `.tasks/done/TASK-144-cross-platform-compat-no-skip.md` (discovered these)

## Progress Log
- 2025-12-21: Created from failures discovered by TASK-144 harness fix.
- 2025-12-21: Investigated resurrection failure - traced to __crsql_key vs rowid mismatch.
- 2025-12-21: Fixed merge_insert.zig to look up actual PK values from pks table.
- 2025-12-21: Fixed test harness newline handling.
- 2025-12-21: All tests passing. Verified with `make test-parity`.

## Completion Notes
Two distinct issues were fixed:

1. **Zig bug**: Base table operations (exists/delete/insert/update) were using `__crsql_key` directly as rowid, but for `INTEGER PRIMARY KEY` tables, the rowid equals the declared PK column value. Added `getPkValueFromKey()` to properly look up PK values from the pks table.

2. **Harness bug**: Bash `read` command splits on newlines, breaking parsing of text values containing newlines. Fixed by escaping newlines as `\n` in the export format and unescaping on import.
