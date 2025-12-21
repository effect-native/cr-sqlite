# TASK-147 — Implement cross-open modification interoperability (Zig matches Rust/C trigger schema)

## Goal
Change the Zig implementation to match the Rust/C implementation such that a database created by one implementation can be modified by the other and vice-versa.

This is a hard requirement.

## Status
- State: active
- Priority: highest

## Problem Statement
Cross-open read-only works, but cross-open modification fails due to trigger schema incompatibility.

Today:
- Zig-created CRR triggers embed `crsql_pack_columns()` directly in trigger SQL.
- Rust/C-created CRR triggers call helper functions `crsql_after_insert/update/delete()`.

When the other implementation opens the DB and performs INSERT/UPDATE/DELETE, triggers fire and fail:
- Rust/C on Zig DB: error like `unsafe use of crsql_pack_columns`
- Zig on Rust/C DB: error like `no such function: crsql_after_*`

This breaks the interoperability requirement.

## Proposed Direction (implementation sketch)
Unify on the Rust/C trigger schema and semantics:

1. Add Zig implementations for the Rust/C trigger helper SQL functions:
   - `crsql_after_insert(table_name, pk_new...)`
   - `crsql_after_update(table_name, pk_new..., pk_old..., [non_pk_new..., non_pk_old...])`
   - `crsql_after_delete(table_name, pk_old...)`

2. Update Zig trigger generation to emit triggers that call these helpers (matching `core/rs/core/src/triggers.rs`), instead of embedding `crsql_pack_columns()` in SQL.

3. Ensure Zig can also operate correctly when opening an existing Rust/C-created DB that already has Rust-style triggers.

## Files to Modify
(Keep tight; finalize during execution.)
- `zig/src/as_crr.zig` (trigger SQL generation)
- `zig/src/ffi/init.zig` (register new SQL functions)
- New or existing Zig implementation files to host the helpers (e.g. `zig/src/local_writes/*.zig` or similar)
- `zig/harness/test-cross-open-parity.sh` (convert known-fail paths into real assertions)

## Acceptance Criteria
1. `bash zig/harness/test-cross-open-parity.sh`:
   - XO-003 PASS
   - XO-004 PASS
   - XO-006 PASS
   - `KNOWN_FAIL: 0`
   - `FAILED: 0`
   - `SKIPPED: 0`
2. Cross-open modification performs real writes and correct metadata changes:
   - base table reflects modifications
   - `crsql_db_version()` advances appropriately
   - `__crsql_clock` / `crsql_changes` reflect those writes
3. No harness uses sqlite-cr to test Zig extension behavior (must follow `AGENTS.md`).

## Parent Docs / Cross-links
- `.tasks/triage/TASK-143-cross-open-modification-compat.md` (original gap capture)
- `zig/harness/test-cross-open-parity.sh`
- `core/rs/core/src/triggers.rs` (Rust trigger schema)
- `core/rs/core/src/local_writes/after_{insert,update,delete}.rs` (semantics)

## Progress Log
- 2025-12-21: Task created from hard requirement: cross-open modification must work both directions.
- 2025-12-21: First attempt by subagent failed — changed pks table schema AND trigger SQL but left backfill using old schema, causing "failed to backfill existing rows" error. Changes stashed and reverted.
- 2025-12-21: **Remains in active** — needs more careful incremental approach.
- 2025-12-21: **Phase 1 progress** (schema migration):
  - ✅ Fixed compound PK bug in getOrCreatePkKey (commit 255e316e) - dangling pointer fix
  - ✅ Refactored findPkFromBlob for new schema (commit 3b9a984d) - unpacks pk_blob, queries individual PK columns
  - ✅ Made getTableInfo public in as_crr.zig for reuse
  - ✅ Cross-open tests: 24/24 PASSING (direct table modifications work)
  - ❌ Sync operations: FAILING (need merge_insert.zig refactoring)
  - Created 7 triage tasks (TASK-149 through TASK-155) for remaining work
- 2025-12-21: TASK-149 marked "done" but left build broken with 4 compilation errors
- 2025-12-21: **BUILD IS BROKEN** — Must fix before any testing:
  1. `changes_vtab.zig:1707` — unused `base_rowid` variable
  2. `changes_vtab.zig:1539` — `TableMergeStmts.init()` doesn't return error (bad `catch`)
  3. `changes_vtab.zig:1721` — optional pointer not unwrapped
  4. `merge_insert.zig:89` — `api.clear_bindings` doesn't exist

## Implementation Notes (from failed attempt)
The first approach tried to:
1. Change pks table from `(pk, base_rowid, pks BLOB)` to `(__crsql_key, pk_col1, pk_col2, ...)` (Rust/C schema)
2. Add `crsql_after_insert/update/delete` SQL functions
3. Change trigger generation

This failed because:
- The schema change touched too many functions simultaneously (backfill, triggers, changes_vtab, merge)
- The pks table schema is deeply embedded in the codebase
- Need incremental approach: first add functions, then change triggers, then verify

## Recommended Approach (incremental)
1. **Phase 1**: Add `crsql_after_insert/update/delete` functions that work with CURRENT pks schema
   - These functions should do what the current inline trigger SQL does
   - Register them in init.zig
   - Verify existing tests still pass

2. **Phase 2**: Change trigger generation to call these functions
   - No schema changes yet
   - Triggers now call helper functions instead of embedding pack_columns
   - Verify existing tests still pass

3. **Phase 3**: Test cross-open with current schema
   - Zig can now open Rust/C DBs (has crsql_after_* functions)
   - But Rust/C still can't open Zig DBs (triggers still use pack_columns)
   
4. **Phase 4**: Align pks schema if needed for full bidirectional support

## Completion Notes
(Empty until done.)
