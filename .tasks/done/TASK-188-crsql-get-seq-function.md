# TASK-188 — Implement crsql_get_seq() function

## Goal
Add crsql_get_seq() function that returns current seq value without incrementing.

## Status
- State: done
- Priority: medium (API completeness)
- Discovered: Round 64 update tasks

## Problem
Rust/C has `crsql_get_seq()` function but Zig doesn't:
```sql
-- Rust/C oracle:
SELECT crsql_get_seq(); -- Returns 0 (or current seq)

-- Zig:
SELECT crsql_get_seq(); -- ERROR: no such function
```

## Context
- `crsql_increment_and_get_seq()` exists in both implementations
- `crsql_get_seq()` is a read-only version that doesn't increment
- Used by sync clients to get current seq without side effects

## Files to Modify
- `zig/src/site_identity.zig` — add function implementation and register it

## Acceptance Criteria
1. `SELECT crsql_get_seq()` returns current seq value
2. Calling it multiple times returns same value (no increment)
3. Value matches `crsql_increment_and_get_seq()` before any increment
4. Zig matches Rust/C oracle behavior

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Related: TASK-181 (crsql_sha — also missing function)

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-22: Implemented crsqlGetSeqFunc and registered crsql_get_seq in site_identity.zig

## Completion Notes
- Date: 2025-12-22
- Implementation:
  - Added `crsqlGetSeqFunc` function in `zig/src/site_identity.zig` (line ~552)
  - Registered `crsql_get_seq` SQL function with 0 arguments in `register()` (line ~656)
  - Function returns `pending_seq` without incrementing (read-only)
- Test script: `zig/harness/test-get-seq.sh`
- All acceptance criteria met:
  1. ✅ `SELECT crsql_get_seq()` returns current seq value
  2. ✅ Multiple calls return same value (no increment)
  3. ✅ Value matches `crsql_increment_and_get_seq()` before any increment
  4. ✅ Zig matches Rust/C oracle behavior (verified in tests 5 & 6)
