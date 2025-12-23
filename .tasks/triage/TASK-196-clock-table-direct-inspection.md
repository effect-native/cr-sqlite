# TASK-196 — Deep Clock Table Inspection Tests

## Goal
Directly compare clock table internals between Zig and Rust/C to invalidate "Zig parity is complete".

## Status
- State: triage
- Priority: MEDIUM (internal implementation detail, but affects sync)
- Discovered: 2025-12-23 (hypothesis invalidation request)

## Hypothesis to Invalidate
"Zig creates identical clock table entries as Rust/C for all operations."

## Test Approach
After each operation, dump and compare:

1. **Clock table contents**:
   ```sql
   SELECT * FROM {table}__crsql_clock ORDER BY key, cid, site_id;
   ```

2. **Sentinel entries**:
   - Count of cid='-1' entries
   - CL values for sentinels
   - Timing of sentinel creation

3. **Site ID ordinals**:
   ```sql
   SELECT * FROM crsql_site_id ORDER BY ordinal;
   ```

4. **PKS table entries**:
   ```sql
   SELECT * FROM {table}__crsql_pks ORDER BY __crsql_key;
   ```

5. **db_version progression**:
   - After INSERT, UPDATE, DELETE
   - After sync receive
   - After rollback

## Operations to Test
- Single INSERT
- Bulk INSERT (100 rows)
- UPDATE single column
- UPDATE multiple columns
- UPDATE with same value (no-op)
- DELETE single row
- DELETE then re-INSERT (resurrection)
- ALTER ADD COLUMN
- ALTER DROP COLUMN

## Files to Create
- `zig/harness/test-clock-internals.sh` (new)

## Acceptance Criteria
1. Byte-identical clock entries for same operations
2. Same db_version progression
3. Same site_id ordinal assignments
4. Either find divergence OR confirm internal parity

## Parent Docs / Cross-links
- Clock table schema: TASK-123 (fixed pk→key rename)
- Trigger parity: `test-trigger-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.

## Completion Notes
(Empty until done.)
