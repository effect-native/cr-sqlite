# TASK-136: Add cross-open modification parity tests

## Priority: P2 (SECONDARY)

## Summary

Test that databases created by one implementation can be modified by the other,
and changes are visible when re-opened by the original implementation.

## Files to Modify

- `zig/harness/test-oracle-parity.sh` (expand cross-open section)
  OR
- `zig/harness/test-cross-open-parity.sh` (new file)

## Acceptance Criteria

1. [x] Test XO-003: Zig creates -> Rust modifies -> Zig reads
2. [x] Test XO-004: Rust creates -> Zig modifies -> Rust reads
3. [x] Test XO-006: Multiple alternating opens maintain consistency

**Additional tests added:**
- [x] XO-001: Zig creates -> Rust reads (read-only)
- [x] XO-002: Rust creates -> Zig reads (read-only)

## Test Template

```bash
# XO-003: Zig creates, Rust modifies, Zig reads
DB=$(mktemp)

# Zig creates
run_zig "$DB" "CREATE TABLE foo(id INTEGER PRIMARY KEY NOT NULL, name TEXT);"
run_zig "$DB" "SELECT crsql_as_crr('foo');"
run_zig "$DB" "INSERT INTO foo VALUES(1, 'original');"

# Rust modifies
run_rust "$DB" "UPDATE foo SET name='modified' WHERE id=1;"

# Zig reads
RESULT=$(run_zig "$DB" "SELECT name FROM foo WHERE id=1;")
assert_equals "modified" "$RESULT" "Rust modification visible to Zig"

# Also verify clock state is consistent
ZIG_CLOCK=$(run_zig "$DB" "SELECT col_version FROM foo__crsql_clock WHERE col_name='name';")
assert_equals "2" "$ZIG_CLOCK" "Clock updated correctly"
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (XO-003 through XO-006)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card
- 2024-12-20: Implemented test script

## Completion Notes

**Date**: 2024-12-20

**Files Created**:
- `zig/harness/test-cross-open-parity.sh` (new file, ~400 lines)

**Test Results**:
```
Results:
  PASSED:      17
  FAILED:      0
  KNOWN_FAIL:  3 (cross-implementation modification not yet supported)
  SKIPPED:     0
```

**Findings**:

The tests revealed important compatibility details:

1. **Read-only cross-open works perfectly:**
   - XO-001: Zig creates -> Rust reads ✓
   - XO-002: Rust creates -> Zig reads ✓
   - `site_id` preserved across implementations
   - `db_version` consistent across implementations
   - Base table data fully readable

2. **Cross-implementation modification NOT supported (known limitation):**
   - XO-003: Zig creates -> Rust modifies -> FAILS
   - XO-004: Rust creates -> Zig modifies -> FAILS
   - XO-006: Alternating modification -> FAILS

**Root Cause**:
The Zig and Rust implementations use incompatible trigger schemas:
- **Zig triggers** call `crsql_pack_columns()` directly in SQL
- **Rust triggers** call helper functions: `crsql_after_insert()`, `crsql_after_update()`, `crsql_after_delete()`

When one implementation opens a database created by the other, the triggers fail because:
- Rust sees "unsafe use of crsql_pack_columns()" when firing Zig triggers
- Zig sees "no such function: crsql_after_update" when firing Rust triggers

**Impact**:
- Databases can be safely READ by either implementation
- Sync via `crsql_changes` should still work (transfers data, not triggers)
- Direct modification requires using the same implementation that created the CRR

**Test Coverage**:
- 17 passing tests covering read-only scenarios
- 3 known-fail tests documenting modification limitations
- Exit code 0 (CI-friendly)

**Run command**:
```bash
bash zig/harness/test-cross-open-parity.sh
```
