# TASK-138: Add config isolation test

## Priority: P2 (SECONDARY)

## Summary

Verify that configuration changes are connection-local and reset to defaults
when a new connection is opened.

## Files to Modify

- `zig/harness/test-config.sh`

## Acceptance Criteria

1. [x] Test CF-007: Config isolation across connections
2. [x] Verify both implementations have same behavior (parity test)

## Test Template

```bash
# CF-007: Config resets on new connection
DB=$(mktemp)

# Connection 1: Set non-default value
run_both "$DB" "SELECT crsql_config_set('merge-equal-values', 0);"
VALUE1=$(run_both "$DB" "SELECT crsql_config_get('merge-equal-values');")
assert_equals "0" "$VALUE1" "Config was set"

# Connection 2: Should be back to default
VALUE2=$(run_both "$DB" "SELECT crsql_config_get('merge-equal-values');")
assert_equals "1" "$VALUE2" "Config reset to default on new connection"
```

## Parent Docs / Cross-links

- Experiments: `research/zig-cr/96-ideal-parity-experiments.md` (CF-007)
- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`

## Progress Log

- 2024-12-20: Created task card
- 2024-12-20: Implemented config isolation tests in `zig/harness/test-config.sh`

## Completion Notes

**Completed**: 2024-12-20

### Tests Added

The test script `zig/harness/test-config.sh` was expanded with config isolation tests:

1. **Test CF-007a**: Config persists in database across connections (Zig)
   - Verifies that `crsql_config_set` persists to the database
   - A new connection to the SAME database sees the persisted value

2. **Test CF-007b**: Fresh database has default config (Zig)
   - Verifies default value for fresh database

3. **Test CF-007c Parity**: Compare Zig vs Rust/C oracle behavior
   - Tests that both implementations have same persistence behavior
   - Tests that both implementations have same default value

### Key Discovery

The original task assumed config "resets on new connection". Testing revealed:

- **Config is stored in the database**, not just per-connection memory
- Both Zig and Rust/C implementations persist config to `crsql_config` table
- A new connection to the SAME database sees the persisted value (correct behavior)
- A fresh database uses the default value

### Parity Issue Found

The test discovered a parity divergence in DEFAULT VALUES:

- **Rust/C oracle default**: `0` (per `core/src/ext-data.c:72`)
- **Zig implementation default**: `1`

This is a real bug that needs to be fixed in the Zig implementation.

### Test Results

```
PASSED:  15
FAILED:  1  (default value parity divergence)
```

### Commands to Reproduce

```bash
bash zig/harness/test-config.sh
```
