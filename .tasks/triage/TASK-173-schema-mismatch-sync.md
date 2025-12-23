# TASK-173 — Test schema mismatch during sync

## Goal
Verify Zig handles schema mismatches gracefully during sync.

## Status
- State: triage
- Priority: medium (production scenario)

## Context
Different sites may have different schemas due to:
- Staggered migrations
- Independent schema evolution
- Partial sync before schema propagated

Scenarios:
1. Source has column that destination doesn't
2. Destination has column that source doesn't
3. Column types differ
4. PK structure differs

## Files to Modify
- `zig/harness/test-schema-mismatch.sh` (new)

## Acceptance Criteria
1. Site A adds column 'foo', inserts data
2. Sync to Site B (which doesn't have column 'foo')
3. Document behavior: error? ignored? partial apply?
4. Reverse: Site B has column 'bar' that Site A doesn't
5. Sync Site B to Site A
6. Document behavior
7. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Related: TASK-172 (malformed input)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
