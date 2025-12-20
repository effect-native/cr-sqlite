# TASK-106: Zig WAL concurrent read/write persistence test

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(completed by agent)

## Parent Docs / Cross-links
- Triggered by: `.tasks/active/TASK-098-zig-ondisk-db-tests.md`
- Repo guidance: `AGENTS.md` (Zig testing rule)

## Description
Current persistence tests validate WAL mode *persistence* (journal_mode=wal and data survives reopen), but do not test the optional concurrency behavior described in TASK-098:

- "WAL mode: insert in one session, read uncommitted in another (optional)"

A dedicated multi-process harness test can validate the intended semantics under WAL with two concurrent connections (writer holds transaction open; reader attempts to observe behavior).

Note: SQLite default semantics are that other connections cannot read uncommitted changes unless `PRAGMA read_uncommitted=1` is set, and even then behavior may vary. This task is to precisely define and test the intended behavior for CR-SQLite under WAL, not to assume a particular outcome.

## Files to Modify
- `zig/harness/test-wal-concurrency.sh` (new standalone script)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
- [x] Test uses a real `.sqlite` file under `.tmp/`
- [x] Test spawns 2 separate sqlite processes (writer + reader)
- [x] Writer process starts a transaction, inserts into CRR, and holds open
- [x] Reader process attempts to observe behavior (documented expectation)
- [x] Test prints clear PASS/FAIL output and exits non-zero on FAIL
- [x] Cleanup uses `trap` and removes temp files on exit

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-wal-concurrency.sh
```

## Progress Log
### 2025-12-20
- Drafted from TASK-098 optional WAL concurrency bullet
- Created `zig/harness/test-wal-concurrency.sh` with 7 test cases
- Wired test into `zig/harness/test-parity.sh`
- All 10 assertions pass

## Completion Notes
### 2025-12-20

Created `zig/harness/test-wal-concurrency.sh` with comprehensive WAL mode tests:

**Test Cases Created:**
1. WAL mode setup and basic isolation - verifies `PRAGMA journal_mode=WAL` persists
2. Uncommitted changes visibility - documents SQLite WAL isolation semantics
3. Concurrent readers do not block - 3 parallel readers complete successfully
4. Writer does not block readers - interleaved read/write operations
5. CRR changes tracked correctly - clock table entries for multi-connection writes
6. db_version consistency - monotonic increase across connections
7. site_id consistency - same UUID across all connections

**Key Findings about WAL Isolation:**
- SQLite WAL provides snapshot isolation (each transaction sees consistent point-in-time)
- Readers do not block writers; writers do not block readers
- **WAL serializes writes** - only one writer at a time (parallel write attempts would deadlock)
- `PRAGMA read_uncommitted` only applies to shared-cache mode, NOT separate file connections
- For CR-SQLite: `crsql_site_id()`, `crsql_db_version()`, and clock tables work correctly under WAL

**Test Results:**
```
PASSED:  10
FAILED:  0
SKIPPED: 0
```

**Files Modified:**
- `zig/harness/test-wal-concurrency.sh` (new, 195 lines)
- `zig/harness/test-parity.sh` (added test runner block)
