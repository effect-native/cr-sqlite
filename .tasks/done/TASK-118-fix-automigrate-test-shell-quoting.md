# TASK-118: Fix shell quoting in automigrate test script

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] `bash zig/harness/test-automigrate.sh` reports `17/17` pass
- [x] The fix is robust to schema strings containing single quotes and newlines
- [x] No changes to Zig implementation code

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-automigrate.sh
```

## Progress Log
### 2025-12-20
- Filed from Round 43 evidence: 2 failures attributed to shell quoting.
- Fixed Tests 9 and 10 shell quoting issues in test script.
- All 17 tests now pass.

## Completion Notes
### 2025-12-20

**Root Cause:** Bash single-quote escaping vs SQL single-quote escaping mismatch.

**Test 9 (Idempotent):**
- Problem: `SCHEMA` variable contained `SELECT crsql_as_crr('item');` 
- When embedded in SQL as `'$SCHEMA'`, the inner single quotes broke the SQL string literal
- Fix: Split into two variables - `SCHEMA_SETUP` (for initial SQL execution) and `SCHEMA_ARG` (with doubled single quotes `''item''` for SQL string escaping)

**Test 10 (Complex schema):**
- Problem: Used bash single-quoted string `'...'` containing `''deck''`
- Bash interprets `''` inside single quotes as string concatenation (empty + text + empty), not as escaped quotes
- Result: `''deck''` became just `deck` (unquoted identifier)
- Fix: Changed to bash double-quoted string `"..."` with properly escaped double quotes for SQL identifiers, and `''deck''` for SQL string literals (which bash preserves in double-quoted strings)

**Files Modified:**
- `zig/harness/test-automigrate.sh` (only file modified, as required)

**Final Output:**
```
PASSED:  17
FAILED:  0
SKIPPED: 0
✓ All tests PASSED
```
