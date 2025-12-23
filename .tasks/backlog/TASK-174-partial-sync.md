# TASK-174 — Partial sync / interruption recovery tests

## Goal
Verify Zig handles interrupted sync correctly (no partial state).

## Status
- State: backlog
- Priority: high (production reliability)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
Network can fail mid-sync. Need to verify atomicity guarantees.

## Files to Modify
- `zig/harness/test-partial-sync.sh` (new, ~200 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Large batch interrupted → no partial changes
2. db_version unchanged after failed batch
3. Retry succeeds with full batch
4. Zig and Rust/C produce identical behavior

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-partial-sync.sh - Interrupted sync handling

test_rollback_on_interrupt() {
    # Record initial db_version
    # BEGIN transaction
    # INSERT 500 changes via crsql_changes
    # ROLLBACK (simulate interrupt)
    # Verify: no changes applied
    # Verify: db_version unchanged
}

test_retry_after_interrupt() {
    # Simulate failed batch (ROLLBACK)
    # Retry same batch (COMMIT)
    # Verify: all changes applied
    # Verify: db_version correct
}

test_large_batch_atomicity() {
    # 10,000 row batch
    # Verify: all-or-nothing semantics
}
```

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
