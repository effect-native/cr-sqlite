# TASK-108: Fix `test-parity.sh` pass counting for `test-multiconn.sh`

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
low

## Assigned To
Claude (agent)

## Parent Docs / Cross-links
- Trigger: `zig/harness/test-parity.sh` integration for `zig/harness/test-multiconn.sh`
- Runner file: `zig/harness/test-parity.sh`
- New test: `zig/harness/test-multiconn.sh`
- Task that introduced it: `.tasks/done/TASK-099-zig-multiconn-test.md`

## Description
`zig/harness/test-parity.sh` currently counts passes in sub-tests by grepping for `PASS:`.

`zig/harness/test-multiconn.sh` emits `PASS:` lines for both Zig and Rust/C oracle runs, which causes `test-parity.sh` to over-count passes (e.g. +9 instead of +6). This doesn't fail the suite but makes the aggregate summary misleading.

## Files to Modify
- `zig/harness/test-parity.sh`
- (optional) `zig/harness/test-multiconn.sh`

## Acceptance Criteria
- [x] `zig/harness/test-parity.sh` adds the correct number of passed tests from `test-multiconn.sh`
- [x] The suite summary totals remain stable and meaningful
- [x] `bash zig/harness/test-parity.sh` still exits non-zero on real failures

## Progress Log
### 2025-12-20
- Created as a triage follow-up after observing inflated pass counts from multiconn parity output.
- Fixed: Modified `test-multiconn.sh` to emit `PASS:` only for actual Zig test assertions
- Oracle parity checks now emit `[Oracle] OK:` instead of `[Rust/C] PASS:`, so they provide 
  informational confirmation without inflating the pass count
- Before: 9 PASS lines (6 Zig + 3 Rust/C oracle), After: 6 PASS lines (Zig only)

## Completion Notes
**Fix Approach**: Modified `zig/harness/test-multiconn.sh` output format (Option 1 from Possible Solutions)

**Changes made**:
- Changed all `[Zig] PASS:` to `PASS:` (removes unnecessary prefix, consistent with other parity tests)
- Changed all `[Rust/C] PASS:` to `[Oracle] OK:` (informational, not counted by grep)
- Changed all `[Zig] FAIL:` to `FAIL:` and `[Zig] BLOCKED:` to `BLOCKED:` for consistency
- Oracle parity information is preserved but distinguished from countable pass assertions

**Before/After**:
- Before: `grep -c 'PASS:' test-multiconn.sh` returned 9 (inflated by oracle passes)
- After: `grep -c 'PASS:' test-multiconn.sh` returns 6 (correct count)

**Verification**:
- `bash zig/harness/test-multiconn.sh` exits 0 with 6 passes
- `[Oracle] OK:` lines still confirm parity with Rust/C extension
- Suite exit logic unchanged (exits non-zero on failures)
