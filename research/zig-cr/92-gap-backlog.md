# 92-gap-backlog

> Last updated: 2025-12-18 (new test-gap backlog)

## Status

- MVP: ✅ complete (154/154 tests passing)
- Zig implementation: `zig/`
- Canonical task queue: `.tasks/{backlog,active,done}/`

## Now (next parallel assignments)

Goal: invalidate the hypothesis that “Zig is done” by expanding cross-implementation parity coverage and adding real-system tests.

- [ ] **TASK-070** — Cover missing C suites: ext-data + sandbox → `.tasks/backlog/TASK-070-zig-parity-extdata-sandbox.md`
- [ ] **TASK-071** — Cover remaining C suites: crsqlite + is-crr → `.tasks/backlog/TASK-071-zig-parity-crsqlite-is-crr.md`
- [ ] **TASK-072** — Make `crsql_internal_sync_bit` per-connection → `.tasks/backlog/TASK-072-zig-sync-bit-per-connection.md`
- [ ] **TASK-073** — Compare Rust integration suite vs Zig harness; create missing-test tasks → `.tasks/backlog/TASK-073-compare-rust-zig-tests.md`
- [ ] **TASK-074** — Expand Zig↔Rust/C wire compat tests beyond happy path → `.tasks/backlog/TASK-074-cross-impl-compat-expanded.md`

## Context / Evidence

- C reference runner lists suites in `core/src/tests.c`:
  - `vtab`, `extdata`, `crsql`, `fract`, `is_crr`, `rows_impacted`, `rowid`, `sandbox`, `rust_integration`
- Zig harness currently emphasizes:
  - rows impacted, changes vtab filters, rowid slab, alter, noop, fract (`zig/harness/test-parity.sh`)
  - cross-impl compat exists but can SKIP if Rust/C extension not built (`zig/harness/test-cross-platform-compat.sh`)
- Rust integration suite (`core/rs/integration_check/src/t/*.rs`) covers migration/backfill/tableinfo/pack_columns/etc.

## Done (recent)

- MVP completed (all tests green) — see previous state in `research/zig-cr/92-gap-backlog.md` history

## Gaps (only what’s still open)

- Effect Bun scratchpad (blocked on Tom / TS spec-gate): `.wishes/blocked-on-tom/effect-bun-scratchpad.md`
