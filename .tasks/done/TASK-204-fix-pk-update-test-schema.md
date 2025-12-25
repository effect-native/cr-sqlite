# TASK-204 — Fix PK UPDATE Test Schema Mismatch

## Goal
Fix `test-pk-update.sh` Test 1d to use correct pks table schema.

## Status
- State: done
- Priority: LOW (test bug, not implementation bug)
- Discovered: 2025-12-25 (Round 73)
- Completed: 2025-12-25 (Round 74)

## Problem

Test 1d in `zig/harness/test-pk-update.sh` uses outdated column names:

```sql
-- Test currently uses:
SELECT COUNT(*) FROM foo__crsql_clock c JOIN foo__crsql_pks p ON c.pk = p.pk WHERE p.pks = X'010901';

-- But the actual schema is:
CREATE TABLE "foo__crsql_pks" (__crsql_key INTEGER PRIMARY KEY, "id")
```

The columns `pk` and `pks` don't exist. The actual columns are:
- `__crsql_key` (the key)
- `id` (the actual PK column value)

## Fix

Update the test to use:
```sql
SELECT COUNT(*) FROM foo__crsql_clock c WHERE c.key = (SELECT __crsql_key FROM foo__crsql_pks WHERE id = 1);
```

Or use the clock table's `key` column directly:
```sql
SELECT COUNT(*) FROM foo__crsql_clock WHERE key = <expected_key>;
```

## Files to Modify

- `zig/harness/test-pk-update.sh` — Fix Test 1d SQL queries

## Acceptance Criteria

1. [x] Test 1d passes
2. [x] All 16 PK UPDATE tests pass

## Parent Docs / Cross-links

- Related: `.tasks/done/TASK-110-zig-pk-update-compound-text-pk.md`

## Progress Log
- 2025-12-25: Created from Round 73 findings.
- 2025-12-25: Fixed by Round 74 delegation.

## Completion Notes
- Fixed Test 1d SQL queries in `zig/harness/test-pk-update.sh`
- Changed `c.pk` and `p.pk` and `p.pks` to use correct columns: `key`, `__crsql_key`, `id`
- All 16/16 PK UPDATE tests now pass
- Commit: (pending)
