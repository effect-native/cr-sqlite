# TASK-147 — Implement cross-open modification interoperability (Zig matches Rust/C trigger schema)

## Goal
Change the Zig implementation to match the Rust/C implementation such that a database created by one implementation can be modified by the other and vice-versa.

This is a hard requirement.

## Status
- State: triage
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

## Completion Notes
(Empty until done.)
