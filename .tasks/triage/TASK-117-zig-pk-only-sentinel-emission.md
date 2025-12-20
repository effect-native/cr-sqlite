# TASK-117: Zig — PK-only tables don't emit sentinel rows

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
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
- `zig/harness/test-sandbox.sh` — Will pass once fixed

## Acceptance Criteria
- [ ] PK-only table INSERT emits sentinel change
- [ ] Sentinel format matches Rust/C: `cid = '-1'`, `val = NULL`
- [ ] `bash zig/harness/test-sandbox.sh` passes (9/9)
- [ ] No regression in `make -C zig test-parity`

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
