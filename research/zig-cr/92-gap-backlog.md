# 92-gap-backlog

> Last updated: 2025-12-22 (Gap analysis: 23 new triage tasks from skeptical review)

## Status

- **BUILD: ✅ PASSING** — compiles successfully
- **MVP: ✅ PASSING** — all core tests pass
- Oracle parity: ✅ **18/18 PASSING**
- Cross-open parity: ✅ **24/24 PASSING**
- rows_impacted: ✅ **18/18 PASSING**
- ALTER tests: ✅ **6/6 PASSING**
- Cross-platform compat: ✅ **ALL PASSING**
- Zig implementation: `zig/`
- Canonical task queue: `.tasks/{backlog,active,done}/`

## Now (next parallel assignments)

**23 NEW TRIAGE TASKS** from gap analysis (2025-12-22):

### High Priority (Cross-impl parity, data integrity)
| Task | Summary | Risk |
|------|---------|------|
| TASK-161 | Resurrection: live row via sentinel | CL semantics |
| TASK-162 | Resurrection: dead row via sentinel | CL semantics |
| TASK-163 | Resurrection: live row via column | CL semantics |
| TASK-164 | Resurrection: dead row via column | CL semantics |
| TASK-165 | Out-of-order delete/resurrect sync | Production bug |
| TASK-166 | Sentinel omission on INSERT | Wire format |
| TASK-167 | Sentinel created on DELETE | Wire format |
| TASK-169 | Sentinel NOT created on merge | Sync correctness |
| TASK-170 | FK between CRR tables | Real-world apps |
| TASK-171 | ON DELETE CASCADE between CRRs | Data integrity |
| TASK-172 | Malformed PK blob handling | Security |
| TASK-174 | Partial sync / interruption | Production |
| TASK-177 | DEFAULT value merge semantics | Schema evolution |
| TASK-179 | "Discord corrosion" 4-node scenario | Complex sync |

### Medium Priority (Robustness, edge cases)
| Task | Summary | Risk |
|------|---------|------|
| TASK-168 | Sentinel NOT on INSERT OR REPLACE | Edge case |
| TASK-173 | Schema mismatch during sync | Error handling |
| TASK-175 | Savepoints during sync | Transaction |
| TASK-176 | ATTACH database with CRRs | Multi-DB |
| TASK-180 | Site ID collision | Security |
| TASK-182 | User triggers modify other CRRs | Real-world |

### Low Priority (Performance, debug)
| Task | Summary | Risk |
|------|---------|------|
| TASK-156 | Linux CI parity | Infrastructure |
| TASK-178 | VACUUM on CRR database | Maintenance |
| TASK-181 | crsql_sha() function | Debug info |
| TASK-183 | Wide table (100 cols) performance | Performance |

## Triage Inbox Status

**23 items** in `.tasks/triage/` (see table above)

**Completed Round 61 (2025-12-21):**
- [x] TASK-148: Fix cross-platform compat failures (resurrection + text newlines) ✓
- [x] TASK-158: Optimize zeroClockOnResurrect caching ✓
- [x] TASK-160: Remove rollback_hook reset (was already fixed) ✓

**Completed Rounds 59/60 (2025-12-21):**
- [x] TASK-147: Cross-open modification interoperability ✓
- [x] TASK-157: Fix rows_impacted returning empty string ✓
- [x] TASK-159: Fix ALTER compact clock table ✓
- [x] TASK-150, 151, 152, 153, 154, 155: Marked done (superseded by above)

### Hypothesis Invalidation (Done)
- [x] **TASK-127** — Experimentally invalidate "full parity" hypothesis via fuzzing ✓ `.tasks/done/TASK-127-experimental-parity-invalidation.md`
  - Invalidation successful: Discovered empty blob (`X''`) vs `NULL` divergence
- [x] **TASK-128** — Expand parity suite with invalidation findings ✓ `.tasks/done/TASK-128-expand-parity-suite.md`
  - Created `zig/harness/test-edge-cases.sh` with 6 deterministic tests
- [x] **TASK-129** — Fix empty blob handling in Zig crsql_changes ✓ `.tasks/done/TASK-129-fix-empty-blob-parity.md`
  - Fixed `changes_vtab.zig` to return empty blob instead of NULL
  - All edge case tests pass

### Open Gaps (Parity Divergences)
- [x] **TASK-123** — Fix clock table schema parity (pk vs key, index) ✓ `.tasks/done/TASK-123-fix-clock-table-schema-parity.md`
  - Column renamed `pk` → `key`, added STRICT mode, added `_dbv_idx` index
