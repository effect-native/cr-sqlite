# TASK-204 — Fix PK UPDATE Test Schema Mismatch

## Goal
Fix `test-pk-update.sh` Test 1d to use correct pks table schema.

## Status
- State: triage
- Priority: LOW (test bug, not implementation bug)
- Discovered: 2025-12-25 (Round 73)

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

1. [ ] Test 1d passes
2. [ ] All 16 PK UPDATE tests pass

## Parent Docs / Cross-links

- Related: `.tasks/done/TASK-110-zig-pk-update-compound-text-pk.md`

## Progress Log
- 2025-12-25: Created from Round 73 findings.

## Completion Notes
(Empty until done.)
