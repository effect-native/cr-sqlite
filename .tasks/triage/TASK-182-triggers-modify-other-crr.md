# TASK-182 — Test user triggers that modify other CRR tables

## Goal
Verify behavior when user-defined triggers INSERT/UPDATE/DELETE other CRR tables.

## Status
- State: triage
- Priority: medium (real-world pattern)

## Context
Apps often have triggers like:
```sql
CREATE TRIGGER audit_log AFTER UPDATE ON items
INSERT INTO audit_log (item_id, action) VALUES (NEW.id, 'update');
```

If audit_log is also a CRR:
1. Does the trigger-based insert get clock entries?
2. Is it in the same transaction as the original update?
3. Does db_version advance correctly?

## Files to Modify
- `zig/harness/test-trigger-crr.sh` (new)

## Acceptance Criteria
1. Create two CRR tables (items, audit_log)
2. Create trigger: UPDATE items → INSERT audit_log
3. UPDATE an item
4. Verify: audit_log has row
5. Verify: audit_log row has clock entries
6. Verify: db_version advanced for both changes
7. Sync to Site B
8. Verify: both tables sync correctly
9. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Related: TASK-170 (FK between CRRs)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
