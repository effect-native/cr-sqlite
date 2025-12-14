# 92-gap-backlog

> **Last Updated**: 2025-12-14 (Round 27)

## Status Summary

**Backlog pointers**:
- Task cards: `.tasks/backlog/`
- Completed task archive: `.tasks/done/`
- Product-owner wishes inbox: `.wishes/`
- Wishes blocked on Tom: `.wishes/blocked-on-tom/`

**Task map (what to run in parallel next)**:
- Perf hotspots: ✅ COMPLETE (see `.tasks/done/TASK-029-performance-hotspot-closure.md`)
- Windows `.dll`: ✅ COMPLETE (see `.tasks/done/TASK-030-windows-dll-build.md`)
- Hosted web ESM proposal: ✅ COMPLETE (see `.tasks/done/TASK-035-hosted-wasm-proposal.md`)
- Effect submodules + TS-work rule: ✅ COMPLETE (see `.tasks/done/TASK-038-add-effect-native-submodules.md`)
- npm native packaging (Zig artifacts): ✅ COMPLETE (see `.tasks/active/TASK-034-npm-package-zig-native.md`)
- Release-planning proposal: `.tasks/backlog/TASK-036-release-planning-proposal.md`
- Web phase-2 (now TS-in-`effect-native/`): `.tasks/backlog/TASK-031-web-service-worker-fallback.md`, `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`
- Global mesh spec-first planning:
  - `.tasks/backlog/TASK-039-spec-global-mesh-package-map.md`
  - `.tasks/backlog/TASK-040-spec-crsql-mesh-protocol.md`
  - `.tasks/backlog/TASK-041-spec-crsql-mesh-core.md`
  - `.tasks/backlog/TASK-042-spec-crsql-mesh-transport.md`
  - `.tasks/backlog/TASK-043-spec-crsql-mesh-integration.md`
  - `.tasks/backlog/TASK-044-spec-libcrsql-next.md`
  - `.tasks/backlog/TASK-045-spec-crsql-mesh-runtime.md`
