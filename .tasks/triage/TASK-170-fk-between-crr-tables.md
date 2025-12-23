# TASK-170 — Test foreign keys between CRR tables

## Goal
Verify Zig handles foreign key constraints between CRR tables correctly during sync.

## Status
- State: triage
- Priority: high (real-world apps have FKs)

## Context
No existing tests verify FK behavior between CRR tables. Real apps commonly have:
- Parent/child relationships (orders → line_items)
- Many-to-many via junction tables
- Self-referential FKs (org hierarchy)

Key questions:
1. What happens when child row arrives before parent?
2. Does FK violation during merge fail or defer?
3. Are FK constraints even compatible with CRRs?

## Files to Modify
- `zig/harness/test-fk-crr.sh` (new)

## Acceptance Criteria
1. Create parent CRR table with PK
2. Create child CRR table with FK to parent
3. Insert parent, then child — works
4. Sync child to Site B (parent not yet synced)
5. Document behavior (fail? deferred? ignored?)
6. Sync parent to Site B
7. Verify FK constraint now satisfied
8. Zig and Rust/C oracle produce identical results (or document difference)

## Parent Docs / Cross-links
- Related: TASK-171 (cascading deletes)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
