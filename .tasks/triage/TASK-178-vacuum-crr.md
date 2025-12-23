# TASK-178 — Test VACUUM on database with CRR tables

## Goal
Verify VACUUM doesn't corrupt CRR metadata.

## Status
- State: triage
- Priority: low (maintenance operation)

## Context
VACUUM rebuilds the entire database file. Questions:
1. Are clock tables preserved correctly?
2. Are internal rowid mappings preserved?
3. Is crsql_master preserved?
4. Can you sync after VACUUM?

## Files to Modify
- `zig/harness/test-vacuum-crr.sh` (new)

## Acceptance Criteria
1. Create CRR table with data
2. Generate some clock entries
3. Run VACUUM
4. Verify: data intact
5. Verify: clock tables intact
6. Verify: can still INSERT/UPDATE/DELETE
7. Verify: can still sync via crsql_changes
8. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
