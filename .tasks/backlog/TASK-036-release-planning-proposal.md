# TASK-036: Release Planning Proposal (Where + How)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/release-planning.md`
- Current packages: `package.json`, `zig/browser-dist/package.json`
- CI: `.github/workflows/*`

## Description
Write a proposal for how/where to release the Zig work (native + browser):

- Which registries/channels: Nix, npm, GitHub releases, etc.
- What versioning strategy: aligned with root package version or independent
- What artifact matrix: darwin arm64/x64, linux x64/arm64, windows, wasm
- What docs are needed and where they live (prefer in-repo, near code)

Do not publish anything. Output should be a checklist and a proposed staged rollout.

## Files to Modify
- `research/zig-cr/*` (small proposal doc) or `README.md` (if appropriate)
- `.wishes/release-planning.md` (mark done + link to proposal)

## Acceptance Criteria
- [ ] Proposal enumerates channels + pros/cons.
- [ ] Proposal has a staged plan (MVP web beta → linux → mac/windows, etc.).
- [ ] Proposal lists concrete next engineering tasks and where they live in `.tasks/`.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

## Completion Notes
[fill in when done]
