# TASK-098: Zig on-disk DB persistence tests

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
- Created by: `.tasks/active/TASK-073-compare-rust-zig-tests.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
**Critical real-system gap**: All Zig harness tests currently use `:memory:` databases. This means:

1. No persistence testing - data survives only within session
2. No WAL mode testing - in-memory doesn't use WAL
3. No crash recovery testing - can't simulate process restart
4. No file locking testing - in-memory has no file contention

Real applications use on-disk databases. The Zig extension must be validated against file-backed SQLite.

## Files to Modify
- `zig/harness/test-persistence.sh` (new file)
- `zig/harness/test-parity.sh` (add test runner call)

## Acceptance Criteria
- [x] New test script `zig/harness/test-persistence.sh` exists
- [x] Tests use temp directory with actual `.sqlite` files
- [x] Tests cover:
  - Create CRR, insert data, close DB, reopen, verify data
  - Create CRR, insert data, close DB, reopen, query `crsql_changes`
  - Verify `crsql_site_id()` persists across sessions
  - Verify `crsql_db_version()` persists across sessions
  - WAL mode: insert in one session, read uncommitted in another (optional)
- [x] Cleanup: test removes temp files on exit
- [x] Reproducible command: `bash zig/harness/test-persistence.sh`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-persistence.sh
```

## Progress Log
### 2025-12-18
- Task created from TASK-073 coverage analysis
- Identified as HIGH priority real-system gap

### 2025-12-20
- Implemented `zig/harness/test-persistence.sh` with 7 test suites, 12 assertions
- Wired into `zig/harness/test-parity.sh` test runner
- All tests pass

## Completion Notes
**Date**: 2025-12-20

**Files created/modified**:
- `zig/harness/test-persistence.sh` (new, 297 lines)
- `zig/harness/test-parity.sh` (updated to include persistence tests)

**Test coverage (12 assertions)**:
1. Data persistence across sessions (2 tests)
2. crsql_changes persistence (2 tests)
3. crsql_site_id() persistence across sessions (2 tests)
4. crsql_db_version() persistence across sessions (2 tests)
5. Clock table persistence (1 test)
6. CRR schema persistence (1 test)
7. WAL mode persistence (2 tests)

**Test execution**:
```
bash zig/harness/test-persistence.sh
```

**Results**: 12 PASSED, 0 FAILED, 0 SKIPPED

**Key implementation details**:
- Uses `.tmp/persistence-test-$$` for temp files (per AGENTS.md)
- Proper cleanup with `trap 'rm -rf "$TMPDIR"' EXIT`
- Tests real file-backed databases, not `:memory:`
- Validates site_id and db_version survive DB close/reopen
- Tests CRR triggers remain active after session restart
