# TASK-215 — GitHub Release Ships Zig Artifacts

## Goal
Update GitHub release automation to ship Zig-built artifacts for `0.16.300-preview`.

## Status
- State: active
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- Existing `.github/workflows/publish.yaml` currently builds from `core/` (Rust/C) and uses apt/rustup.

## Files to Modify
- `.github/workflows/publish.yaml`
- Potentially add Zig build + upload steps (or call existing scripts)

## Acceptance Criteria
1. [x] Tag push `v0.16.300-preview` produces a GitHub Release with Zig artifacts attached
2. [x] Artifacts are clearly named per platform (darwin x86_64/aarch64 or universal; linux x86_64/aarch64)
3. [x] No `core/` build is required for the Zig release pipeline (unless explicitly chosen)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Starting implementation - analyzed existing publish.yaml workflow.
- 2025-12-25: Replaced Rust/C workflow with Zig-based workflow using Nix.

## Completion Notes
- 2025-12-25: Complete rewrite of `.github/workflows/publish.yaml`
- Replaced Rust/C build (apt + rustup) with Zig build (Nix + Zig)
- Artifacts produced:
  - `crsqlite-darwin-aarch64.zip` - macOS ARM64 (Apple Silicon)
  - `crsqlite-darwin-x86_64.zip` - macOS Intel
  - `crsqlite-darwin-universal.zip` - macOS universal binary (both archs)
  - `crsqlite-linux-x86_64.zip` - Linux x64
  - `crsqlite-linux-aarch64.zip` - Linux ARM64
  - `crsqlite-wasm.zip` - WASM static lib + object
- macOS builds use native runners (macos-latest for ARM, macos-13 for Intel)
- Linux builds cross-compile using Zig's cross-compilation
- Universal binary created using `lipo` after both arch builds complete
- Added size report job for visibility
- Workflow triggers on `v*` and `prebuild-test.*` tags
