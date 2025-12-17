# TASK-067: Zig WASM baked-in extensions (sqlite-vec / FTS / BJSON)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/wasm-extras.md`
- Zig wasm build scripts: `zig/wasm-build/`
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (add a new section under Gaps)

## Description
Our wasm build does not support loadable extensions. This task bakes a small set of useful extensions into the wasm artifact:

- `sqlite-vec`
- Full text search (FTS)
- BJSON

This is strictly about build composition and test evidence; not about exposing a large JS API surface.

## Files to Modify
- `zig/wasm-build/build-sqlite-wasm.sh`
- `zig/browser-test/tests/crsql-wasm.spec.ts` (add assertions proving extensions present)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] `zig/browser-test/tests/crsql-wasm.spec.ts` contains deterministic evidence that each extension is available.
- [x] The wasm build includes the extensions without requiring dynamic loading.
- [x] Verification:
  - `make -C zig test-browser` (or the repo's existing browser test command)

## Progress Log
### 2025-12-17
- Task created from `.wishes/wasm-extras.md` during "update tasks".

### 2025-12-16
- Modified `zig/wasm-build/build-sqlite-wasm.sh`:
  - Added Step 2 to download sqlite-vec v0.1.6 amalgamation from GitHub releases
  - Updated glue code (Step 3) to register sqlite-vec as an auto-extension alongside CR-SQLite
  - Added compilation of `sqlite-vec.o` with `-DSQLITE_CORE -DSQLITE_VEC_OMIT_FS -DNDEBUG` flags
  - Added `sqlite-vec.o` to the final linking step
- Added "Baked-in Extensions" test suite to `zig/browser-test/tests/crsql-wasm.spec.ts`:
  - FTS5 tests: virtual table creation, full-text search via COUNT(*)
  - JSON/JSONB tests: `json()`, `json_extract()`, `jsonb()`, `json_array()`, `json_object()`
  - sqlite-vec tests: `vec_version()`, `vec_f32()`, `vec_distance_l2()`, `vec_distance_cosine()`, `vec0` virtual table, KNN queries
- Copied updated WASM files to `zig/browser-test/fixtures/` and `zig/browser-dist/`
- All 30 browser tests pass

## Completion Notes
### 2025-12-16
- **Extensions successfully baked into WASM build:**
  - **FTS5**: Full-text search enabled via `-DSQLITE_ENABLE_FTS5` flag (already in SQLite)
  - **JSON/JSONB**: JSON1 enabled via `-DSQLITE_ENABLE_JSON1` flag; JSONB built into SQLite 3.45+
  - **sqlite-vec v0.1.6**: Statically linked, auto-initialized via `sqlite3_auto_extension()`
- **WASM size**: 1,440,717 bytes (increased from 1,340,272 due to sqlite-vec)
- **Test verification command**: `make -C zig test-browser` - 30/30 tests pass
- **Commit**: (pending)
