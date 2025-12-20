# TASK-103: Zig WAL concurrent read/write persistence test

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Triggered by: `.tasks/active/TASK-098-zig-ondisk-db-tests.md`
- Repo guidance: `AGENTS.md` (Zig testing rule)

## Description
Current persistence tests validate WAL mode *persistence* (journal_mode=wal and data survives reopen), but do not test the optional concurrency behavior described in TASK-098:

- “WAL mode: insert in one session, read uncommitted in another (optional)”

A dedicated multi-process harness test can validate the intended semantics under WAL with two concurrent connections (writer holds transaction open; reader attempts to observe behavior).

Note: SQLite default semantics are that other connections cannot read uncommitted changes unless `PRAGMA read_uncommitted=1` is set, and even then behavior may vary. This task is to precisely define and test the intended behavior for CR-SQLite under WAL, not to assume a particular outcome.

## Files to Modify
- `zig/harness/test-persistence.sh` (add concurrency subtest) OR
- `zig/harness/test-wal-concurrency.sh` (new standalone script) and wire into `zig/harness/test-parity.sh`

## Acceptance Criteria
- [ ] Test uses a real `.sqlite` file under `.tmp/`
- [ ] Test spawns 2 separate sqlite processes (writer + reader)
- [ ] Writer process starts a transaction, inserts into CRR, and holds open
- [ ] Reader process attempts to observe behavior (documented expectation)
- [ ] Test prints clear PASS/FAIL output and exits non-zero on FAIL
- [ ] Cleanup uses `trap` and removes temp files on exit

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-wal-concurrency.sh
```

## Progress Log
### 2025-12-20
- Drafted from TASK-098 optional WAL concurrency bullet

## Completion Notes
