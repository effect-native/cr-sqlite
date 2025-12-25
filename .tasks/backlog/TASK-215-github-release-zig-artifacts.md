# TASK-215 — GitHub Release Ships Zig Artifacts

## Goal
Update GitHub release automation to ship Zig-built artifacts for `0.16.300-preview`.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- Existing `.github/workflows/publish.yaml` currently builds from `core/` (Rust/C) and uses apt/rustup.

## Files to Modify
- `.github/workflows/publish.yaml`
- Potentially add Zig build + upload steps (or call existing scripts)

## Acceptance Criteria
1. [ ] Tag push `v0.16.300-preview` produces a GitHub Release with Zig artifacts attached
2. [ ] Artifacts are clearly named per platform (darwin x86_64/aarch64 or universal; linux x86_64/aarch64)
3. [ ] No `core/` build is required for the Zig release pipeline (unless explicitly chosen)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
