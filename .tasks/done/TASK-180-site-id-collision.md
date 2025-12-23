# TASK-180 — Test site_id collision handling

## Goal
Document behavior when two databases have the same site_id.

## Status
- State: done
- Priority: medium (edge case, security)

## Context
What happens if:
1. You copy a database file (both have same site_id)
2. Both copies make changes
3. You try to sync them

This could happen accidentally (backup restored) or maliciously.

## Files to Modify
- `zig/harness/test-site-id-collision.sh` (new)

## Acceptance Criteria
1. Create database with CRR, insert data ✅
2. Copy database file (now two DBs with same site_id) ✅
3. Make different changes in each copy ✅
4. Attempt to sync between them ✅
5. Document behavior: ✅
   - Does it detect collision? NO - cr-sqlite does not detect same-site_id
   - Does it error or corrupt? Neither - applies normal CRDT merge rules
   - What's the recommended recovery? Regenerate site_id on one copy
6. Zig and Rust/C oracle produce identical results ✅

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-23: Implemented test suite with 7 test scenarios.

## Completion Notes
- Date: 2025-12-23
- Created `zig/harness/test-site-id-collision.sh` with comprehensive test suite

### Test Results Summary
- **13 passed, 0 failed, 0 skipped, 0 divergences**

### Documented Behavior
When two databases have the same site_id (e.g., from copying a database file):

1. **Detection**: cr-sqlite does NOT detect or reject same-site_id changes
2. **Merging**: Changes are applied using normal CRDT merge rules
3. **Convergence**: Both copies converge using:
   - col_version comparison (higher wins)
   - Value comparison as tie-breaker
4. **Risk**: With same site_id, col_versions may collide causing
   unpredictable tie-breaking based on value comparison
5. **Internal divergence**: When both copies make changes at same col_version,
   internal divergence is expected (each copy may end up with different values
   depending on sync order)

### Key Test Scenarios
1. Basic setup - copying preserves site_id ✅
2. Independent changes on both copies ✅
3. Sync changes between colliding site IDs ✅
4. Bidirectional sync (convergence test) ✅
5. Concurrent inserts with same PK ✅
6. Delete/resurrection with same site_id ✅
7. Zig vs Rust/C parity (full collision scenario) ✅

### Recommended Recovery
```sql
-- Regenerate site_id on one copy:
DELETE FROM crsql_site_id;
-- (triggers regeneration on next access)

-- Or manually set:
INSERT INTO crsql_site_id VALUES (randomblob(16));
```

### Parity
Zig and Rust/C implementations behave **identically** under site_id collision.
Both exhibit the same internal divergence patterns when col_versions collide.
