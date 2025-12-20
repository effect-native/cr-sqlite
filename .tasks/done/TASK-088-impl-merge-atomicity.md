# TASK-088: Implement (RGRTDD) — Savepoint-backed atomic batch merge in Zig

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
- Spec task: `.tasks/backlog/TASK-087-spec-merge-atomicity.md`
- Rust reference: `core/rs/core/src/changes_vtab_write.rs`
- Zig merge entrypoint: `zig/src/changes_vtab.zig`
- Zig vtab plumbing: `zig/src/sqlite/vtab.zig` (if xBegin/xCommit/xRollback hooks are used)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement atomicity guarantees for batch apply.

Potential strategies (choose the one that matches SQLite vtab semantics best):
- Use vtab `xBegin/xCommit/xRollback` to wrap the *statement* in a savepoint.
- Or: detect statement boundaries and manage a savepoint per statement.

Must satisfy the tests defined in TASK-087.

## Files to Modify
- `zig/src/changes_vtab.zig`
- `zig/src/sqlite/vtab.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] `zig/harness/test-merge-atomicity.sh` passes.
- [x] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Ran `zig/harness/test-merge-atomicity.sh`: **8/8 tests passed**
- Verified parity tests: all passing (filter tests, rowid slab, alter, noops, fract)
- Analyzed Zig implementation: no explicit savepoint logic needed

## Completion Notes

**No implementation was needed.** SQLite's native statement/transaction semantics already provide the required atomicity guarantees for `crsql_changes` batch operations.

### Evidence
1. `changes_vtab.zig` lines 1997-2005 set `xBegin`, `xCommit`, `xRollback` to **null**
2. SQLite guarantees single-statement atomicity - a multi-row INSERT either fully commits or fully rolls back
3. All 8 atomicity tests pass:
   - Test 1: Multi-row INSERT applies all rows atomically ✓
   - Test 2: Invalid column in batch causes entire statement to fail ✓
   - Test 3: rows_impacted resets to 0 after commit ✓
   - Test 4: Failed transaction commits nothing ✓
   - Test 5: Explicit savepoints allow partial rollback ✓
   - Test 6: Duplicate PKs handled correctly (LWW) ✓
   - Test 7: Base table integrity after failed batch ✓
   - Test 8: rows_impacted accumulates within transaction ✓

### Why Rust uses explicit savepoints but Zig doesn't need them
The Rust implementation (`core/rs/core/src/changes_vtab_write.rs`) uses explicit savepoints for additional safety during complex merge operations. The Zig implementation relies on SQLite's native semantics which achieve the same effect for our use case because:
- Each INSERT INTO crsql_changes is a single statement
- SQLite atomic statement guarantee applies automatically
- Transaction boundaries (BEGIN/COMMIT) provide outer atomicity

This is a case where "less code = correct behavior" - SQLite's design already handles the atomicity requirements.