- [x] **TASK-124** — Fix site_id preservation on cross-open ✓ `.tasks/done/TASK-124-fix-site-id-cross-open-parity.md`
  - Added `crsqlite_version|160300` to `crsql_master` on init
- [x] **TASK-125** — Fix schema_alter.zig pk→key column rename ✓ `.tasks/done/TASK-125-fix-schema-alter-pk-to-key-rename.md`
  - Updated all clock table `"pk"` references to `"key"` in schema_alter.zig
  - Added STRICT mode and _dbv_idx index to match as_crr.zig
- [x] **TASK-126** — Fix merge resolution parity with oracle ✓ `.tasks/done/TASK-126-fix-merge-resolution-parity.md`
  - Fixed site_id blob→ordinal conversion in setWinnerClock/setWinnerClockCached
  - All merge resolution tests now pass (Test 3a, 3b, ValueWin)

### Remaining Divergences (from oracle-parity test)
- ~~[ ] Merge resolution (Test 3a/3b): Remote wins / site_id tiebreaker differs — needs investigation~~
- **NONE** — All 18 oracle parity tests pass ✓

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
  - ~~**1 DIVERGENCE**: No-op UPDATE handling~~ → **FIXED by TASK-122**
  - Test: `zig/harness/test-db-version-parity.sh` = 14/14 pass ✓
- [x] **TASK-093** — rows_impacted counter timing ✓ `.tasks/done/TASK-093-rows-impacted-counter-timing.md`
  - ~~**1 DIVERGENCE**: ROLLBACK behavior~~ → **FIXED by TASK-121**
  - Test: `zig/harness/test-rows-impacted-parity.sh` = 18/18 pass ✓
- [x] **TASK-094** — ALTER TABLE history preservation ✓ `.tasks/done/TASK-094-alter-table-history-preservation.md`
  - Divergence found: ADD COLUMN clock backfill semantics (Zig eager vs Rust lazy)
  - [x] **TASK-100** — Decide ADD COLUMN clock semantics ✓ `.tasks/done/TASK-100-decide-alter-new-column-clock-semantics.md`
    - **Decision: LAZY MATERIALIZE** — Zig should NOT backfill clock entries on ADD COLUMN
    - Rationale: Clock entries represent writes, not schema changes; matches oracle; O(0) sync payload
  - [x] **TASK-101** — Implement lazy semantics in Zig ✓ `.tasks/done/TASK-101-impl-alter-add-column-no-backfill.md`
    - Removed `backfillNewColumns()` call from `crsqlCommitAlterFunc`
    - Test: `zig/harness/test-alter-parity.sh` = 19/19 pass ✓
  - [x] **TASK-102** — Fix/replace local oracle dylib (ALTER) ✓ `.tasks/done/TASK-102-fix-oracle-crsqlite-dylib-alter.md`

### Realistic Sync Tests
- [x] **TASK-119** — Fix realistic sync test failures (extra rows after merge) ✓ `.tasks/done/TASK-119-fix-realistic-sync-test-failures.md`
  - Root cause: pk vs base_rowid confusion in cached merge functions
  - Fixed: `rowExistsInBaseTableCached`, `deleteFromBaseTableCached`, `updateBaseTableColumn`
  - Tests: `test-realistic-sync.sh`, `test-realistic-offline.sh`, `test-realistic-collab.sh` all pass
- [x] **TASK-120** — Fix realistic offline test failures (consolidated into TASK-119) ✓ `.tasks/done/TASK-120-fix-realistic-offline-test-failures.md`

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

## Done (recent)

- **Round 54 (2025-12-20)**:
  - TASK-127: Experimentally invalidate parity hypothesis — found empty blob bug
  - TASK-128: Expand parity suite — added `test-edge-cases.sh` (6 tests)
  - TASK-129: Fix empty blob handling — fixed `values` serialization for zero-length blobs

- **Round 53 (2025-12-20)**:
  - TASK-125: Fix schema_alter pk→key column rename (6/6 pass)
  - TASK-126: Fix merge resolution parity (site_id ordinal conversion) (18/18 pass)

- **Round 51 (2025-12-20)**:
  - TASK-121: Fix rows_impacted ROLLBACK reset divergence (18/18 pass)
  - TASK-122: Fix no-op UPDATE db_version divergence (14/14 pass)
  - **Remaining divergences**: TASK-123 (clock schema), TASK-124 (site_id cross-open)
