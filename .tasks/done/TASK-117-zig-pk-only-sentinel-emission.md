# TASK-117: Zig — PK-only tables don't emit sentinel rows

## Status
- [x] In Progress
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Triggering task: `.tasks/done/TASK-070-zig-parity-extdata-sandbox.md`
- Test harness: `zig/harness/test-sandbox.sh` (4 failures due to this)
- C reference: `core/src/sandbox.test.c` (uses PK-only tables)

## Description
When a table has only primary key columns (no data columns), inserting rows should emit a sentinel change with `cid = '-1'` to track row existence. The Rust/C implementation does this correctly; Zig does not.

### Evidence

**Rust/C (correct):**
```sql
CREATE TABLE foo (a PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1);
SELECT COUNT(*) FROM crsql_changes;  -- Returns 1
SELECT cid FROM crsql_changes;       -- Returns '-1' (sentinel)
```

**Zig (incorrect):**
```sql
CREATE TABLE foo (a PRIMARY KEY NOT NULL);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1);
SELECT COUNT(*) FROM crsql_changes;  -- Returns 0 (WRONG)
```

### Impact
- sandbox.test.c tests fail (basic sync between two DBs)
- PK-only tables cannot sync their row existence
- Affects any CRDT setup with key-only membership tables

### Root Cause Analysis
The Zig INSERT trigger only iterates over non-PK columns to emit changes. When there are no non-PK columns, no changes are emitted. Need to:
1. Detect PK-only table scenario
2. Emit sentinel row (`cid = '-1'`, `val = NULL`) for row existence

## Files to Modify
- `zig/src/as_crr.zig` — INSERT trigger generation
- `zig/src/changes_vtab.zig` — Virtual table sentinel handling
- `zig/src/merge_insert.zig` — Merge insert pk handling
- `zig/harness/test-sandbox.sh` — Will pass once fixed

## Acceptance Criteria
- [x] PK-only table INSERT emits sentinel change
- [x] Sentinel format matches Rust/C: `cid = '-1'`, `val = NULL`
- [x] `bash zig/harness/test-sandbox.sh` passes (9/9)
- [x] No regression in `make -C zig test-parity`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite/zig
bash harness/test-sandbox.sh
# Current: 5/9 pass, 4/9 fail
# Target: 9/9 pass
```

## Progress Log
### 2025-12-20
- Task created during TASK-070 completion
- Root cause: INSERT trigger doesn't emit sentinel for PK-only tables

### 2025-12-20 (fix implementation)
- **Root cause analysis refined:**
  1. `as_crr.zig` INSERT trigger was emitting sentinels for ALL tables (including non-PK-only)
  2. `changes_vtab.zig` was filtering out ALL odd col_version sentinels (which filtered PK-only sentinels)
  3. Rust/C only emits sentinels for PK-only tables, Zig was emitting for all

- **Changes made:**
  1. `zig/src/as_crr.zig`: Only emit sentinel in INSERT trigger for PK-only tables (non_pk_count == 0)
  2. `zig/src/changes_vtab.zig`: 
     - Stop filtering sentinels (now only emitted for PK-only tables)
     - Fix `fetchCausalLength` to return 1 (live) when no sentinel exists
     - Fix xUpdate handler to create rows for PK-only tables when receiving live sentinel
     - Fix pk lookup bug: use pks table auto-increment key for clock entries, not base table rowid
  3. `zig/src/merge_insert.zig`:
     - Add `insertPkOnlyRow` function for inserting rows with only PK columns
     - Add `insertIntoPksTableAndGetPk` function to return the pks table pk after insert

- **Test results:**
  - `bash zig/harness/test-sandbox.sh`: 9/9 PASS
  - `make -C zig test-parity`: All tests pass (rows_impacted, compound PK, core functions, filters, rowid slab, alter, noops, fract)

## Completion Notes
(to be filled when complete)
