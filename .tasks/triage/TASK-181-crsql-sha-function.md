# TASK-181 — Implement crsql_sha() function

## Goal
Add crsql_sha() function that returns git commit SHA (for version tracing).

## Status
- State: triage
- Priority: low (debug/version info only)
- Confirmed: Round 64 — verified missing via function list comparison

## Problem
```sql
-- Rust/C oracle:
SELECT crsql_sha(); -- Returns '0d62b52b4662ee1a762c9fd9264d48a91ab8df83'

-- Zig:
SELECT crsql_sha(); -- ERROR: no such function
```

## Context
Rust/C has `crsql_sha()` that returns the git commit hash of the build.
Useful for debugging "which version is this?"

## Files to Modify
- `zig/src/sha.zig` (new)
- `zig/src/ffi/init.zig` (register function)

## Acceptance Criteria
1. `SELECT crsql_sha()` returns a string
2. String is the git commit hash (or "unknown" if not available)
3. Function is deterministic (same result every call)

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
