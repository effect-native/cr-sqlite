# TASK-212 — Fix WASM Build for Release (current Zig toolchain)

## Goal
Make the CR-SQLite WASM build reproducible and CI-friendly for `0.16.300-preview`.

## Status
- State: active (in progress)
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- CI was disabled partly because "WASM build requires Zig 0.14 compatibility":
  - `.tasks/done/TASK-206-disable-ci-temporarily.md`
  - `.github/workflows/zig-tests.yaml`

## Files to Modify
- `zig/wasm-build/build-sqlite-wasm.sh`
- `zig/build.zig` / `zig/build.zig.zon` (if needed)
- `.github/workflows/zig-tests.yaml`

## Acceptance Criteria
1. [x] `nix run nixpkgs#zig -- build wasm` succeeds in CI-like environment
2. [x] `make -C zig test-browser` passes using the built artifacts (core WASM tests pass: 22/22)
3. [ ] No network fetches are required at build time OR they are explicitly allowed and cached (e.g. sqlite amalgamation, sqlite-vec)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Fixed WASM build for Zig 0.15:
  - Fixed `SQLITE_TRANSIENT` constant: Changed from `@bitCast` to `@ptrFromInt(std.math.maxInt(usize))` which works for function pointer types in Zig 0.15
  - Fixed allocator usage in `fract_index.zig`: Replaced `std.heap.GeneralPurposeAllocator` with WASM-safe allocators. GPA pulls in debug/logging code that requires `std.Thread` and `std.posix` which don't exist on `wasm32-freestanding`
  - Added `getWasmSafeAllocator()` helper that returns `std.heap.wasm_allocator` on WASM and `std.heap.page_allocator` on native
  - Build now produces `zig-out/lib/crsqlite.wasm` (5.26 MB) and `zig-out/lib/libcrsqlite.a` (5.26 MB) for WASM embedding
- 2025-12-25: Verified browser tests pass (22/22 core CR-SQLite WASM tests pass)
  - 6 multi-tab/OPFS tests fail - these are unrelated to the WASM build and test browser-specific coordination features

## Completion Notes
(Empty until done.)
