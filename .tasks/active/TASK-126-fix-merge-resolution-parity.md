# TASK-126: Fix merge resolution parity with oracle

## Status
- [ ] Planned

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Test: `zig/harness/test-oracle-parity.sh` (Test 3a, 3b)
- Test: `zig/harness/test-parity.sh` (ValueWin test)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Zig implementation's merge resolution differs from the Rust/C oracle:

**Test 3a: Remote wins with higher col_version**
- Zig: returns "local" (local value kept)
- Rust/C: returns "remote_winner" (remote value applied)

**Test 3b: site_id tiebreaker (lower site_id wins on equal col_version)**
- Zig: returns empty
- Rust/C: returns "low_site"

**ValueWin test (test-parity.sh)**
- Expected rows_impacted = 1
- Got: empty (merge not applied)

This suggests the merge logic in `changes_vtab.zig` or `merge_insert.zig` is not correctly determining when remote wins.

## Files to Modify
- `zig/src/changes_vtab.zig` — merge resolution logic
- `zig/src/merge_insert.zig` — merge helpers

## Acceptance Criteria
- [ ] `zig/harness/test-oracle-parity.sh` Test 3a passes
- [ ] `zig/harness/test-oracle-parity.sh` Test 3b passes
- [ ] `zig/harness/test-parity.sh` ValueWin test passes
- [ ] No regressions in other parity tests
