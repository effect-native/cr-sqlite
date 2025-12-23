# TASK-171 — Test ON DELETE CASCADE between CRR tables

## Goal
Verify Zig handles cascading deletes between CRR tables correctly.

## Status
- State: triage
- Priority: high (data integrity)

## Context
When parent row is deleted with ON DELETE CASCADE:
- Child rows should be deleted
- But do child deletions get proper clock entries?
- Do cascaded deletes get proper CL values?
- What happens during sync convergence?

This is critical for data integrity in relational schemas.

## Files to Modify
- `zig/harness/test-fk-crr.sh` (extend)

## Acceptance Criteria
1. Create parent CRR with child CRR (ON DELETE CASCADE)
2. Insert parent + children
3. Delete parent
4. Verify: children deleted locally
5. Verify: clock entries exist for child deletions
6. Verify: child deletions have correct CL
7. Sync to Site B
8. Verify: Site B has parent and child tombstones
9. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Related: TASK-170 (FK basics)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
