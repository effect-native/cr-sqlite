# TASK-035: Hosted Browser ESM Proposal (Multi-tab)

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
- Wish: `.wishes/hosted-wasm.md`
- Current browser dist: `zig/browser-dist/`
- Multi-tab architecture proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`

## Description
Write a concrete proposal for the "hosted wasm" experience:

"I can just `import('https://.../crsqlite-multitab.mjs')` and it all Just Works."

Do not implement hosted distribution yet. Produce a tight checklist for:
- what files need to be hosted
- how versioning/cache busting works
- what the public API looks like
- what the minimal example looks like
- what constraints (COOP/COEP, browser support) are required

Keep this proposal close to the code that will ship (prefer updating `zig/browser-dist/README.md` or a small `research/zig-cr/*` doc rather than new standalone docs elsewhere).

## Files to Modify
- `zig/browser-dist/README.md` and/or `research/zig-cr/*`
- `.wishes/hosted-wasm.md` (mark done + link to proposal)

## Acceptance Criteria
- [ ] Proposal describes a minimal importable ESM surface.
- [ ] Proposal describes where artifacts live and how they’re hosted.
- [ ] Proposal calls out which parts are blocked on TS/publishing decisions.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

## Completion Notes
[fill in when done]
