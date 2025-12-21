# TASK-148 — Fix cross-platform compat test failures (resurrection + text newlines)

## Goal
Fix the 2 compatibility failures discovered by `zig/harness/test-cross-platform-compat.sh` after it was converted from SKIP to FAIL mode.

## Status
- State: triage
- Priority: high

## Problem Statement
`bash zig/harness/test-cross-platform-compat.sh` now runs (doesn't SKIP) and found 2 real failures:

1. **Test G: Resurrection** — table `sch_test already exists` error during schema evolution sync
2. **Test M: Text Edge Cases** — text with newlines differs between Zig and Rust/C export

These are Zig implementation bugs, not harness issues.

## Evidence
```
WARNING: Rust/C error:
Error: sqlite3_close() returns 5: unable to close due to unfinalized statements or unfinished backups

FAIL: Text id=5 differs (Zig='line1
line2', Rust=)
```

## Files to Modify
(To be determined during investigation)
- Likely `zig/src/changes_vtab.zig` or related sync export code

## Acceptance Criteria
1. `bash zig/harness/test-cross-platform-compat.sh` passes all tests (0 failures)
2. Text with newlines exports correctly from Zig
3. Resurrection/schema evolution sync works without "table already exists" errors

## Parent Docs / Cross-links
- `zig/harness/test-cross-platform-compat.sh`
- `.tasks/done/TASK-144-cross-platform-compat-no-skip.md` (discovered these)

## Progress Log
- 2025-12-21: Created from failures discovered by TASK-144 harness fix.

## Completion Notes
(Empty until done.)
