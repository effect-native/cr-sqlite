# TASK-105: Zig PK UPDATE must emit tombstone + new insert

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete (partial — integer PK complete, compound/text PK needs follow-up)

## Priority
high

## Assigned To
delegate-round-42

## Parent Docs / Cross-links
- Triggered by: `.tasks/active/TASK-095-zig-test-pk-update-semantics.md`
- New failing test: `zig/harness/test-pk-update.sh`
- Rust/C expected behavior reproduced via: `nix run github:subtleGradient/sqlite-cr`
- Zig parity runner: `zig/harness/test-parity.sh`

## Description
The new Zig harness test for PK UPDATE semantics (`zig/harness/test-pk-update.sh`) currently fails.

Observed behavior in Zig extension:
- Base table row updates work.
- `crsql_changes` and `__crsql_clock` do not record PK updates as a DELETE tombstone for the old PK + INSERT for the new PK.

Expected behavior (matches Rust/C reference implementation):
- Updating a primary key column in a CRR table produces:
  1. A tombstone entry for the old PK (sentinel `cid = '-1'`)
  2. New change entries for the new PK
- Clock table (`<table>__crsql_clock`) reflects both the tombstoned old PK and the newly inserted PK.

This is sync-critical: without tombstones, replicas can diverge because the old PK is never deleted.

## Files to Modify
- `zig/src/*` (exact file(s) TBD once root cause located)
- Potentially: trigger generation / update handling code paths that respond to UPDATE of PK columns

## Acceptance Criteria
- [ ] `bash zig/harness/test-pk-update.sh` passes (no FAIL lines)
- [ ] `bash zig/harness/test-parity.sh` reports PK UPDATE tests passing
- [ ] For single-column PK update, `crsql_changes` contains:
  - a `cid='-1'` row for old PK
  - column rows for new PK
- [ ] For compound PK update, `crsql_changes` contains:
  - a `cid='-1'` row for old PK
  - column rows for new PK
- [ ] `<table>__crsql_clock` contains entries for both old and new PKs after a PK update

## Repro
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-pk-update.sh
```

## Evidence
- Zig output currently shows no `cid='-1'` rows after PK UPDATE.
- Rust/C reference (via `sqlite-cr`) shows tombstones and new inserts for PK UPDATE.

## Progress Log
### 2025-12-20
- Added PK UPDATE harness test in TASK-095; test fails against Zig extension.
- Confirmed expected behavior via `nix run github:subtleGradient/sqlite-cr`.

### 2025-12-20 (delegate round 42)
- Implemented `createPkUpdateTrigger` in `zig/src/as_crr.zig`
- Modified `isSentinelRow` in `zig/src/changes_vtab.zig` for tombstone visibility
- Results: **11 PASS, 5 FAIL** (up from 0 PASS originally)
- Passing: All integer PK tests (single-column, sequential updates)
- Failing: Compound PK and text PK tombstone tests (architectural limitation)

## Completion Notes
### 2025-12-20
- **Partial completion**: Integer PK UPDATE works correctly
- Files modified:
  - `zig/src/as_crr.zig` - Added `createPkUpdateTrigger` function
  - `zig/src/changes_vtab.zig` - Fixed `isSentinelRow` for tombstone visibility
- Known limitation: Compound/text PKs where rowid doesn't change cause sentinel overwrite
- Follow-up task created: `.tasks/backlog/TASK-110-zig-pk-update-compound-text-pk.md`
