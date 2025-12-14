# TASK-028: Spec-First Realistic Scenario Tests

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [x] Complete

## Priority
medium

## Assigned To
subagent (spec-tests)

## Description
Create new shell-based tests under `zig/harness/` that serve as both executable examples AND documentation. These tests should demonstrate realistic use cases that a person would actually want to do with CR-SQLite. Follow the "thing-golf" philosophy from `research/thing-golf.md` — keep them clean, focused, and smugly self-validating.

## Constraint
Per `.wishes/stop-before-typescript.md`: **NO TypeScript**. All new tests must be Zig or shell-based. If a scenario truly demands TS (e.g., browser-specific features), document it and mark as blocked.

## Files to Create/Modify
- `zig/harness/test-realistic-sync.sh` - Realistic multi-device sync scenario
- `zig/harness/test-realistic-collab.sh` - Collaborative editing scenario
- `zig/harness/test-realistic-offline.sh` - Offline-first scenario with conflict resolution

## Acceptance Criteria
- [x] At least 2 new realistic scenario tests created
- [x] Each test is self-documenting (clear comments explaining the scenario)
- [x] Each test demonstrates a real-world use case (not just edge cases)
- [x] Tests serve dual purpose: validation AND example documentation
- [x] All new tests pass
- [x] Tests follow existing harness conventions (exit codes, output format)
- [x] `make test-parity` still works (if tests are added to parity suite)

## Example Scenarios to Consider
1. **Multi-device sync**: Two "devices" make changes, sync via crsql_changes, both converge
2. **Collaborative editing**: Concurrent edits to same row, CRDT merge resolves correctly
3. **Offline-first**: Device goes offline, makes changes, reconnects, syncs cleanly
4. **Fractional ordering**: Collaborative list reordering with `crsql_fract_key_between`

## Progress Log
### 2025-12-14
- Task created from .wishes/spec-first-RGRTDD.md
- Implemented 3 realistic scenario tests (all passing)

## Completion Notes
### Completed 2025-12-14

Created 3 shell-based realistic scenario tests in `zig/harness/`:

1. **test-realistic-sync.sh** - Multi-Device Todo List Sync
   - Alice and Bob each make changes offline
   - Both sync via crsql_changes
   - Demonstrates: crsql_as_crr(), extracting changes, applying changes, convergence
   - Shows site_id origin tracking

2. **test-realistic-collab.sh** - Collaborative Document Editing
   - Concurrent edits to same cell
   - Demonstrates: col_version conflict resolution (higher wins)
   - Shows tie-breaker behavior (same col_version → larger value wins)
   - Proves sync order independence (CRDT property)

3. **test-realistic-offline.sh** - Offline-First Field Worker App
   - Field worker accumulates changes while offline
   - Server receives updates from other workers
   - Bidirectional sync on reconnect
   - Demonstrates: db_version as sync cursor, incremental sync pattern

All tests:
- Are self-documenting with extensive comments
- Follow existing harness conventions (set -euo pipefail, temp cleanup, exit codes)
- Use INTEGER PRIMARY KEYs (TEXT PKs have WIP insertIntoBaseTable support)
- Pass consistently
