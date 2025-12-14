# 92-gap-backlog

> **Last Updated**: 2025-12-14 (Round 13)

## Status Summary

**MVP COMPLETE** — All core replication functionality implemented and tested:
- Native parity tests: 44/44 PASS
- Browser WASM tests: 10/10 PASS
- E2E sync tests: ALL PASS

---

## Recent Progress (Rounds 10-13)

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

### 1. Performance Optimizations
**Source**: `research/zig-cr/11-performance-hotspots.md`
**Priority**: Medium
**Status**: Infrastructure complete, integration pending

- [x] Statement caching infrastructure (`zig/src/stmt_cache.zig`)
- [ ] Integrate stmt_cache into union query generation
- [ ] Integrate stmt_cache into clock writes
- [ ] Schema version invalidation caching (`PRAGMA schema_version`)
- [ ] `PRAGMA data_version` check amortization (per-transaction flag)
- [ ] Prepared statement persistence (`SQLITE_PREPARE_PERSISTENT`)

### 2. Fractional Indexing UDFs
**Source**: `research/zig-cr/07-fractindex-rust.md`
**Priority**: Low (deferred from MVP)
**Status**: Not started

- [ ] `crsql_fract_key_between(left, right)` — lexicographic midpoint
- [ ] `crsql_fract_as_ordered(table, order_col, collection_cols...)` — view + triggers
- [ ] `crsql_fract_fix_conflict_return_old_key(...)` — collision repair

### 3. Multi-tab Web Architecture
**Source**: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
**Priority**: High (for production web use)
**Status**: Core infrastructure complete

- [x] SharedWorker coordinator for provider election (`zig/browser-test/src/SharedWorkerCoordinator.ts`)
- [x] Web Locks for exclusive provider access
- [x] RPC interface (exec, query) (`zig/browser-test/src/DbClient.ts`)
- [x] Provider worker (`zig/browser-test/src/ProviderWorker.ts`)
- [x] Browser test coverage for multi-tab scenarios (`zig/browser-test/tests/multi-tab.spec.ts`)
- [ ] Service Worker fallback for environments without SharedWorker
- [ ] Subscribe/reactive queries in RPC interface
- [ ] OPFS storage integration (`opfs-sahpool` VFS)
- [ ] Provider migration safety (idempotent writes)

### 4. C Test Harness (Oracle Validation)
**Source**: `research/zig-cr/10-test-oracle.md`
**Priority**: Medium
**Status**: Scaffolding complete

- [x] Build harness scaffolding (`zig/harness/c-oracle/`)
- [ ] Load Zig `.so`/`.dylib` via `sqlite3_load_extension()` in harness
- [ ] Run original C tests (`core/src/*.test.c`) against Zig extension
- [ ] Validate byte-for-byte codec compatibility

### 5. Cross-platform Packaging & CI
**Source**: `research/zig-cr/93-phased-execution-proposal.md` (Phase 7)
**Priority**: Medium
**Status**: CI complete, packaging pending

- [x] GitHub Actions CI for Zig extension (`.github/workflows/zig-tests.yaml`)
  - Linux x86_64 native tests
  - macOS arm64 native tests
  - WASM build verification
- [ ] macOS universal binary (aarch64 + x86_64)
- [ ] Windows `.dll` build
- [ ] iOS/Android static embedding guide
- [ ] npm package updates for Zig-built extensions

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
