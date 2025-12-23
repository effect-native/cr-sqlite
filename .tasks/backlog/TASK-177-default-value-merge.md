# TASK-177 — DEFAULT value merge semantics tests

## Goal
Verify Zig handles DEFAULT column values correctly during merge.

## Status
- State: backlog
- Priority: high (schema evolution)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
From Python `test_sync.py`. When columns have DEFAULT values, merge behavior must be consistent.

## Files to Modify
- `zig/harness/test-default-merge.sh` (new, ~200 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Explicit value beats DEFAULT (when explicit has higher col_version)
2. DEFAULT value handling after ALTER ADD COLUMN
3. Zig and Rust/C produce identical behavior

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-default-merge.sh - DEFAULT value merge semantics

test_explicit_beats_default() {
    # Site A: table with col DEFAULT 'default_val'
    # Site A: INSERT without specifying col (uses default)
    # Site B: INSERT same PK with col='explicit'
    # Sync A to B (or B to A)
    # Verify: explicit wins (higher col_version)
}

test_default_after_alter() {
    # Site A: ALTER ADD COLUMN foo DEFAULT 'new_default'
    # Site A: existing rows get default value
    # Site B: UPDATE existing row's foo column
    # Sync
    # Verify: explicit update wins
}
```

## Parent Docs / Cross-links
- Python tests: `py/correctness/tests/test_sync.py`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
