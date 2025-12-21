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

1. [ ] Test XO-003: Zig creates -> Rust modifies -> Zig reads
2. [ ] Test XO-004: Rust creates -> Zig modifies -> Rust reads
3. [ ] Test XO-006: Multiple alternating opens maintain consistency

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

## Completion Notes

(To be filled upon completion)
