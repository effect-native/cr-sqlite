# TASK-118: Fix shell quoting in automigrate test script

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Triggering task: `.tasks/done/TASK-076-impl-automigrate.md`
- Spec task: `.tasks/done/TASK-075-spec-automigrate.md`
- Failing script: `zig/harness/test-automigrate.sh`
- Delegate evidence: `.tasks/DELEGATE_WORK_HANDOFF.md` (Round 2025-12-20 (43))

## Description
`crsql_automigrate` is implemented, but `zig/harness/test-automigrate.sh` reports `15/17` passing due to **shell escaping issues** (per TASK-076 completion notes and delegate evidence). This task fixes the test harness so the failing cases exercise the implementation correctly.

Constraints:
- This is a **test-only** task.
- Do not change `zig/src/automigrate.zig` or other implementation files.

## Files to Modify
- `zig/harness/test-automigrate.sh`
- (optional) `zig/harness/test-parity.sh` (only if it needs to report automigrate results consistently)

## Acceptance Criteria
- [ ] `bash zig/harness/test-automigrate.sh` reports `17/17` pass
- [ ] The fix is robust to schema strings containing single quotes and newlines
- [ ] No changes to Zig implementation code

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-automigrate.sh
```

## Progress Log
### 2025-12-20
- Filed from Round 43 evidence: 2 failures attributed to shell quoting.

## Completion Notes
(append date + commit hash)
