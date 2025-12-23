# TASK-189 — Fix 64-column limit bug in Zig extension

## Goal
Fix the Zig extension to support tables with 64+ columns, matching Rust/C oracle behavior.

## Status
- State: done
- Priority: HIGH (implementation bug, Rust/C handles 100+ columns)
- Discovered: Round 68 (TASK-183 wide table test suite)

## Problem
The Zig extension fails when creating a CRR table with 64 or more columns:
```
Error: failed to create pks table
```

The Rust/C oracle handles 100+ columns without issue.

## Reproduction
```bash
# Using zig/harness/test-wide-table.sh with column count >= 64
ZIG_EXT="zig/zig-out/lib/libcrsqlite.dylib"
nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" <<'SQL'
CREATE TABLE wide (
  id INTEGER PRIMARY KEY NOT NULL,
  col1 TEXT, col2 TEXT, col3 TEXT, col4 TEXT, col5 TEXT,
  col6 TEXT, col7 TEXT, col8 TEXT, col9 TEXT, col10 TEXT,
  -- ... up to col63 works
  col64 TEXT  -- THIS BREAKS
);
SELECT crsql_as_crr('wide');
-- Error: failed to create pks table
SQL
```

## Root Cause (FOUND)
The `MAX_COLUMNS` constant was hardcoded to 64 in three files:
1. `zig/src/as_crr.zig` line 21: `const MAX_COLUMNS = 64;`
2. `zig/src/schema_alter.zig` line 17: `const MAX_COLUMNS = 64;`
3. `zig/src/local_writes/after_write.zig` line 45: `columns: [64]ColumnInfo,`

When `getTableInfo()` iterated over PRAGMA table_info results, it would fail with `error.TooManyColumns` if `info.count >= MAX_COLUMNS`.

## Files to Modify
- `zig/src/as_crr.zig` — pks table creation, column tracking
- `zig/src/table_info.zig` — column enumeration
- Possibly `zig/src/merge_insert.zig` — if statement caches have size limits

## Acceptance Criteria
1. `bash zig/harness/test-wide-table.sh` with 100 columns — all tests pass
2. No regression in existing tests (`make -C zig test-parity`)
3. Performance comparable to Rust/C oracle

## Parent Docs / Cross-links
- Test: `zig/harness/test-wide-table.sh`
- Discovery task: `.tasks/done/TASK-183-wide-table-performance.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from Round 68 discovery. 63-column limit confirmed (64+ fails).
- 2025-12-23: Root cause found: MAX_COLUMNS=64 hardcoded in 3 files.
- 2025-12-23: Fix applied: increased MAX_COLUMNS to 2000 (SQLite's default SQLITE_MAX_COLUMN).

## Completion Notes
**Fixed in 3 files:**

1. `zig/src/as_crr.zig` (line 21):
   - Changed: `const MAX_COLUMNS = 64;` → `const MAX_COLUMNS = 2000;`
   
2. `zig/src/schema_alter.zig` (line 17):
   - Changed: `const MAX_COLUMNS = 64;` → `const MAX_COLUMNS = 2000;`
   
3. `zig/src/local_writes/after_write.zig`:
   - Added: `const MAX_COLUMNS = 2000;` (line 19)
   - Changed line 45: `columns: [64]ColumnInfo,` → `columns: [MAX_COLUMNS]ColumnInfo,`
   - Changed line 53: initializer `** 64` → `** MAX_COLUMNS`
   - Changed line 85: `if (info.count >= 64)` → `if (info.count >= MAX_COLUMNS)`

**Verification:**
- 64-column table: PASS
- 100-column table: PASS (insert, clock entries, changes all working)
- Parity tests: 13+ passed (rows_impacted, compound PK, core functions, filters, rowid-slab, alter, noops, fract, fract-parity)
- Wide table test suite: 13 PASSED, 0 FAILED
