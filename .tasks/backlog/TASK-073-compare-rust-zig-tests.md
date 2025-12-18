# TASK-073: Compare Rust integration suite vs Zig harness; create missing-test tasks

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

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
- Zig harness: `zig/harness/`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The repo contains *multiple* test surfaces:
- C test suites (`core/src/*.test.c`)
- Rust integration suite (`core/rs/integration_check/src/t/*.rs`)
- Zig parity/unit/realistic harness (`zig/harness/*`, `zig/test/*.zig`)

To invalidate the hypothesis that the Zig implementation is done, we need a *coverage map* that answers:
- Which Rust/C behaviors are not exercised by Zig tests?
- Which Zig behaviors aren’t cross-checked against Rust/C? (risk of Zig-specific blindspots)

This task builds that map and then produces follow-up task cards for each gap.

## Files to Modify
- `.tasks/backlog/TASK-073-compare-rust-zig-tests.md`
- `research/zig-cr/92-gap-backlog.md`
- `.tasks/backlog/TASK-*.md` (new follow-up tasks created by this task)

## Acceptance Criteria
- [ ] A table exists in this task card mapping:
  - Rust integration suite → equivalent Zig test(s) (or "missing")
  - C suite → equivalent Zig test(s) (or "missing")
- [ ] For each "missing" row: a new `.tasks/backlog/TASK-*.md` exists, with tight `Files to Modify` and a reproducible command.
- [ ] Gaps are framed from a real-system POV (migrations, multi-conn, on-disk DBs, crash/rollback).

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".

## Completion Notes
