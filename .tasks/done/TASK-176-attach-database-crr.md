# TASK-176 — Test ATTACH database with CRR tables

## Goal
Verify Zig handles attached databases with CRR tables.

## Status
- State: done
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
- 2025-12-23: Implemented test suite `zig/harness/test-attach-crr.sh`.

## Completion Notes
**Date:** 2025-12-23

**Test Suite Created:** `zig/harness/test-attach-crr.sh`

**Test Results:** All 15 tests PASSED, 0 failed, 0 skipped, 0 divergences

**Findings (answers to original questions):**

1. **Can you query crsql_changes from attached DB?**
   - YES. `SELECT * FROM other.crsql_changes` works when `other.db` is attached.
   - Both Zig and Rust/C implementations support this.

2. **Is site_id scoped per-database or per-connection?**
   - **Per-database.** Each database file has its own persistent site_id.
   - `crsql_site_id()` returns the main connection's DB site_id even when attached DBs are present.
   - site_id is stable across connections to the same database file.

3. **Can you sync between main and attached CRRs?**
   - YES. Changes can be exported from one DB via `crsql_changes` and applied to another via `INSERT INTO crsql_changes`.
   - Cross-database INSERT through ATTACH also works (`INSERT INTO other.items ...`).

**Test Coverage:**
1. Create main.db and other.db with CRR tables ✓
2. ATTACH other.db and query attached tables ✓
3. Query other.crsql_changes from attached database ✓
4. Verify site_id is per-database (different site_ids for different DBs) ✓
5. site_id stable across connections to same DB ✓
6. site_id scope when querying through ATTACH ✓
7. Sync from other.db to main.db using crsql_changes ✓
8. Verify main.db has complete merged data (4 items) ✓
9. Cross-database INSERT through ATTACH ✓
10. Cross-db INSERT persistence ✓
11. DETACH and verify data persistence ✓
12. db_version tracking with attached databases ✓

**Oracle Parity:** Full parity confirmed between Zig and Rust/C implementations on all tests.
