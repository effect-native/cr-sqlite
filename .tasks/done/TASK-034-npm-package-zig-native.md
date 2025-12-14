# TASK-034: npm Packaging for Zig-built Native Extensions

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md` ("Cross-platform Packaging & CI" / "Remaining Work for Production Release")
- Existing JS package entry: `index.js`, `package.json`, `scripts/*`
- Existing prebuilt artifacts: `lib/`
- Zig build artifacts: `zig/zig-out*/lib/libcrsqlite.*`

## Description
Package Zig-built native artifacts in the main npm package so users can install and load Zig `crsqlite` without building from source.

This repository already ships C/Rust prebuilt artifacts in `lib/`. Extend or parallel that mechanism for Zig builds.

Constraints:
- Do not introduce a new TS project; stay within existing build tooling.
- Prefer reproducible builds (Nix).

## Files to Modify
- `package.json`
- `scripts/*` (likely `scripts/build-production.ts` / `scripts/build-production.cjs`)
- `index.js` (if selection logic changes)
- `lib/*` (only if intentionally adding artifacts)
- `research/zig-cr/92-gap-backlog.md` (status notes)

## Acceptance Criteria
- [x] Build pipeline produces Zig artifacts for at least one platform and places them in a deterministic location.
- [x] Runtime loader can select Zig artifacts deterministically (or explicitly documents why it can't yet).
- [x] `dist.test.ts` (or equivalent existing packaging sanity tests) extended to assert Zig artifacts presence/selection.
- [x] No regression in existing C/Rust artifact selection.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

### 2025-12-14 (Implementation)
- Updated `index.js` with implementation selection logic:
  - New `PREFER_IMPLEMENTATION` export (controlled by `CRSQLITE_IMPL` env var)
  - `getExtensionPath()` now accepts `{ implementation: 'zig' | 'c-rust' | 'auto' }` option
  - Default 'auto' mode prefers Zig, falls back to C/Rust
- Updated `index.d.ts` with new types and exports
- Created `scripts/build-zig.sh` - builds Zig extension for various platforms
- Created `scripts/bundle-zig-lib.sh` - bundles Zig artifacts to `lib/` with naming convention `crsqlite-zig-<platform>-<arch>.<ext>`
- Updated `package.json` with new scripts:
  - `build:zig` - build for current platform
  - `build:zig:all` - build all platforms
  - `bundle-lib:zig` - bundle Zig artifacts to lib/
  - `test:zig` - run packaging tests
- Updated `dist.test.ts` with Zig artifact verification tests
- Bundled macOS Zig artifacts (universal, aarch64, x86_64) to lib/
- All tests pass:
  - Loader correctly prefers Zig artifacts in 'auto' mode
  - Explicit implementation selection works
  - No regression in C/Rust artifact selection logic

## Completion Notes
**Completed 2025-12-14**

Changes made:
1. `index.js` - Added implementation selection (zig/c-rust/auto)
2. `index.d.ts` - Added new types for implementation selection
3. `scripts/build-zig.sh` - New script to build Zig extension cross-platform
4. `scripts/bundle-zig-lib.sh` - New script to bundle Zig artifacts to lib/
5. `package.json` - Added new npm scripts for Zig builds
6. `dist.test.ts` - Extended with Zig artifact verification

Naming convention:
- C/Rust: `crsqlite-<platform>-<arch>.<ext>`
- Zig: `crsqlite-zig-<platform>-<arch>.<ext>`

Artifacts in lib/:
- `crsqlite-zig-darwin-universal.dylib` (macOS universal)
- `crsqlite-zig-darwin-aarch64.dylib` (macOS ARM64)
- `crsqlite-zig-darwin-x86_64.dylib` (macOS x64)
- Linux artifacts can be built with `npm run build:zig linux && npm run bundle-lib:zig linux`
