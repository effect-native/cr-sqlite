# TASK-174 — Test partial sync / interruption recovery

## Goal
Verify Zig handles interrupted sync correctly (no partial state).

## Status
- State: triage
- Priority: high (production reliability)

## Context
Network can fail mid-sync. Questions:
1. If sync is interrupted after 50% of changes, what state is DB in?
2. Are partial changes rolled back?
3. Can sync resume from where it left off?
4. Is db_version consistent after recovery?

## Files to Modify
- `zig/harness/test-partial-sync.sh` (new)

## Acceptance Criteria
1. Start large batch INSERT INTO crsql_changes (1000 rows)
2. Interrupt mid-batch (kill connection or ROLLBACK)
3. Verify: no partial changes applied
4. Verify: db_version unchanged from before sync
5. Retry full batch
6. Verify: all changes applied atomically
7. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Related: TASK-175 (savepoints during sync)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
