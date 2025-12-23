# TASK-172 — Malformed input error handling tests

## Goal
Verify Zig handles malformed inputs gracefully (error, not crash).

## Status
- State: backlog
- Priority: high (security/robustness)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
The `pk` column in crsql_changes contains packed binary data. Malformed data could crash or corrupt. We need to verify graceful error handling.

## Files to Modify
- `zig/harness/test-error-handling.sh` (new, ~250 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Test truncated PK blob → error, not crash
2. Test wrong column count header → error
3. Test invalid type markers → error
4. Test corrupted length prefixes → error
5. Error messages are actionable (not just "error")
6. Database remains uncorrupted after each error
7. Zig and Rust/C produce same error behavior

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-error-handling.sh - Malformed input handling

test_truncated_pk() {
    # Valid PK would be X'010901' (1 col, int8, value 1)
    # Send X'0109' (truncated)
    # Expect: error, no crash
}

test_wrong_column_count() {
    # Header says 3 columns but only 1 value
    # Expect: error
}

test_invalid_type_marker() {
    # Use type marker 0xFF (invalid)
    # Expect: error
}

test_db_uncorrupted_after_error() {
    # Insert valid row
    # Attempt malformed insert (fails)
    # Verify: valid row still intact
    # Verify: can still INSERT/UPDATE/DELETE
}
```

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
