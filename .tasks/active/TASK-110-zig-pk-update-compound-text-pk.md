# TASK-110: Zig PK UPDATE — Compound/Text PK tombstone fix

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Parent task: `.tasks/done/TASK-105-zig-pk-update-must-emit-tombstone-and-insert.md`
- Test harness: `zig/harness/test-pk-update.sh`
- Zig implementation: `zig/src/as_crr.zig`

## Description
TASK-105 implemented PK UPDATE tombstone semantics for integer PKs, but compound/text PK updates still fail.

### Root Cause
When rowid doesn't change (compound/text PKs), the new sentinel overwrites the tombstone because:
- Clock table uses `rowid` as the key
- For integer PKs, rowid = pk value (changes on update)
- For compound/text PKs, rowid is auto-assigned (doesn't change on update)
- When creating tombstone then new entries, they share the same rowid

### Failing Tests (5)
- Test 1d: Clock table queries for integer PK (test issue — uses blob-encoded pk)
- Test 2b: Compound PK (a,b) tombstone not created
- Test 3b: Full compound PK update tombstone not created  
- Test 4b: Text PK (sku) tombstone not created

### Potential Solutions
1. **Store pk blob in clock table** instead of rowid
2. **Use separate tombstone tracking table**
3. **Create separate pks entries for tombstoned pk blobs**

## Files to Modify
- `zig/src/as_crr.zig` — trigger generation
- `zig/src/changes_vtab.zig` — potentially clock table schema
- `zig/harness/test-pk-update.sh` — may need test fixes

## Acceptance Criteria
- [x] All 16 tests in `bash zig/harness/test-pk-update.sh` pass
- [x] No regression in `make -C zig test-parity`
- [x] Compound PK update creates tombstone for old PK
- [x] Text PK update creates tombstone for old PK

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-pk-update.sh
# Current: 11 PASS, 5 FAIL
# Target: 16 PASS, 0 FAIL
```

## Progress Log
### 2025-12-20
- Task created as follow-up from TASK-105
- Analyzed root cause: clock table used base table rowid as key, but compound/text PKs don't change rowid on UPDATE
- Implemented solution: decouple pks table key from base table rowid

## Completion Notes
### 2025-12-20 - COMPLETED

**Solution Implemented:**

The fix decoupled the pks table's primary key from the base table rowid. This allows compound/text PK updates to have separate entries for the old and new PK blobs.

**Schema Changes:**

1. **pks table schema** (`as_crr.zig`):
   - Added `base_rowid` column to store the base table rowid
   - `pk` column is now auto-increment (independent of base table)
   - `pks` blob has UNIQUE constraint for lookups
   - Old schema: `(pk INTEGER PRIMARY KEY, pks BLOB NOT NULL)`
   - New schema: `(pk INTEGER PRIMARY KEY, base_rowid INTEGER, pks BLOB NOT NULL UNIQUE)`

2. **Trigger changes** (`as_crr.zig`):
   - INSERT trigger: Uses `INSERT ... ON CONFLICT(pks) DO UPDATE SET base_rowid`
   - UPDATE trigger: Looks up clock.pk via `SELECT pk FROM pks WHERE pks = blob`
   - PK UPDATE trigger: Creates tombstone at old pks key, creates new pks entry for new blob
   - DELETE trigger: Sets `base_rowid = NULL` to mark tombstoned entries

3. **Value lookup changes** (`changes_vtab.zig`):
   - `fetchColumnValue` now looks up `base_rowid` from pks table before querying base table
   - Handles tombstoned entries (base_rowid = NULL) by returning NULL

4. **Sync path changes** (`merge_insert.zig`):
   - Added `getBaseRowidFromPk` helper function
   - `deleteFromBaseTable` and `rowExistsInBaseTable` now look up base_rowid first
   - `insertIntoPksTable` uses `ON CONFLICT` to handle resurrection

5. **Test fix** (`test-pk-update.sh`):
   - Test 1d now queries clock table via JOIN with pks table (clock.pk = pks.pk, pks.pks = blob)

**Files Modified:**
- `zig/src/as_crr.zig` - pks table schema, all trigger generation
- `zig/src/changes_vtab.zig` - fetchColumnValue to use base_rowid
- `zig/src/merge_insert.zig` - getBaseRowidFromPk, deleteFromBaseTable, rowExistsInBaseTable, insertIntoPksTable
- `zig/harness/test-pk-update.sh` - Test 1d clock table query fix

**Test Results:**
- All 16 PK UPDATE tests pass
- All parity tests pass (no regressions)
- E2E sync tests pass
- Resurrection tests pass
- Merge tests pass
