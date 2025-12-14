# TASK-036: Release Planning Proposal (Where + How)

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
- Wish: `.wishes/release-planning.md`
- Current packages: `package.json`, `zig/browser-dist/package.json`
- CI: `.github/workflows/*`
- **Proposal:** `research/zig-cr/103-release-planning-proposal.md`

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
- [x] Proposal enumerates channels + pros/cons.
- [x] Proposal has a staged plan (MVP web beta → linux → mac/windows, etc.).
- [x] Proposal lists concrete next engineering tasks and where they live in `.tasks/`.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started
- Analyzed existing package structure and distribution
- Researched competitor distribution patterns (better-sqlite3, sql.js, libsql)
- Wrote comprehensive proposal at `research/zig-cr/103-release-planning-proposal.md`
- Updated `.wishes/release-planning.md` with completion notes
- Task complete

## Completion Notes

**Completed:** 2025-12-14

**Deliverables:**
1. `research/zig-cr/103-release-planning-proposal.md` - Full release planning proposal

**Key Recommendations:**
- **Primary channel:** npm with platform-specific optional dependency packages (follow better-sqlite3 model)
- **Secondary channels:** GitHub Releases for raw binaries, Nix flakes for reproducible builds
- **Versioning:** Aligned versions across all packages (e.g., 0.17.0)
- **Staged rollout:** Browser beta (week 1) -> Linux (week 2) -> macOS/Windows (week 3) -> Stable (week 4)

**Next Tasks Identified:**
- TASK-037: Publish browser package to npm beta
- TASK-038: Set up Zig Linux CI builds
- TASK-039: Create platform-specific npm packages
- TASK-040: Update root README for Zig transition
- TASK-041: Write browser package README
- TASK-042: Create GitHub Release workflow
