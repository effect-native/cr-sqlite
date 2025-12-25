# TASK-202 — Fix INSERT INTO crsql_changes Failure (CRITICAL)

## Goal
Fix the critical bug where `INSERT INTO crsql_changes` fails in the Zig implementation, completely breaking cross-device sync.

## Status
- State: triage
- Priority: **P0 CRITICAL** (sync is completely broken)
- Discovered: 2025-12-25 (TASK-194 real-world app simulation)

## Problem

When applying changes from another device via `INSERT INTO crsql_changes`, the Zig implementation fails:

```
debug(changes_vtab): changesUpdate INSERT: table=todos, cid=title...
debug(changes_vtab): changesUpdate: no local row, inserting new row
debug(changes_vtab): changesUpdate: insertOrUpdateColumn failed
Error: stepping, SQL logic error
```

**This is the core sync mechanism of cr-sqlite. Without it, the extension is non-functional.**

## Reproduction

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-app-todo.sh
```

The test creates a todo on "Device A", exports changes via `SELECT * FROM crsql_changes`, then tries to apply them to "Device B" via `INSERT INTO crsql_changes`. Rust/C succeeds, Zig fails.

Minimal reproduction:
```sql
-- Device A (Zig)
CREATE TABLE todos(id TEXT PRIMARY KEY, title TEXT);
SELECT crsql_as_crr('todos');
INSERT INTO todos VALUES ('1', 'Test');

-- Export changes
SELECT * FROM crsql_changes;
-- Returns: todos|1|title|Test|1|1|<site_id>|1|1

-- Device B (Zig) - THIS FAILS
CREATE TABLE todos(id TEXT PRIMARY KEY, title TEXT);
SELECT crsql_as_crr('todos');
INSERT INTO crsql_changes VALUES ('todos', '1', 'title', 'Test', 1, 1, X'...', 1, 1);
-- Error: SQL logic error
```

## Root Cause (Suspected)

The error occurs in `zig/src/changes_vtab.zig` in the `changesUpdate` function, specifically in the `insertOrUpdateColumn` code path when the local row doesn't exist.

Possible causes:
1. SQL statement preparation failure (wrong column names/types)
2. Missing table/column in PKS table lookup
3. Incorrect binding of site_id blob
4. Schema mismatch between clock table and expected format

## Files to Investigate

- `zig/src/changes_vtab.zig` — `changesUpdate` function, especially "no local row" branch
- `zig/src/merge_insert.zig` — `insertOrUpdateColumn` and related functions
- `zig/harness/test-app-todo.sh` — Reproduction script

## Acceptance Criteria

1. [ ] `INSERT INTO crsql_changes` succeeds for new rows
2. [ ] `bash zig/harness/test-app-todo.sh` passes on Zig
3. [ ] All 3 app simulation tests pass (todo, chat, inventory)
4. [ ] Existing parity tests continue to pass

## Parent Docs / Cross-links

- Discovered in: `.tasks/active/TASK-194-real-world-app-simulation.md`
- Test scripts: `zig/harness/test-app-*.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-25: Created from TASK-194 findings. This is P0 blocker.

## Completion Notes
(Empty until done.)
