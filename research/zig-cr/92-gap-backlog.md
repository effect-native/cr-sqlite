# 92-gap-backlog

> Last updated: 2025-12-20 (Round 48 — TASK-088, TASK-106, TASK-107 complete)

## Status

- MVP: ✅ complete (154/154 tests passing)
- Zig implementation: `zig/`
- Canonical task queue: `.tasks/{backlog,active,done}/`

## Now (next parallel assignments)

Goal: invalidate the hypothesis that "Zig is done" by expanding cross-implementation parity coverage and adding real-system tests.

### Parity/Coverage Tasks (ready to assign)
- [x] **TASK-070** — Cover missing C suites: ext-data + sandbox ✓ `.tasks/done/TASK-070-zig-parity-extdata-sandbox.md`
  - ext-data: 15/15 tests pass (test-extdata.sh)
  - sandbox: 5/9 tests pass → TASK-117 filed for PK-only sentinel gap
- [x] **TASK-071** — Cover remaining C suites: crsqlite + is-crr ✓ `.tasks/done/TASK-071-zig-parity-crsqlite-is-crr.md`
- [x] **TASK-117** — Fix PK-only table sentinel emission ✓ `.tasks/done/TASK-117-zig-pk-only-sentinel-emission.md`

### Build/Tooling Blockers
- [x] **TASK-111** — Fix Zig 0.15 `SQLITE_TRANSIENT` alignment build error ✓ `.tasks/done/TASK-111-zig-build-sqlite-transient-alignment.md`
- [x] **TASK-072** — Make `crsql_internal_sync_bit` per-connection ✓ `.tasks/done/TASK-072-zig-sync-bit-per-connection.md`
  - Per-connection isolation implemented via ConnectionSyncBitMap
  - Test: `zig/harness/test-sync-bit-isolation.sh`
- [x] **TASK-073** — Compare Rust integration suite vs Zig harness ✓ `.tasks/done/TASK-073-compare-rust-zig-tests.md`
  - Coverage map created; spawned follow-up tasks
- [x] **TASK-074** — Expand Zig↔Rust/C wire compat tests beyond happy path ✓ `.tasks/done/TASK-074-cross-impl-compat-expanded.md`
  - New: `zig/harness/test-oracle-parity.sh` (18 tests, 15 pass / 3 divergences found)
  - Expanded `test-cross-platform-compat.sh` with edge cases (deletes, PK updates, floats, blobs, schema evolution)
  - **3 real divergences identified** (clock table naming, index structure, site_id cross-open)

### New Test Tasks (from TASK-073 coverage analysis)
- [x] **TASK-095** — Zig test for PK UPDATE semantics ✓ `.tasks/done/TASK-095-zig-test-pk-update-semantics.md`
  - Test exists and is wired into suite
  - **TASK-105** partial impl: 11/16 tests pass (integer PK complete, compound/text PK needs follow-up)
  - [x] **TASK-110** — Compound/text PK tombstone fix ✓ `.tasks/done/TASK-110-zig-pk-update-compound-text-pk.md`
- [x] **TASK-096** — Zig test for backfill verification ✓ `.tasks/done/TASK-096-zig-test-backfill-verification.md`
  - Test exists and is wired into suite
  - **TASK-078 complete**: All 12 backfill tests pass ✓
- [x] **TASK-097** — Zig ExtData lifecycle parity test ✓ `.tasks/done/TASK-097-zig-extdata-lifecycle-test.md`
  - Test: `zig/harness/test-extdata.sh`
  - 15 tests created, all pass
  - Oracle parity confirmed (no divergences)
- [x] **TASK-098** — Zig on-disk DB persistence tests ✓ `.tasks/done/TASK-098-zig-ondisk-db-tests.md`
- [x] **TASK-099** — Zig multi-connection parity test ✓ `.tasks/done/TASK-099-zig-multiconn-test.md`

### Missing-feature RGRTDD tracks (spec then impl)
- [x] **TASK-075** — Spec `crsql_automigrate` behavior ✓ `.tasks/done/TASK-075-spec-automigrate.md`
  - Test: `zig/harness/test-automigrate.sh` (17 tests, all RED until impl)
- [x] **TASK-076** — Implement `crsql_automigrate` in Zig ✓ `.tasks/done/TASK-076-impl-automigrate.md`
  - Status: `zig/harness/test-automigrate.sh` = 17/17 pass ✓ (TASK-118 fixed quoting)
- [x] **TASK-077** — Spec `crsql_as_crr` backfill behavior ✓ `.tasks/done/TASK-077-spec-as-crr-backfill.md`
- [x] **TASK-078** — Implement `crsql_as_crr` backfill in Zig ✓ `.tasks/done/TASK-078-impl-as-crr-backfill.md`
  - All 12 backfill tests pass
- [x] **TASK-079** — Spec `clset` virtual table module ✓ `.tasks/done/TASK-079-spec-clset-vtab.md`
  - Test: `zig/harness/test-clset-vtab.sh` (10 tests)
- [x] **TASK-080** — Implement `clset` module in Zig ✓ `.tasks/done/TASK-080-impl-clset-vtab.md`
  - Test: `zig/harness/test-clset-vtab.sh` = 10/10 pass ✓
