# TASK-211 — Release Native Zig Artifacts (darwin + linux)

## Goal
Produce and verify the native Zig loadable extension artifacts for `0.16.300-preview`.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Scope
Minimum required for release:
- macOS (arm64 + x86_64) `.dylib` (universal acceptable)
- Linux x86_64 `.so`

## Files to Modify
- `zig/` build outputs are generated, but the task should modify only build scripts / CI packaging:
  - `scripts/build-zig.sh`
  - `scripts/build-production.ts` (if used for bundling)
  - `.github/workflows/zig-tests.yaml` (if needed for artifact upload)

## Acceptance Criteria
1. [ ] `nix run nixpkgs#zig -- build -Doptimize=ReleaseFast` succeeds
2. [ ] Built artifacts exist with deterministic names under `zig/zig-out/lib/`
3. [ ] Artifacts can be loaded by sqlite on their target platforms
4. [ ] Artifact naming + layout matches the GitHub Release upload plan

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
