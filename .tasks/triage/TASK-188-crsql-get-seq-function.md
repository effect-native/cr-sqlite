# TASK-188 — Implement crsql_get_seq() function

## Goal
Add crsql_get_seq() function that returns current seq value without incrementing.

## Status
- State: triage
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
- `zig/src/db_version.zig` (or `seq.zig` if exists) — add function
- `zig/src/ffi/init.zig` — register function

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

## Completion Notes
(Empty until done.)
