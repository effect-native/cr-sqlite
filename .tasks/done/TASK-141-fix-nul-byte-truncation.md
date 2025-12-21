# TASK-141: Fix NUL byte truncation in text sync

## Summary

The Zig implementation truncates text values containing embedded NUL bytes (0x00) at the first NUL byte during sync. The Rust/C oracle correctly preserves the full text including NUL bytes.

## Evidence

From `zig/harness/test-boundary-values.sh` (EC-021):
```
FAIL: Text with NULL bytes mismatch
  Rust hex: 68656C6C6F00776F726C64 (len=11, "hello\0world")
  Zig hex:  68656C6C6F (len=5, "hello")
```

## Root Cause (Hypothesis)

SQLite stores text as C strings (NUL-terminated) but also tracks length. The issue is likely in one of:
1. `pack_columns` — when packing values for wire format
2. `changes_vtab.zig` — when reading/writing values via the changes virtual table
3. String handling that uses C-style strlen() instead of SQLite's length

## Files to Modify

- `zig/src/changes_vtab.zig` — check `fetchColumnValue()` for text handling
- `zig/src/pack.zig` — check text packing/unpacking
- Possibly `zig/src/merge_insert.zig` — check value handling during merge

## Acceptance Criteria

1. `bash zig/harness/test-boundary-values.sh` passes all 8 tests (including EC-021)
2. Text values with embedded NUL bytes roundtrip correctly:
   - INSERT into Zig DB with NUL bytes → SELECT returns full value
   - crsql_changes reports full value (not truncated)
   - Sync to Rust/C oracle preserves full value

## Reproduction Steps

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-boundary-values.sh
# EC-021 will fail
```

Minimal reproduction:
```sql
CREATE TABLE t (id INTEGER PRIMARY KEY, data TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'hello' || char(0) || 'world');
SELECT hex(val) FROM crsql_changes WHERE [table]='t' AND cid='data';
-- Expected: 68656C6C6F00776F726C64 (11 bytes)
-- Actual (Zig): 68656C6C6F (5 bytes)
```

## Parent Docs / Cross-links

- Discovered in: `.tasks/done/TASK-137-boundary-value-edge-cases.md`
- Test file: `zig/harness/test-boundary-values.sh`
- Related: Empty blob fix in `TASK-129` had similar root cause (pointer vs length handling)

## Progress Log

- [x] Created task card
- [x] Reproduced the failing test (EC-021 failed, 7/8 passed)
- [x] Investigated the root cause - discovered the issue was in the test's sync mechanism, not the Zig implementation
- [x] Verified Zig implementation correctly handles NUL bytes when querying directly (`hex(val)` returns full 11 bytes)
- [x] Identified that SQLite's `quote()` function truncates TEXT at first NUL byte
- [x] Fixed the test script to use `CAST(X'...' AS TEXT)` format for TEXT values during sync
- [x] Verified all 8 tests pass

## Completion Notes

**Date:** 2025-12-20

### Root Cause Analysis

The bug was **NOT** in the Zig implementation. Investigation revealed:

1. The Zig implementation correctly stores and retrieves TEXT values with embedded NUL bytes
2. Direct queries like `SELECT hex(val) FROM crsql_changes` return the full 11-byte value (`68656C6C6F00776F726C64`)
3. The issue was in the **test script's sync protocol**, which used SQLite's `quote(val)` function
4. SQLite's `quote()` function treats TEXT as C-strings and truncates at the first NUL byte:
   - `quote(CAST(X'68656C6C6F00776F726C64' AS TEXT))` → `'hello'` (5 bytes, truncated)

### Fix Applied

Modified `zig/harness/test-boundary-values.sh` to use a proper quoting expression for TEXT values that preserves embedded NUL bytes:

```sql
-- Before (buggy):
quote(val)

-- After (correct):
CASE typeof(val) 
  WHEN 'text' THEN 'CAST(X''' || hex(val) || ''' AS TEXT)'
  WHEN 'null' THEN 'NULL'
  ELSE quote(val)
END
```

This converts TEXT values to their hex representation and casts back to TEXT, preserving all bytes including embedded NUL characters.

### Test Results

```
Boundary Value Edge Case Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PASS:    8
  FAIL:    0
  SKIP:    0

All boundary value edge case tests PASSED
```

### Files Modified

- `zig/harness/test-boundary-values.sh` — Fixed sync SQL quoting to preserve NUL bytes in TEXT values

### Note for Implementers

When syncing `crsql_changes` data between databases:
- Do NOT use `quote(val)` for TEXT values - it truncates at NUL bytes
- Use `CAST(X'<hex>' AS TEXT)` format instead, or use BLOB types for binary data
- This is a SQLite `quote()` limitation, not a cr-sqlite limitation
