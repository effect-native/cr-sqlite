# TASK-186 — Decide schema mismatch behavior for unknown columns

## Goal
Decide whether Zig should error or ignore unknown columns during sync, then align implementations.

## Status
- State: triage
- Priority: MEDIUM (behavioral difference, not data corruption)
- Discovered: Round 62 (TASK-173 test suite)

## Problem
When source has a column that destination doesn't have, the implementations differ:
- **Zig**: Returns ERROR
- **Rust/C**: Gracefully IGNORES the unknown column, syncs known columns

**Test failure from `test-schema-mismatch.sh`:**
```
Divergences found:
  - source_has_extra_column: Zig='ERROR' vs Rust='IGNORED'
```

## Scenario
1. Site A: table with columns (id, name, extra)
2. Site B: table with columns (id, name) — no 'extra' column
3. Site A: INSERT with extra='value'
4. Sync A→B
5. **Rust/C**: Row synced, 'extra' column data ignored, known columns applied
6. **Zig**: ERROR returned, nothing synced

## Analysis
Both approaches have merit:
- **Zig (strict)**: Catches schema drift early, prevents silent data loss
- **Rust/C (lenient)**: Allows staggered migrations, more forgiving in production

## Decision Needed
1. Should Zig match Rust/C behavior (ignore unknown columns)?
2. Or is the strict behavior intentional/preferred?
3. Should this be configurable?

## Files to Modify
- `zig/src/changes_vtab.zig` — column lookup in xUpdate
- `zig/src/merge_insert.zig` — column resolution

## Acceptance Criteria
1. Decision documented
2. If aligning with Rust/C: `bash zig/harness/test-schema-mismatch.sh` — Test 1 passes
3. If keeping strict: Test marked as known divergence with rationale

## Parent Docs / Cross-links
- Test: `zig/harness/test-schema-mismatch.sh` (Test 1: source_has_extra_column)
- Triggering task: `.tasks/done/TASK-173-schema-mismatch.md`

## Progress Log
- 2025-12-22: Created from Round 62 divergence discovery.

## Completion Notes
(Empty until done.)
