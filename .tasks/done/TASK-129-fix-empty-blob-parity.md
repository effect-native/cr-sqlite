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
- [x] Empty blob (`X''`) is reported as `X''` in crsql_changes, not NULL
- [x] Existing parity tests still pass
- [x] `test-fuzz-parity.sh` passes with no divergences

## Parent Docs
- TASK-127 (discovered the bug)
- `research/zig-cr/92-gap-backlog.md`

## Completion Notes

**Date**: 2024-12-20

**Root Cause**: In `fetchColumnValue()` at `zig/src/changes_vtab.zig:1087-1089`, when handling `SQLITE_BLOB` type, the code was calling `resultBlob(ctx, blob_ptr, blob_len, ...)` directly. For empty blobs:
- `sqlite3_column_type()` correctly returns `SQLITE_BLOB`
- `sqlite3_column_blob()` returns `NULL` (documented SQLite behavior for zero-length blobs)
- `sqlite3_column_bytes()` returns `0`

When `sqlite3_result_blob()` receives a NULL pointer, even with length 0, it produces NULL output instead of an empty blob.

**Fix**: Modified `zig/src/changes_vtab.zig` lines 1087-1104 to detect the empty blob case (col_type is SQLITE_BLOB but pointer is NULL) and pass a static non-NULL pointer with length 0 to produce `X''`:

```zig
if (blob_ptr != null) {
    resultBlob(ctx, blob_ptr, blob_len, api.getTransientDestructor());
} else {
    // Empty blob case: col_type is SQLITE_BLOB but pointer is NULL
    // Use a static non-NULL pointer with length 0 to produce X''
    const empty_blob = [_]u8{};
    resultBlob(ctx, &empty_blob, 0, api.SQLITE_STATIC);
}
```

**Verification**:
```bash
# Manual test - now outputs X'' instead of NULL
nix run nixpkgs#sqlite -- :memory: -cmd ".load zig/zig-out/lib/libcrsqlite.dylib" <<'SQL'
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, X'');
SELECT quote(val) FROM crsql_changes WHERE [table]='t' AND cid='data';
SQL
# Output: X''

# Parity tests pass
make -C zig test-parity  # All tests pass

# Oracle parity tests pass  
bash zig/harness/test-oracle-parity.sh  # 18 passed, 0 failed
```
