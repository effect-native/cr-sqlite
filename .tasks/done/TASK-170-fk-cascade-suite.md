# TASK-170 — Foreign key and cascade test suite (consolidated)

## Goal
Create tests verifying Zig handles foreign keys and cascading operations between CRR tables.

## Status
- State: done
- Priority: high (real-world apps have FKs)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
Consolidates TASK-170 and TASK-171. No existing tests verify FK behavior between CRR tables.

Key questions to answer:
1. Can CRR tables have FK constraints to each other?
2. What happens when child row syncs before parent?
3. Do cascaded deletes get proper clock entries?
4. Is the cascade CL correct for sync convergence?

## Files to Modify
- `zig/harness/test-fk-crr.sh` (new, ~350 lines) ✓
- `zig/harness/test-parity.sh` (wire in new test) ✓

## Acceptance Criteria
1. ✓ Test FK between two CRR tables (parent/child) - **FINDING: CRR tables REJECT FK constraints**
2. ✓ Test child arriving before parent during sync - Works with soft relationships
3. ✓ Test ON DELETE CASCADE behavior - **FINDING: CASCADE not available on CRR tables**
4. ✓ Verify cascade creates proper clock entries - N/A (CASCADE rejected)
5. ✓ Verify cascade clock entries have correct CL - N/A (CASCADE rejected)
6. ✓ Verify sync convergence after cascade - Tested with soft relationships
7. ✓ Document any Zig vs Rust/C differences - Both reject FK on CRR, parity confirmed

## Key Findings

**CR-SQLite intentionally REJECTS FK constraints on CRR tables.**

This is by design because FKs are incompatible with CRDTs:
- FK enforcement during sync can cause conflicts
- Cascades create non-deterministic outcomes on different sites  
- Child can arrive before parent in distributed sync

### What Works
1. **Non-CRR tables CAN have FKs referencing CRR tables**
2. **Soft relationships (no FK) work for CRR-to-CRR links**
3. **Out-of-order sync works with soft relationships**
4. **Delete convergence works correctly with soft relationships**

### Recommended Pattern for CRR-to-CRR Relationships
```sql
-- Instead of FK constraints, use soft relationships:
CREATE TABLE parent (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT DEFAULT ''
);
CREATE TABLE child (
    id INTEGER PRIMARY KEY NOT NULL,
    parent_id INTEGER NOT NULL DEFAULT 0,  -- No FK!
    data TEXT DEFAULT ''
);
SELECT crsql_as_crr('parent');
SELECT crsql_as_crr('child');

-- Application logic handles:
-- 1. Orphaned rows (no automatic CASCADE)
-- 2. Referential integrity checks
-- 3. Cleanup of dangling references
```

## Parent Docs / Cross-links
- Supersedes: TASK-171
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Consolidated FK and cascade tasks.
- 2025-12-23: Implemented test suite, discovered FK rejection is intentional, confirmed Zig/Rust parity.

## Completion Notes
- Date: 2025-12-23
- Result: 11 tests pass, 0 fail, 0 skip
- Files created:
  - `zig/harness/test-fk-crr.sh` (~350 lines)
- Files modified:
  - `zig/harness/test-parity.sh` (wired in FK tests)
- Key outcome: Documented that CR-SQLite intentionally rejects FK constraints on CRR tables.
  This is correct behavior - FKs and CRDTs are fundamentally incompatible.
  Apps should use soft relationships and handle referential integrity in application logic.
