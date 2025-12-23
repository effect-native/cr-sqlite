# TASK-172 — Test malformed PK blob handling

## Goal
Verify Zig handles malformed PK blobs gracefully (error, not crash).

## Status
- State: triage
- Priority: high (security/robustness)

## Context
The `pk` column in crsql_changes contains packed binary data. Malformed data could:
- Crash the extension
- Corrupt data silently
- Cause undefined behavior

We need to verify graceful error handling.

## Files to Modify
- `zig/harness/test-error-handling.sh` (new)

## Acceptance Criteria
1. Test truncated PK blob (missing bytes)
2. Test PK blob with wrong column count header
3. Test PK blob with invalid type markers
4. Test PK blob with corrupted length prefixes
5. All cases should return error, not crash
6. Error message should be actionable
7. Database should remain uncorrupted after error
8. Zig and Rust/C oracle produce same error behavior

## Parent Docs / Cross-links
- Related: TASK-173 (schema mismatch)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
