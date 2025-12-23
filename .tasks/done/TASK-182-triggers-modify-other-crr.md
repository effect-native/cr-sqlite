# TASK-182 — Test user triggers that modify other CRR tables

## Goal
Verify behavior when user-defined triggers INSERT/UPDATE/DELETE other CRR tables.

## Status
- State: done
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
- 2025-12-23: Created `zig/harness/test-trigger-crr.sh` with 11 test scenarios (31 assertions).

## Completion Notes
- **Created**: `zig/harness/test-trigger-crr.sh` (566 lines)
- **Test Results**: All 31 tests PASSED, 0 FAILED, 0 SKIPPED
- **Parity**: Zig and Rust/C oracle produce identical results for all scenarios

### Test Scenarios Implemented:
1. Basic trigger INSERT (UPDATE items -> INSERT audit_log)
2. Trigger-inserted row has clock entries
3. db_version advances for both changes
4. Sync works for triggered inserts
5. DELETE trigger (DELETE items -> INSERT audit_log)
6. Multiple CRR triggers in chain (A -> B -> C)
7. Trigger with FK-like reference (soft relationship)
8. Parity — Zig and Rust/C produce identical results
9. INSERT trigger (INSERT items -> INSERT audit_log)
10. Trigger UPDATE on another CRR (UPDATE A -> UPDATE B)
11. Trigger DELETE on another CRR (cascade via trigger)

### Key Findings:
1. User triggers that modify other CRRs work correctly
2. Trigger-inserted rows get proper clock entries
3. db_version advances for both original and triggered changes
4. Triggered changes appear in crsql_changes for sync
5. Trigger chains (A->B->C) work across multiple CRRs
6. DELETE triggers can implement soft cascades between CRRs

### No Divergences Found:
- Zig and Rust/C implementations behave identically for all trigger scenarios
