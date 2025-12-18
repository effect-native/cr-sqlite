# 92-gap-backlog

> Last updated: 2025-12-18 (added oracle-based parity tests TASK-089 through TASK-094)

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

Missing-feature RGRTDD tracks (spec then impl):
- [ ] **TASK-075** — Spec `crsql_automigrate` behavior → `.tasks/backlog/TASK-075-spec-automigrate.md`
- [ ] **TASK-076** — Implement `crsql_automigrate` in Zig → `.tasks/backlog/TASK-076-impl-automigrate.md`
- [ ] **TASK-077** — Spec `crsql_as_crr` backfill behavior → `.tasks/backlog/TASK-077-spec-as-crr-backfill.md`
- [ ] **TASK-078** — Implement `crsql_as_crr` backfill in Zig → `.tasks/backlog/TASK-078-impl-as-crr-backfill.md`
- [ ] **TASK-079** — Spec `clset` virtual table module → `.tasks/backlog/TASK-079-spec-clset-vtab.md`
- [ ] **TASK-080** — Implement `clset` module in Zig → `.tasks/backlog/TASK-080-impl-clset-vtab.md`
- [ ] **TASK-081** — Spec `crsql_unpack_columns` vtab → `.tasks/backlog/TASK-081-spec-unpack-columns-vtab.md`
- [ ] **TASK-082** — Implement `crsql_unpack_columns` vtab in Zig → `.tasks/backlog/TASK-082-impl-unpack-columns-vtab.md`
- [ ] **TASK-083** — Spec table compatibility checks for `crsql_as_crr` → `.tasks/backlog/TASK-083-spec-table-compat.md`
- [ ] **TASK-084** — Implement table compatibility checks in Zig → `.tasks/backlog/TASK-084-impl-table-compat.md`
- [ ] **TASK-085** — Spec `crsql_config_get/set` + `merge-equal-values` behavior → `.tasks/backlog/TASK-085-spec-config.md`
- [ ] **TASK-086** — Implement `crsql_config_get/set` in Zig → `.tasks/backlog/TASK-086-impl-config.md`
- [ ] **TASK-087** — Spec merge atomicity for batch apply → `.tasks/backlog/TASK-087-spec-merge-atomicity.md`
- [ ] **TASK-088** — Implement savepoint-backed merge atomicity → `.tasks/backlog/TASK-088-impl-merge-atomicity.md`

Oracle-based parity tests (Rust/C as golden master):
- [ ] **TASK-089** — API surface completeness: pragma_function_list/module_list comparison → `.tasks/backlog/TASK-089-api-surface-completeness.md`
- [ ] **TASK-090** — Trigger/clock logic equivalence: col_version/db_version/seq match → `.tasks/backlog/TASK-090-trigger-clock-logic-equivalence.md`
- [ ] **TASK-091** — Fract index algorithm parity: crsql_fract_key_between output match → `.tasks/backlog/TASK-091-fract-index-algorithm-parity.md`
- [ ] **TASK-092** — db_version advancement parity: version increments at same moments → `.tasks/backlog/TASK-092-db-version-advancement-parity.md`
- [ ] **TASK-093** — rows_impacted counter timing: reset timing match → `.tasks/backlog/TASK-093-rows-impacted-counter-timing.md`
- [ ] **TASK-094** — ALTER TABLE history preservation: clock history + backfill match → `.tasks/backlog/TASK-094-alter-table-history-preservation.md`

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