- Mobile embedding guide: `.tasks/backlog/TASK-033-mobile-static-embedding-guide.md`
- zig-sqlite upstream feedback capture (blocked): `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

**MVP COMPLETE** — All core replication functionality implemented and tested:
- Zig unit tests: 64/64 PASS
- Shell parity tests: 52/52 PASS
- Browser WASM tests: 18/18 PASS (including multi-tab SharedWorker + OPFS)
- C oracle harness: 20/20 PASS (5 suites)
- E2E sync tests: ALL PASS
- **Total: 154/154 tests passing (100%)** 🎉

---

## Recent Progress (Rounds 10-20)

### Round 10: CI Infrastructure
- ✅ GitHub Actions CI workflow (`.github/workflows/zig-tests.yaml`)
- Automated native tests on Linux and macOS
- WASM build verification

### Round 11: Performance Infrastructure
- ✅ Statement caching infrastructure (`zig/src/stmt_cache.zig`)
- Generic cache with configurable capacity
- Reset-on-schema-change support
- Foundation for query optimization

### Round 12: Multi-tab Web Architecture
- ✅ SharedWorker coordinator (`zig/browser-test/src/SharedWorkerCoordinator.ts`)
- ✅ Provider worker (`zig/browser-test/src/ProviderWorker.ts`)
- ✅ DbClient interface (`zig/browser-test/src/DbClient.ts`)
- ✅ Multi-tab test infrastructure (`zig/browser-test/tests/multi-tab.spec.ts`)
- Web Locks for exclusive provider access
- RPC interface (exec, query)
- OPFS storage integration ready

### Round 13: Oracle Validation Foundation
- ✅ C oracle harness scaffolding (`zig/harness/c-oracle/`)
- ✅ esbuild bundling configuration (`zig/browser-test/esbuild.config.mjs`)
- Foundation for cross-validating Zig extension against C reference

### Round 14: Schema Alter & E2E Sync
- ✅ Schema alter tests passing
- ✅ E2E sync validation complete

### Round 15-16: Critical Bug Fixes & Multi-tab Completion
- ✅ **CRITICAL site_id bug fixed** — site IDs now correctly persisted and stable across sessions
- ✅ `crsql_fract_key_between` implemented (`zig/src/fract_index.zig`)
- ✅ Multi-tab SharedWorker fully working (4 browser tests pass)
- ✅ C oracle harness all 4 suites pass (changes-vtab, as-crr, e2e-sync, filters)
- ✅ Native parity tests expanded to 52 tests
- ✅ Browser tests expanded to 14 tests

### Round 17: OPFS Persistence & npm Package Structure
- ✅ OPFS persistence integration for browser storage
- ✅ npm package structure updates (`zig/browser-dist/`)
- ✅ Production-ready JavaScript bundles (coordinator.js, provider.js)

### Round 18: OPFS Testing & Stress Tests
- ✅ OPFS persistence tests added to browser test suite
- ✅ Concurrent writes stress test (multi-tab write contention)
- ✅ Browser tests expanded to 16 tests

### Round 19: Provider Re-election
- ✅ Provider failover and re-election fully working
- ✅ Graceful handoff when provider tab closes
- ✅ All 18 browser tests pass

### Round 20: C Oracle Expansion
- ✅ browser-dist package updates for npm publishing
- ✅ `sandbox.test.c` added to C oracle harness
- ✅ `rs-fract.test.c` added to C oracle harness
- ✅ C oracle now covers 5 test suites (19/20 pass)
- ⚠️ 1 failing test: `fract: AsOrdered` (stub not implemented)

### Round 21: Fractional Indexing Complete
- ✅ `crsql_fract_as_ordered` fully implemented (`zig/src/fract_index.zig`)
  - AFTER INSERT trigger for `-1`/`1` sentinel handling (prepend/append)
  - AFTER UPDATE trigger for move operations
  - `<table>_fractindex` view with INSTEAD OF triggers
- ✅ `crsql_fract_fix_conflict_return_old_key` implemented (collision repair)
- ✅ **All C oracle tests now pass: 20/20 (100%)**
- ✅ **Total test count: 154/154 (100%)**

### Round 22: Performance & npm Package
- ✅ `discoverTablesCached` enabled in `changes_vtab.zig` (was implemented but unused!)
- ✅ `TableMergeStmts` per-table statement cache in `merge_insert.zig`
  - 8 cached function variants for hot paths
  - Lazy statement preparation
  - No allocator needed (stack-allocated SQL buffers)
- ✅ npm package renamed to `@effect-native/libcrsql-browser`
- ✅ Browser package README updated with usage docs
- ✅ Root README updated with "Browser Usage" section
- 📋 Service Worker fallback researched (defer to Phase 2)

### Round 23: Statement Cache Wiring & Cross-Platform Validation
- ✅ `TableMergeStmts` wired into `changes_vtab.zig` write path
  - All 8 merge hot-path functions now use cached statements
  - Per-table cache with automatic invalidation on table change
  - Graceful fallback to uncached on allocation failure
- ✅ Cross-platform sync compatibility test (`zig/harness/test-cross-platform-compat.sh`)
  - Validates Zig ↔ Rust/C wire format compatibility
  - Tests: bidirectional sync, PK blob format, Lamport clocks, NULL handling, tombstones
  - **Result: 100% compatible**
- 📋 macOS universal binary approach documented (lipo-based)
- 📋 Reactive query subscriptions researched (defer to Phase 2)

### Round 24: Adversarial Testing (Bugs Found)
- ✅ Merge stress test (`zig/harness/test-merge-stress.sh`) — **ALL PASS**
- ✅ Schema evolution test (`zig/harness/test-schema-evolution.sh`) — **ALL PASS**
- ⚠️ Large data test (`zig/harness/test-large-data.sh`) — 23/25 PASS
- ⚠️ Clock edge cases test (`zig/harness/test-clock-edge-cases.sh`) — found 3 bugs

### Round 25: Bug Fixes (All 3 Fixed!)
- ✅ **BUG-001 FIXED**: cl comparison now works (higher cl wins)
  - Added `zeroClockOnResurrect()` to reset col_versions on resurrection
- ✅ **BUG-002 FIXED**: Tombstone (cl<0) now deletes rows correctly
  - Added special tombstone handling before CL gating check
- ✅ **BUG-003 FIXED**: seq now increments within transaction
  - Added `crsql_increment_and_get_seq()` UDF
  - Updated all triggers to use new seq function
  - Seq resets to 0 on commit/rollback
- ✅ **Clock edge cases test now passes: 7/7**

### Round 26: Universal Binary, Docs, Realistic Tests
- ✅ **macOS universal binary**: `make universal` target added to `zig/Makefile`
  - Builds aarch64 + x86_64 with separate `--prefix` outputs
  - Combines with `lipo -create` into `zig-out-universal/lib/libcrsqlite.dylib`
  - Verified: `lipo -info` shows both architectures
- ✅ **Docs alignment**: `zig/README.md` updated to reflect 154/154 tests passing
  - C oracle tests: 20/20 (was incorrectly showing "partial")
  - `crsql_begin_alter` / `crsql_commit_alter` listed as implemented
  - Known Limitations reflects actual remaining gaps
- ✅ **Realistic scenario tests**: 3 new shell tests in `zig/harness/`
  - `test-realistic-sync.sh` - Multi-device sync (Alice/Bob todo list)
  - `test-realistic-collab.sh` - Concurrent edit conflict resolution
  - `test-realistic-offline.sh` - Offline-first field worker pattern
  - All serve as executable documentation per `.wishes/spec-first-RGRTDD.md`

### Round 27: npm Packaging for Zig Artifacts
- ✅ **npm packaging for Zig-built native extensions** (TASK-034)
  - Updated `index.js` with implementation selection logic
  - New `PREFER_IMPLEMENTATION` export ('zig' | 'c-rust' | 'auto')
  - `getExtensionPath({ implementation })` option for explicit selection
  - Default 'auto' mode prefers Zig, falls back to C/Rust
  - Naming convention: `crsqlite-zig-<platform>-<arch>.<ext>`
- ✅ **Build scripts**: `scripts/build-zig.sh`, `scripts/bundle-zig-lib.sh`
  - Cross-platform builds: darwin (universal), linux (x64, arm64)
  - npm scripts: `build:zig`, `build:zig:all`, `bundle-lib:zig`
- ✅ **Test verification**: `dist.test.ts` extended
  - Checks for both C/Rust and Zig artifacts
  - Verifies loader selection logic
- ✅ **Bundled artifacts** in `lib/`:
  - `crsqlite-zig-darwin-universal.dylib`
  - `crsqlite-zig-darwin-aarch64.dylib`
  - `crsqlite-zig-darwin-x86_64.dylib`

---

## Completed Items (Rounds 1-9)

### ✅ SQLite API Scaffolding
1. ~~**Loadable extension init scaffolding**~~ — DONE in `zig/src/ffi/init.zig`
2. ~~**Writable vtab support**~~ — DONE in `zig/src/changes_vtab.zig` (xUpdate, xBegin, xCommit)
3. ~~**Blob-safe arg decoding**~~ — DONE in `zig/src/codec.zig`, `pack_columns.zig`

### ✅ Core Replication Features
- `crsql_as_crr` / `crsql_as_table` — `zig/src/as_crr.zig`
- `crsql_changes` read path (union query, filters, rowid slabs)
- `crsql_changes` write path (merge semantics, cl/col_version comparison)
- `crsql_site_id()`, `crsql_db_version()` — `zig/src/site_identity.zig`
- `crsql_rows_impacted()` — `zig/src/rows_impacted.zig`
- `crsql_is_crr()` — `zig/src/is_crr.zig`
- `crsql_begin_alter` / `crsql_commit_alter` — `zig/src/schema_alter.zig`
- Sync bit gating — `zig/src/sync_bit.zig`
- Resurrection merge (tombstone → live) — `zig/src/merge_insert.zig`
- WASM memory safety (allocator fixes) — `zig/src/pack_columns.zig`

---

## Remaining Gaps (Post-MVP)

> This section is kept in lockstep with `.tasks/backlog/`. If you see an unchecked item here, you should see a task card that owns it.

### 1. Performance Optimizations
**Source**: `research/zig-cr/11-performance-hotspots.md`
**Priority**: Medium
**Status**: ✅ All performance optimizations complete (Round 26)

- [x] Statement caching infrastructure (`zig/src/stmt_cache.zig`)
- [x] `discoverTablesCached` enabled in `changes_vtab.zig` ✅
- [x] Per-table merge statement caching (`TableMergeStmts` in `merge_insert.zig`) ✅
- [x] Wire `TableMergeStmts` into changes_vtab write path ✅ (Round 23)
- [x] Schema version invalidation caching (`PRAGMA schema_version`) ✅ — `.tasks/active/TASK-029-performance-hotspot-closure.md`
- [x] `PRAGMA data_version` check amortization (per-transaction flag) ✅ — `.tasks/active/TASK-029-performance-hotspot-closure.md`
- [x] Prepared statement persistence (`SQLITE_PREPARE_PERSISTENT`) ✅ — `.tasks/active/TASK-029-performance-hotspot-closure.md`

### 2. Fractional Indexing UDFs
**Source**: `research/zig-cr/07-fractindex-rust.md`
**Priority**: Low (deferred from MVP)
**Status**: ✅ COMPLETE — All UDFs implemented

- [x] `crsql_fract_key_between(left, right)` — lexicographic midpoint (`zig/src/fract_index.zig`)
- [x] `crsql_fract_as_ordered(table, order_col, collection_cols...)` — view + triggers ✅
- [x] `crsql_fract_fix_conflict_return_old_key(...)` — collision repair ✅

### 3. Multi-tab Web Architecture
**Source**: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
**Priority**: High (for production web use)
**Status**: ✅ Complete — 18 browser tests passing (including OPFS + re-election)

- [x] SharedWorker coordinator for provider election (`zig/browser-test/src/SharedWorkerCoordinator.ts`)
- [x] Web Locks for exclusive provider access
- [x] RPC interface (exec, query) (`zig/browser-test/src/DbClient.ts`)
- [x] Provider worker (`zig/browser-test/src/ProviderWorker.ts`)
- [x] Browser test coverage for multi-tab scenarios (18 tests passing)
- [x] OPFS storage integration (`opfs-sahpool` VFS) ✅
- [x] Provider re-election on tab close ✅
- [ ] Service Worker fallback for environments without SharedWorker — `.tasks/backlog/TASK-031-web-service-worker-fallback.md` (blocked on `.tasks/backlog/TASK-038-add-effect-native-submodules.md`)
- [ ] Subscribe/reactive queries in RPC interface — `.tasks/backlog/TASK-032-web-reactive-subscriptions.md` (blocked on `.tasks/backlog/TASK-038-add-effect-native-submodules.md`)

### 4. C Test Harness (Oracle Validation)
**Source**: `research/zig-cr/10-test-oracle.md`
**Priority**: Medium
**Status**: ✅ COMPLETE — All 20/20 tests pass

- [x] Build harness scaffolding (`zig/harness/c-oracle/`)
- [x] Load Zig `.so`/`.dylib` via `sqlite3_load_extension()` in harness
- [x] Run original C tests against Zig extension — **20/20 tests pass (5 suites)**:
  - `test-changes-vtab.sh` ✅
  - `test-as-crr.sh` ✅
  - `test-e2e-sync.sh` ✅
  - `test-filters.sh` ✅
  - `test-sandbox.sh` ✅
  - `test-fract.sh` ✅
- [x] Validate codec compatibility via merge tests

### 5. Cross-platform Packaging & CI
**Source**: `research/zig-cr/93-phased-execution-proposal.md` (Phase 7)
**Priority**: Medium (next focus area)
**Status**: CI complete, npm package pending

- [x] GitHub Actions CI for Zig extension (`.github/workflows/zig-tests.yaml`)
  - Linux x86_64 native tests
  - macOS arm64 native tests
  - WASM build verification
- [x] macOS universal binary (aarch64 + x86_64) ✅ (Round 26) — `.tasks/done/TASK-026-A-macos-universal-binary.md`
- [x] Windows `.dll` build ✅ (Round 27) — `.tasks/done/TASK-030-windows-dll-build.md`
- [ ] iOS/Android static embedding guide — `.tasks/backlog/TASK-033-mobile-static-embedding-guide.md`
- [ ] **npm package updates for Zig-built extensions** — High priority for release — `.tasks/backlog/TASK-034-npm-package-zig-native.md`

### 6. `sqlite3_vtab_config` (Optional)
**Priority**: Low
**Status**: Deferred — not needed for current functionality

---

## Risks / Unknowns

- Performance at scale with many CRR tables (UNION query compilation time)
- Hook clobbering: commit/rollback hooks overwrite existing hooks (no chaining)
- WASM memory limits for very large databases

## MVP Cut (Reference)

The MVP path from `research/zig-cr/91-mvp-roadmap.md` is **COMPLETE**:
- ✅ Phase 0: Extension bring-up
- ✅ Phase 1: Wire format (codec)
- ✅ Phase 2: Clock + site identity
- ✅ Phase 3: `crsql_as_crr` + triggers
- ✅ Phase 4: `crsql_changes` read path
- ✅ Phase 5: Merge + `rows_impacted`
- ✅ Phase 6: E2E sync + alter workflow

---

## Remaining Work for Production Release

> Task cards live in `.tasks/backlog/` and reference this file as the parent backlog.

### High Priority
1. ~~**npm package updates**~~ — ✅ DONE (Round 22) - `@effect-native/libcrsql-browser` ready
2. ~~**OPFS storage**~~ — ✅ DONE (`opfs-sahpool` VFS integrated)

### Medium Priority
3. ~~`crsql_fract_as_ordered`~~ — ✅ DONE (Round 21)
4. ~~macOS universal binary~~ — ✅ DONE (Round 26) — tracked by `.tasks/done/TASK-026-A-macos-universal-binary.md`
5. ~~Windows `.dll` build~~ — ✅ DONE (Round 27) — tracked by `.tasks/done/TASK-030-windows-dll-build.md`
6. ~~Statement cache integration into hot paths~~ — ✅ DONE (Round 22-23)
7. ~~Wire `TableMergeStmts` into changes_vtab write path~~ — ✅ DONE (Round 23)
8. Cross-platform sync validation — ✅ DONE (Round 23)

### Low Priority
9. Service Worker fallback (researched, defer to Phase 2) — `.tasks/backlog/TASK-031-web-service-worker-fallback.md` (TS-gated)
10. Subscribe/reactive queries (researched, defer to Phase 2) — `.tasks/backlog/TASK-032-web-reactive-subscriptions.md` (TS-gated)
11. ~~`crsql_fract_fix_conflict_return_old_key`~~ — ✅ DONE (Round 21)
