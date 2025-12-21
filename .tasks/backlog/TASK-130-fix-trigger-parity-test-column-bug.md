# TASK-130: Fix test-trigger-parity.sh column name bug

## Priority: P0 (BLOCKING)

## Summary

The `test-trigger-parity.sh` script queries the wrong column name for Zig clock tables,
causing 15 false test failures. Both implementations now use `key` but the test queries `pk`.

## Files to Modify

- `zig/harness/test-trigger-parity.sh`

## Acceptance Criteria

1. [ ] Change `pk` to `key` in `dump_clock_zig` function (line ~98)
2. [ ] Run test-trigger-parity.sh and verify all 15 tests pass
3. [ ] If any tests fail after fix, those are REAL parity gaps (document them)

## Bug Details

**Location:** Lines 97-98

```bash
# CURRENT (BROKEN)
dump_clock_zig() {
    $SQLITE "$db" -cmd ".load $ZIG_EXT sqlite3_crsqlite_init" \
        "SELECT pk, col_name, col_version, db_version, seq FROM ${table}__crsql_clock..."
}

# FIXED
dump_clock_zig() {
    $SQLITE "$db" -cmd ".load $ZIG_EXT sqlite3_crsqlite_init" \
        "SELECT key, col_name, col_version, db_version, seq FROM ${table}__crsql_clock..."
}
```

## Evidence

Direct verification shows Zig DOES populate clock tables correctly:

```sql
-- Zig
CREATE TABLE foo (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
SELECT crsql_as_crr('foo');
INSERT INTO foo VALUES (1, 'test');
SELECT key, col_name, col_version, db_version, seq FROM foo__crsql_clock;
-- Returns: 1|name|1|1|0
```

Both implementations use the same schema:
```sql
CREATE TABLE IF NOT EXISTS "foo__crsql_clock" (
  "key" INTEGER NOT NULL,  -- NOT "pk"
  "col_name" TEXT NOT NULL,
  ...
)
```

## Experiments Unblocked

- TR-001 through TR-030 (all 19 trigger/clock experiments)

## Parent Docs / Cross-links

- Analysis: `research/zig-cr/97-test-gap-analysis.md`
- Experiments: `research/zig-cr/96-ideal-parity-experiments.md`

## Progress Log

- 2024-12-20: Created task card

## Completion Notes

(To be filled upon completion)
