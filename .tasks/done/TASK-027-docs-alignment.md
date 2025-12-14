# TASK-027: Docs Alignment (zig/README.md)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [x] Complete

## Priority
high

## Assigned To
subagent (docs-alignment)

## Description
Fix zig/README.md to accurately reflect the current state of the Zig implementation. The README currently claims "partial C oracle" and "missing alter" but research/zig-cr/92-gap-backlog.md shows MVP is complete with 154/154 tests passing.

## Files to Modify
- `zig/README.md` - Update status table and known limitations

## Acceptance Criteria
- [x] Status table shows accurate test counts (154/154 total)
- [x] C oracle tests show 20/20 (not "partial")
- [x] `crsql_begin_alter` / `crsql_commit_alter` listed as implemented (not missing)
- [x] Known Limitations section updated to reflect actual remaining gaps
- [x] Reference to `research/zig-cr/10-test-oracle.md` and `core/src/*.test.c` as acceptance suite

## Source of Truth
- `research/zig-cr/92-gap-backlog.md` (current status)
- Test harness results from `zig/harness/` and `zig/browser-test/`

## Progress Log
### 2025-12-14
- Task created from start-here.md gap analysis

## Completion Notes
### 2025-12-14
- Updated Status table to show 154/154 tests passing (100%)
- Changed C oracle tests from "Partial 3/4" to "Complete 20/20 (5 suites)"
- Updated test breakdown: 64 Zig unit, 52 parity, 18 browser, 20 C oracle
- Added `crsql_begin_alter`/`crsql_commit_alter` to Implemented Functions
- Added `crsql_fract_as_ordered` and `crsql_fract_fix_conflict_return_old_key` to Implemented Functions
- Replaced false "Not yet implemented" claims with actual remaining gaps (performance, Service Worker, reactive queries, Windows/iOS/Android packaging)
- Added reference to `research/zig-cr/10-test-oracle.md` (test oracle strategy)
- Added reference to `research/zig-cr/92-gap-backlog.md` (current status)
