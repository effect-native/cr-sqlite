# TASK-073: Compare Rust integration suite vs Zig harness; create missing-test tasks

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
agent

## Parent Docs / Cross-links
- Rust integration suite entrypoint: `core/rs/integration_check/src/lib.rs`
- Rust integration suites:
  - `core/rs/integration_check/src/t/automigrate.rs`
  - `core/rs/integration_check/src/t/backfill.rs`
  - `core/rs/integration_check/src/t/pack_columns.rs`
  - `core/rs/integration_check/src/t/pk_only_tables.rs`
  - `core/rs/integration_check/src/t/pk_update.rs`
  - `core/rs/integration_check/src/t/test_db_version.rs`
  - `core/rs/integration_check/src/t/test_cl_set_vtab.rs`
  - `core/rs/integration_check/src/t/tableinfo.rs`
  - `core/rs/integration_check/src/t/teardown.rs`
  - `core/rs/integration_check/src/t/fract.rs`
  - `core/rs/integration_check/src/t/sync_bit_honored.rs`
- Zig harness: `zig/harness/`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The repo contains *multiple* test surfaces:
- C test suites (`core/src/*.test.c`)
- Rust integration suite (`core/rs/integration_check/src/t/*.rs`)
- Zig parity/unit/realistic harness (`zig/harness/*`, `zig/test/*.zig`)

To invalidate the hypothesis that the Zig implementation is done, we need a *coverage map* that answers:
- Which Rust/C behaviors are not exercised by Zig tests?
- Which Zig behaviors aren't cross-checked against Rust/C? (risk of Zig-specific blindspots)

This task builds that map and then produces follow-up task cards for each gap.

## Files to Modify
- `.tasks/active/TASK-073-compare-rust-zig-tests.md` (this file)
- `research/zig-cr/92-gap-backlog.md`
- `.tasks/backlog/TASK-*.md` (new follow-up tasks created by this task)

## Acceptance Criteria
- [x] A table exists in this task card mapping:
  - Rust integration suite → equivalent Zig test(s) (or "missing")
  - C suite → equivalent Zig test(s) (or "missing")
- [x] For each "missing" row: a new `.tasks/backlog/TASK-*.md` exists, with tight `Files to Modify` and a reproducible command.
- [x] Gaps are framed from a real-system POV (migrations, multi-conn, on-disk DBs, crash/rollback).

---

## Coverage Map

### Rust Integration Suite → Zig Tests

| Rust Suite | Behavior Tested | Zig Equivalent | Status |
|------------|-----------------|----------------|--------|
| `automigrate.rs` | `crsql_automigrate()` - schema evolution, idempotency, table/column/index add/remove/rename | **MISSING** | Blocked on TASK-075/076 |
| `backfill.rs` | `crsql_as_crr()` backfills existing data with clock entries | Partial: `test-parity.sh` creates CRRs but no backfill verification | **GAP** |
| `pack_columns.rs` | `crsql_pack_columns()` / `crsql_unpack_columns` binary encoding | **MISSING** | Blocked on TASK-081/082 |
| `pk_only_tables.rs` | Tables with only PK columns, junction tables, pk-only sync | `test-trigger-parity.sh`, `test-e2e-sync.sh` | **COVERED** (partial) |
| `pk_update.rs` | UPDATE of primary key columns (delete + create semantics) | **MISSING** | New task needed |
| `test_db_version.rs` | `fetch_db_version_from_storage`, `next_db_version` | `test-db-version-parity.sh` | **COVERED** |
| `test_cl_set_vtab.rs` | `CLSet` virtual table module for CRR creation | **MISSING** | Blocked on TASK-079/080 |
| `tableinfo.rs` | `is_table_compatible`, `pull_table_info`, clock table creation | **MISSING** | Blocked on TASK-083/084 |
| `teardown.rs` | `crsql_as_table()` removes CRR scaffolding | `test-is-crr.sh` (implicit via DestroyedCrrIsNotCrr) | **COVERED** |
| `fract.rs` | `crsql_fract_as_ordered()` basic operations | `test-fract.sh`, `test-fract-parity.sh` | **COVERED** |
| `sync_bit_honored.rs` | `crsql_internal_sync_bit(1)` suppresses clock writes | **MISSING** | Blocked on TASK-072 |

### C Test Suites → Zig Tests

