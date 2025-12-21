# TASK-129: Fix empty blob handling in Zig crsql_changes

## Goal
Fix the divergence where Zig's `crsql_changes` virtual table reports empty blobs (`X''`) as `NULL`.

## Background
Discovered by TASK-127 fuzzing. The Rust/C oracle correctly distinguishes between empty blobs and NULL values, but Zig treats them as equivalent.

## Minimal Reproduction
```sql
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, X'');
SELECT quote(val) FROM crsql_changes WHERE [table]='t' AND cid='data';
-- Expected: X''
-- Actual (Zig): NULL
```

## Impact
- **Data corruption**: Applications using empty blobs will have incorrect data synced
- **Sync divergence**: Peers will disagree on row values after sync

## Files to Investigate
- `zig/src/changes_vtab.zig` - Changes virtual table implementation
- `zig/src/triggers.zig` - Trigger logic that populates clock tables
- `zig/src/value.zig` (if exists) - Value serialization/deserialization

## Acceptance Criteria
- [ ] Empty blob (`X''`) is reported as `X''` in crsql_changes, not NULL
- [ ] Existing parity tests still pass
- [ ] `test-fuzz-parity.sh` passes with no divergences

## Parent Docs
- TASK-127 (discovered the bug)
- `research/zig-cr/92-gap-backlog.md`