- [x] **TASK-081** — Spec `crsql_unpack_columns` vtab ✓ `.tasks/done/TASK-081-spec-unpack-columns-vtab.md`
  - Test: `zig/harness/test-unpack-columns-vtab.sh` (12 tests)
- [x] **TASK-082** — Implement `crsql_unpack_columns` vtab in Zig ✓ `.tasks/done/TASK-082-impl-unpack-columns-vtab.md`
  - Test: `zig/harness/test-unpack-columns-vtab.sh` = 12/12 pass ✓
- [x] **TASK-083** — Spec table compatibility checks for `crsql_as_crr` ✓ `.tasks/done/TASK-083-spec-table-compat.md`
  - Test: `zig/harness/test-table-compat.sh` (12 tests)
- [x] **TASK-084** — Implement table compatibility checks in Zig ✓ `.tasks/done/TASK-084-impl-table-compat.md`
  - Test: `zig/harness/test-table-compat.sh` = 12/12 pass ✓
  - Validates: PK existence, UNIQUE, AUTOINCREMENT, FK, NOT NULL/DEFAULT
- [x] **TASK-085** — Spec `crsql_config_get/set` + `merge-equal-values` behavior ✓ `.tasks/done/TASK-085-spec-config.md`
  - Test: `zig/harness/test-config.sh` (12 tests)
- [x] **TASK-086** — Implement `crsql_config_get/set` in Zig ✓ `.tasks/done/TASK-086-impl-config.md`
  - Test: `zig/harness/test-config.sh` = 12/12 pass ✓
  - Supports `merge-equal-values` config with persistence to crsql_master
- [x] **TASK-087** — Spec merge atomicity for batch apply ✓ `.tasks/done/TASK-087-spec-merge-atomicity.md`
  - Test: `zig/harness/test-merge-atomicity.sh` (8 tests, all pass — Zig has native atomicity)
- [x] **TASK-088** — Verify merge atomicity ✓ `.tasks/done/TASK-088-impl-merge-atomicity.md`
  - **No implementation needed** — SQLite's native statement atomicity is sufficient
  - All 8 tests pass; hypothesis confirmed that Zig needs no explicit savepoint code

### Oracle-based parity tests (Rust/C as golden master)
- [x] **TASK-089** — API surface completeness ✓ `.tasks/done/TASK-089-api-surface-completeness.md`
  - 10 gaps found: 4 functions + 2 modules actionable, 4 internal functions excluded
  - Test: `zig/harness/test-api-surface.sh`
- [x] **TASK-090** — Trigger/clock logic equivalence ✓ `.tasks/done/TASK-090-trigger-clock-logic-equivalence.md`
  - **13 DIVERGENCES**: sentinel row timing, resurrection col_version, seq ordering
  - Test: `zig/harness/test-trigger-parity.sh`
- [x] **TASK-091** — Fract index algorithm parity ✓ `.tasks/done/TASK-091-fract-index-algorithm-parity.md`
  - **BYTE-IDENTICAL**: 12/12 tests pass
  - Test: `zig/harness/test-fract-parity.sh`