| C Suite | Behavior Tested | Zig Equivalent | Status |
|---------|-----------------|----------------|--------|
| `rs-fract.test.c` | Fractional indexing operations, prepend/append/insert | `test-fract.sh`, `test-fract-parity.sh` | **COVERED** |
| `is-crr.test.c` | `crsql_is_crr()` function | `test-is-crr.sh` | **COVERED** |
| `rows-impacted.test.c` | `crsql_rows_impacted()` counter, reset on commit | `test-parity.sh` (rows_impacted suite) | **COVERED** |
| `sandbox.test.c` | Basic sync between two DBs | `test-e2e-sync.sh`, `test-cross-platform-compat.sh` | **COVERED** |
| `changes-vtab.test.c` | Compound PK encoding, filter pushdown | `test-parity.sh`, `test-filters.sh` | **COVERED** |
| `changes-vtab-rowid.test.c` | Rowid slab allocation for vtab | `test-rowid-slab.sh` | **COVERED** |
| `crsqlite.test.c` | e2e sync, alter column, Lamport clock, no-ops | `test-e2e-sync.sh`, `test-alter.sh`, `test-noops.sh` | **COVERED** |
| `ext-data.test.c` | ExtData lifecycle, pragma version tracking | **MISSING** | New task needed |

### Missing Coverage Summary

1. **`crsql_automigrate`** - No Zig tests (blocked on spec/impl TASK-075/076)
2. **`crsql_as_crr` backfill verification** - Zig creates CRRs but doesn't verify clock table correctness for pre-existing data
3. **`crsql_pack_columns` / `crsql_unpack_columns`** - No Zig tests (blocked on TASK-081/082)
4. **PK UPDATE semantics** - Updating PK columns (delete+create) not tested in Zig
5. **`CLSet` vtab module** - No Zig tests (blocked on TASK-079/080)
6. **`is_table_compatible` checks** - No Zig tests (blocked on TASK-083/084)
7. **`crsql_internal_sync_bit`** - No Zig tests (blocked on TASK-072)
8. **ExtData lifecycle** - Schema version tracking, data version changes not tested
9. **Multi-connection scenarios** - Rust `tableinfo.rs::test_leak_condition` uses 2 connections on same file; Zig harness only tests :memory:

### Real-System Gap Analysis

| Gap Category | What's Missing | Risk Level |
|--------------|----------------|------------|
| **On-disk DBs** | All Zig harness tests use `:memory:` - no persistence testing | HIGH |
| **Multi-connection** | No tests for concurrent connections to same file | HIGH |
| **Crash/rollback** | No tests for transaction rollback, WAL recovery | MEDIUM |
| **Schema migrations** | No automigrate tests | HIGH (blocked) |
| **Large datasets** | `test-large-data.sh` exists but basic | MEDIUM |
| **Concurrent merges** | `test-merge-stress.sh` exists but basic | MEDIUM |

---

## New Task Cards Created

### TASK-095: Zig test for PK UPDATE semantics
Tests UPDATE of primary key columns generates delete + create events.

### TASK-096: Zig test for backfill verification
Verify `crsql_as_crr()` correctly backfills clock tables for pre-existing data.

### TASK-097: Zig ExtData lifecycle parity test
Test schema version tracking, data version pragma changes across connections.

### TASK-098: Zig on-disk DB persistence tests
Convert key harness tests to use on-disk databases instead of :memory:.

### TASK-099: Zig multi-connection parity test
Test concurrent connections to same database file (mirrors tableinfo.rs::test_leak_condition).

---

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".
- Completed coverage map analysis
- Identified 9 major gaps between Rust/C and Zig test coverage
- Created 5 new task cards for missing tests not blocked on features

## Completion Notes
**Completed: 2025-12-18**

Coverage map complete. Key findings:
- 6 Rust behaviors are blocked pending feature implementation (automigrate, pack_columns, CLSet, tableinfo, sync_bit)
- 5 new actionable test tasks created (TASK-095 through TASK-099)
- Critical real-system gaps: on-disk DBs, multi-connection, crash recovery

New tasks created:
- TASK-095: PK UPDATE semantics test
- TASK-096: Backfill verification test
- TASK-097: ExtData lifecycle parity test
- TASK-098: On-disk DB persistence tests (HIGH priority)
- TASK-099: Multi-connection parity test (HIGH priority)
