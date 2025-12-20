# TASK-110: Zig PK UPDATE — Compound/Text PK tombstone fix

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

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
- [ ] All 16 tests in `bash zig/harness/test-pk-update.sh` pass
- [ ] No regression in `make -C zig test-parity`
- [ ] Compound PK update creates tombstone for old PK
- [ ] Text PK update creates tombstone for old PK

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

## Completion Notes
