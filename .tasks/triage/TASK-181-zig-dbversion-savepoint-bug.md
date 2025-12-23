# TASK-181 — Fix Zig db_version not advancing with savepoint + crsql_changes

## Goal
Fix the Zig implementation so db_version correctly advances when changes are applied 
via crsql_changes within a transaction that uses savepoints.

## Status
- State: triage
- Priority: high (sync correctness - db_version is critical for sync protocols)

## Context
Discovered in TASK-175 savepoint sync testing. When changes are applied via 
`INSERT INTO crsql_changes` within a transaction that uses savepoints, the Zig 
implementation fails to advance db_version after COMMIT.

**Reproduction:**
```sql
CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('items');
SELECT crsql_db_version();  -- Returns 0

BEGIN;
INSERT INTO crsql_changes ("table", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('items', X'010901', 'name', 'item1', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
SAVEPOINT sp1;
INSERT INTO crsql_changes ("table", pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES ('items', X'010902', 'name', 'item2', 1, 1, X'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1', 1, 0);
ROLLBACK TO sp1;
COMMIT;

SELECT crsql_db_version();  -- Zig: 0 (BUG), Rust/C: 1 (CORRECT)
```

**Observed Behavior:**
- Rust/C oracle: db_version advances 0 -> 1 after COMMIT
- Zig: db_version stays at 0 after COMMIT

**Impact:**
This breaks sync protocols that rely on db_version to track which changes have been
applied locally. If db_version doesn't advance, the sync cursor will be wrong.

## Files to Modify
- `zig/src/` (db_version tracking logic - needs investigation)

## Acceptance Criteria
1. After the repro above, db_version should be 1 (not 0)
2. Test 7 in `zig/harness/test-savepoint-sync.sh` should pass
3. All other savepoint tests should continue to pass
4. No divergence with Rust/C oracle

## Parent Docs / Cross-links
- Discovered by: TASK-175 (savepoint sync tests)
- Test file: `zig/harness/test-savepoint-sync.sh`
- Related: db_version parity tests in `zig/harness/test-db-version-parity.sh`

## Progress Log
- 2025-12-23: Created from TASK-175 test divergence.

## Completion Notes
(Empty until done.)
