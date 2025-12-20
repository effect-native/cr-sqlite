# TASK-104: Fix `test-parity.sh` pass counting for `test-multiconn.sh`

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
low

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Trigger: `zig/harness/test-parity.sh` integration for `zig/harness/test-multiconn.sh`
- Runner file: `zig/harness/test-parity.sh`
- New test: `zig/harness/test-multiconn.sh`
- Task that introduced it: `.tasks/done/TASK-099-zig-multiconn-test.md`

## Description
`zig/harness/test-parity.sh` currently counts passes in sub-tests by grepping for `PASS:`.

`zig/harness/test-multiconn.sh` emits `PASS:` lines for both Zig and Rust/C oracle runs, which causes `test-parity.sh` to over-count passes (e.g. +9 instead of +6). This doesn’t fail the suite but makes the aggregate summary misleading.

## Files to Modify
- `zig/harness/test-parity.sh`
- (optional) `zig/harness/test-multiconn.sh`

## Acceptance Criteria
- [ ] `zig/harness/test-parity.sh` adds the correct number of passed tests from `test-multiconn.sh`
- [ ] The suite summary totals remain stable and meaningful
- [ ] `bash zig/harness/test-parity.sh` still exits non-zero on real failures

## Progress Log
### 2025-12-20
- Created as a triage follow-up after observing inflated pass counts from multiconn parity output.

## Completion Notes