- [x] **TASK-092** — db_version advancement parity ✓ `.tasks/done/TASK-092-db-version-advancement-parity.md`
  - **1 DIVERGENCE**: No-op UPDATE handling (Rust advances, Zig doesn't)
  - 12 passed, 1 failed
  - Test: `zig/harness/test-db-version-parity.sh`
- [x] **TASK-093** — rows_impacted counter timing ✓ `.tasks/done/TASK-093-rows-impacted-counter-timing.md`
  - **1 DIVERGENCE**: ROLLBACK behavior (Rust/C does NOT reset, Zig incorrectly resets)
  - 17 passed, 1 failed
  - Test: `zig/harness/test-rows-impacted-parity.sh`
- [x] **TASK-094** — ALTER TABLE history preservation ✓ `.tasks/done/TASK-094-alter-table-history-preservation.md`
  - Divergence found: ADD COLUMN clock backfill semantics (Zig eager vs Rust lazy)
  - [ ] **TASK-100** — Decide ADD COLUMN clock semantics → `.tasks/backlog/TASK-100-decide-alter-new-column-clock-semantics.md`
  - [ ] **TASK-101** — Align Zig behavior with oracle (if chosen) → `.tasks/backlog/TASK-101-impl-alter-add-column-no-backfill.md`
  - [ ] **TASK-102** — Fix/replace local oracle dylib (ALTER) → `.tasks/backlog/TASK-102-fix-oracle-crsqlite-dylib-alter.md`

## Coverage Map Summary (TASK-073)

### Rust → Zig Coverage

| Rust Suite | Zig Coverage | Status |
|------------|--------------|--------|
| automigrate.rs | test-automigrate.sh | TASK-075 ✓ (spec), TASK-076 ✓ (impl), TASK-118 ✓ (17/17 pass) |
| backfill.rs | ✓ | TASK-096 + TASK-078 (all 12 tests pass) |
| pack_columns.rs | test-unpack-columns-vtab.sh | TASK-081 ✓ (spec), TASK-082 ✓ (impl, 12/12 pass) |
| pk_only_tables.rs | Partial | TASK-095 (test exists) |
| pk_update.rs | Partial | TASK-105 (11/16 pass; TASK-110 for compound/text PK) |
| test_db_version.rs | test-db-version-parity.sh | ✓ |
| test_cl_set_vtab.rs | test-clset-vtab.sh | TASK-079 ✓ (spec), TASK-080 ✓ (impl, 10/10 pass) |
| tableinfo.rs | ✓ | TASK-097 (15 tests, all pass) |
| teardown.rs | test-is-crr.sh | ✓ |
| fract.rs | test-fract*.sh | ✓ |
| sync_bit_honored.rs | test-sync-bit-isolation.sh | ✓ (TASK-072) |

### C → Zig Coverage

| C Suite | Zig Coverage | Status |
|---------|--------------|--------|
| rs-fract.test.c | test-fract*.sh | ✓ |
| is-crr.test.c | test-is-crr.sh | ✓ |
| rows-impacted.test.c | test-parity.sh | ✓ |
| sandbox.test.c | test-sandbox.sh | ✓ (TASK-117 fixed; 9/9) |
| changes-vtab.test.c | test-filters.sh | ✓ |
| changes-vtab-rowid.test.c | test-rowid-slab.sh | ✓ |
| crsqlite.test.c | test-e2e-sync.sh, test-alter.sh | ✓ |
| ext-data.test.c | test-extdata.sh | ✓ (15/15 tests, TASK-070) |

### Real-System Gaps (HIGH priority)

| Gap | Risk | Task |
|-----|------|------|
| All tests use `:memory:` | HIGH | TASK-098 (done) |
| No multi-connection tests | HIGH | TASK-099 (done) |
| No WAL concurrency tests | HIGH | TASK-106 ✓ (done) — `test-wal-concurrency.sh` (10/10 pass) |
| No crash/rollback tests | MEDIUM | Future |

### Policy/Documentation Tasks
- [x] **TASK-107** — Clarify sqlite-cr wrapper usage ✓ `.tasks/done/TASK-107-clarify-sqlite-cr-wrapper-for-zig-tests.md`
  - Updated `AGENTS.md` with detailed Zig testing policy
  - Audited all 39 test scripts; all compliant

## Context / Evidence

- C reference runner lists suites in `core/src/tests.c`:
  - `vtab`, `extdata`, `crsql`, `fract`, `is_crr`, `rows_impacted`, `rowid`, `sandbox`, `rust_integration`
- Zig harness currently emphasizes:
  - rows impacted, changes vtab filters, rowid slab, alter, noop, fract (`zig/harness/test-parity.sh`)
  - cross-impl compat exists but can SKIP if Rust/C extension not built (`zig/harness/test-cross-platform-compat.sh`)
- Rust integration suite (`core/rs/integration_check/src/t/*.rs`) covers migration/backfill/tableinfo/pack_columns/etc.

## Done (recent)

- **Round 48 (2025-12-20)**:
  - TASK-088: Verify merge atomicity — no impl needed, SQLite native semantics sufficient (8/8 pass)
  - TASK-106: WAL concurrency tests — new `test-wal-concurrency.sh` (10/10 pass)
  - TASK-107: Clarify sqlite-cr wrapper policy — updated `AGENTS.md`
- **Round 47 (2025-12-20)**:
  - TASK-084: Implement table compatibility checks (12/12 tests pass)
  - TASK-086: Implement config get/set API (12/12 tests pass)
  - TASK-074: Expand cross-impl compat tests (15 pass / 3 divergences found)
- **Round 46 (2025-12-20)**:
  - TASK-082: Implement unpack_columns vtab (12/12 tests pass)
  - TASK-083: Spec table compatibility checks (12 tests, 5 pass / 7 RED)
  - TASK-085: Spec config get/set API (12 tests, RED until impl)
- **Round 45 (2025-12-20)**:
  - TASK-080: Implement clset virtual table module (10/10 tests pass)
  - TASK-087: Spec merge atomicity (8 tests, all pass — native SQLite atomicity)
  - TASK-081: Spec unpack_columns vtab (12 tests, RED until impl)
- **Round 44 (2025-12-20)**:
  - TASK-118: Fixed automigrate test shell quoting (17/17 pass)
  - TASK-079: Spec clset virtual table (10 tests, RED until impl)
  - TASK-108: Fixed multiconn parity pass counting (was 9, now 6)
- **Round 42 (2025-12-20)**: 
  - TASK-078: Backfill implementation complete (12/12 tests pass)
  - TASK-097: ExtData lifecycle tests (15/15 tests pass, oracle parity confirmed)
  - TASK-105: PK UPDATE partial (11/16 tests pass — integer PK complete, compound/text PK needs TASK-110)
- TASK-073: Coverage map complete, 5 new test tasks created
- MVP completed (all tests green) — see previous state in `research/zig-cr/92-gap-backlog.md` history

## Gaps (only what's still open)

- Effect Bun scratchpad (blocked on Tom / TS spec-gate): `.wishes/blocked-on-tom/effect-bun-scratchpad.md`
