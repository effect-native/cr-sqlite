# TASK-138: Add config isolation test

## Priority: P2 (SECONDARY)

## Summary

Verify that configuration changes are connection-local and reset to defaults
when a new connection is opened.

## Files to Modify

- `zig/harness/test-config.sh`

## Acceptance Criteria

1. [ ] Test CF-007: Config resets on new connection
2. [ ] Verify both implementations have same default after new connection

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

## Completion Notes

(To be filled upon completion)
