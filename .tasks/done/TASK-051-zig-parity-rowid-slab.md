# TASK-051: Zig parity — Fix crsql_changes multi-table rowid slab

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Delegate evidence: `.tasks/DELEGATE_WORK_HANDOFF.md` (Round 33)
- Parity harness: `zig/harness/test-parity.sh`
- Rowid slab harness: `zig/harness/test-rowid-slab.sh`
- Implementation: `zig/src/changes_vtab.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
`make -C zig test-parity` currently fails 4 assertions in the “rowid slab” suite.

Symptom (from Round 33): `crsql_changes` only emits rowids for the first CRR table; expected slab rowids for subsequent tables are missing.

This task fixes the `crsql_changes` vtab enumeration so multi-table iteration produces the expected slabbed `_rowid_` ordering.

## Files to Modify
- `zig/src/changes_vtab.zig`
- `zig/harness/test-rowid-slab.sh` (only if the test is wrong)
- `zig/harness/test-parity.sh` (only if wiring is wrong)

## Acceptance Criteria
- [x] `zig/harness/test-rowid-slab.sh` passes.
- [x] `make -C zig test-parity` passes.
- [x] Root cause is documented in task `Completion Notes` with the specific bug mechanism.
- [x] The fix is covered by at least one deterministic regression assertion (either the existing harness or a new Zig unit test in `zig/src/changes_vtab.zig`).

## Progress Log
### 2025-12-15
- Task created from Round 33 parity failures.
- Delegated to subagent (Round 34).
- **FIXED**: Root cause identified and patched in `zig/src/changes_vtab.zig`.

## Completion Notes
### 2025-12-15 — Round 34

**Root Cause**: The `crsql_changes` virtual table's schema-version keyed cache was not being properly invalidated when new CRR tables were created. In `changesFilter()`, `getSchemaVersion()` returned the **cached** schema version without checking if SQLite's `PRAGMA schema_version` had changed.

**Bug Mechanism**:
1. First query to `crsql_changes` (with only table `foo`) discovers and caches the table list
2. User creates tables `bar` and `baz` (schema version increments in SQLite)
3. Second query to `crsql_changes` still uses the stale cached table list (only `foo`)
4. Result: Only 2 rows returned instead of 6 (missing slab rowids for subsequent tables)

**Fix**: In `zig/src/changes_vtab.zig` (line 913-918), added a call to `cache.checkSchemaVersion()` **before** checking the cache validity. This ensures the schema version is refreshed from the database before we check if the cached table list is still valid.

**Test Output**:
```
=== Zig CR-SQLite Rowid Slab Tests ===
PASS: First table, first rowid = 1
PASS: First table, second rowid = 2
PASS: rowid[0] = 1
PASS: rowid[1] = 2
PASS: rowid[2] = 10000000000001
PASS: rowid[3] = 10000000000002
PASS: rowid[4] = 20000000000001
PASS: rowid[5] = 20000000000002

=== All rowid slab tests PASSED ===

Full parity suite: PASSED: 52, FAILED: 0, SKIPPED: 0
```
