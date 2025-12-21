# TASK-130: Fix test-trigger-parity.sh column name bug

## Priority: P0 (BLOCKING)

## Summary

The `test-trigger-parity.sh` script queries the wrong column name for Zig clock tables,
causing 15 false test failures. Both implementations now use `key` but the test queries `pk`.

## Files to Modify

- `zig/harness/test-trigger-parity.sh`

## Acceptance Criteria

1. [x] Change `pk` to `key` in `dump_clock_zig` function (line ~98)
2. [x] Run test-trigger-parity.sh and verify tests pass
3. [x] If any tests fail after fix, those are REAL parity gaps (document them)

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
- 2024-12-20: Fixed `pk` → `key` column name bug. Also updated comment and removed unnecessary `AS pk` alias in dump_clock_rust.

## Completion Notes

**Fixed:** Changed `pk` to `key` in `dump_clock_zig` function (line 98) and cleaned up the comment/alias in `dump_clock_rust`.

**Test Results:** 13 passed, 2 failed

**REAL Parity Gaps Discovered (not false positives):**

Both failures are in "resurrection" scenarios (re-INSERT after DELETE):

1. **Test 1 Step 5: Re-INSERT same PK (resurrection)**
   - Divergence in `-1` sentinel row: Rust `col_version=3, db_version=5`, Zig `col_version=2, db_version=4`
   - Divergence in `seq` values: Rust uses `seq=0,1,2`, Zig uses `seq=0,0,1`

2. **Test 2 Step 5: Re-INSERT compound PK (resurrection)**
   - Same pattern as above

**Root Cause Analysis:**
- The `-1` sentinel (tombstone marker) versioning differs on resurrection
- The `seq` counter behavior differs when resurrecting deleted rows
- Rust increments col_version for the sentinel on resurrection; Zig does not
- Rust's seq starts at 0 and increments; Zig's seq resets differently

This is a legitimate implementation difference in how DELETE→INSERT sequences are tracked, requiring a separate fix task.
