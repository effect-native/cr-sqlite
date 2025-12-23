# TASK-170 — Foreign key and cascade test suite (consolidated)

## Goal
Create tests verifying Zig handles foreign keys and cascading operations between CRR tables.

## Status
- State: backlog
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
- `zig/harness/test-fk-crr.sh` (new, ~350 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Test FK between two CRR tables (parent/child)
2. Test child arriving before parent during sync
3. Test ON DELETE CASCADE behavior
4. Verify cascade creates proper clock entries
5. Verify cascade clock entries have correct CL
6. Verify sync convergence after cascade
7. Document any Zig vs Rust/C differences

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-fk-crr.sh - Foreign keys between CRR tables

setup_fk_tables() {
    # CREATE TABLE parent (id INTEGER PRIMARY KEY NOT NULL);
    # CREATE TABLE child (id INTEGER PRIMARY KEY NOT NULL, 
    #                     parent_id INTEGER REFERENCES parent(id) ON DELETE CASCADE);
    # SELECT crsql_as_crr('parent');
    # SELECT crsql_as_crr('child');
}

test_fk_basic() {
    # INSERT parent, INSERT child
    # Verify: both have clock entries
}

test_child_before_parent_sync() {
    # Site A: INSERT parent, INSERT child
    # Site B: receive child first (via crsql_changes)
    # Document: does it fail? defer? succeed with dangling FK?
    # Site B: receive parent
    # Verify: FK now satisfied
}

test_cascade_delete() {
    # INSERT parent + 3 children
    # DELETE parent (cascades to children)
    # Verify: all 4 rows have tombstones
    # Verify: child tombstones have clock entries
    # Verify: child tombstone CL values
}

test_cascade_sync_convergence() {
    # Site A: cascade delete
    # Site B: has parent + children
    # Sync A to B
    # Verify: B has all tombstones
}
```

## Parent Docs / Cross-links
- Supersedes: TASK-171
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Consolidated FK and cascade tasks.

## Completion Notes
(Empty until done.)
