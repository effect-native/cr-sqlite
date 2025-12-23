# TASK-176 — Test ATTACH database with CRR tables

## Goal
Verify Zig handles attached databases with CRR tables.

## Status
- State: triage
- Priority: medium (multi-database patterns)

## Context
SQLite supports attaching multiple databases:
```sql
ATTACH 'other.db' AS other;
SELECT * FROM other.crsql_changes;
```

Questions:
1. Can you query crsql_changes from attached DB?
2. Is site_id scoped per-database or per-connection?
3. Can you sync between main and attached CRRs?

## Files to Modify
- `zig/harness/test-attach-crr.sh` (new)

## Acceptance Criteria
1. Create main.db with CRR table
2. Create other.db with CRR table
3. ATTACH other.db
4. Query other.crsql_changes
5. Verify: changes are scoped to other.db
6. Verify: site_id is per-database
7. Sync from other to main via crsql_changes
8. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
