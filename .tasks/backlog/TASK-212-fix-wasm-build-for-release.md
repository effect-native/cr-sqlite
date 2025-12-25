# TASK-212 — Fix WASM Build for Release (current Zig toolchain)

## Goal
Make the CR-SQLite WASM build reproducible and CI-friendly for `0.16.300-preview`.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- CI was disabled partly because “WASM build requires Zig 0.14 compatibility”:
  - `.tasks/done/TASK-206-disable-ci-temporarily.md`
  - `.github/workflows/zig-tests.yaml`

## Files to Modify
- `zig/wasm-build/build-sqlite-wasm.sh`
- `zig/build.zig` / `zig/build.zig.zon` (if needed)
- `.github/workflows/zig-tests.yaml`

## Acceptance Criteria
1. [ ] `nix run nixpkgs#zig -- build wasm` succeeds in CI-like environment
2. [ ] `make -C zig test-browser` passes using the built artifacts
3. [ ] No network fetches are required at build time OR they are explicitly allowed and cached (e.g. sqlite amalgamation, sqlite-vec)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
