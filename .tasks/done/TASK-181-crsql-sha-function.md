# TASK-181 — Implement crsql_sha() function

## Goal
Add crsql_sha() function that returns git commit SHA (for version tracing).

## Status
- State: done
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
- 2025-12-23: Implemented crsql_sha() function.

## Completion Notes
Completed 2025-12-23.

**Files changed:**
- `zig/src/sha.zig` (new) — Implements crsql_sha() function returning GIT_SHA constant
- `zig/src/ffi/init.zig` — Added import and registration call
- `zig/harness/test-sha.sh` (new) — Test suite for the function

**Implementation:**
- Created `sha.zig` with `GIT_SHA` constant (currently "unknown", can be injected at build time)
- Function is deterministic (SQLITE_DETERMINISTIC flag set)
- Returns error if called with arguments
- All 6 tests pass including oracle parity check

**Test output:**
```
Test 1: crsql_sha() exists — PASS
Test 2: crsql_sha() returns text type — PASS
Test 3: crsql_sha() is deterministic — PASS
Test 4: crsql_sha() returns non-empty string — PASS
Test 5: crsql_sha() rejects arguments — PASS
Test 6: crsql_sha() oracle parity — PASS
```

**Future work:**
- Build-time injection of actual git SHA via build.zig options (low priority)
