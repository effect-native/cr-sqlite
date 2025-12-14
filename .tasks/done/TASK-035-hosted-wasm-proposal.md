# TASK-035: Hosted Browser ESM Proposal (Multi-tab)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] Proposal describes a minimal importable ESM surface.
- [x] Proposal describes where artifacts live and how they're hosted.
- [x] Proposal calls out which parts are blocked on TS/publishing decisions.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started
- Reviewed existing browser-dist implementation (crsql-multitab.js, coordinator.js, provider.js)
- Reviewed multi-tab architecture proposal (research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md)
- Wrote comprehensive hosted ESM proposal in zig/browser-dist/README.md
- Moved wish to .wishes/done/hosted-wasm.md with completion notes

## Completion Notes
**Date**: 2025-12-14

**Summary**: Wrote a comprehensive proposal for the "hosted wasm" experience where users can simply `import('https://cdn/.../crsql-multitab.js')` and everything Just Works™.

**Proposal Location**: `zig/browser-dist/README.md` (under "Hosted ESM Distribution (Proposal)" section)

**Key Proposal Points**:
1. **Files to host**: 5 files (crsql-multitab.js, coordinator.js, provider.js, sql-wasm.js, sql-wasm.wasm) totaling ~1.5MB
2. **Versioning**: Immutable version URLs (/libcrsql-browser@0.1.0/...) + @latest alias for prototyping
3. **Public API**: DbClient class + createDbClient factory as the stable surface
4. **Browser requirements**: Chrome 86+, Firefox 114+, Safari 15.4+ (SharedWorker + Web Locks + OPFS)
5. **No COOP/COEP required**: Uses async OPFS approach instead of SharedArrayBuffer
6. **Cross-origin solution**: Blob URL wrapper for SharedWorker cross-origin loading

**Implementation Checklist** (for future work):
- Blob URL wrapper for SharedWorker
- Versioned CDN deployment workflow
- Use bundled sql-wasm.js instead of loading from cdnjs
- WASM URL resolution in provider
- Optional: integrity hashes, preload hints

**Open Questions for Tom**:
1. Package name: `@effect-native/libcrsql-browser` vs alternatives?
2. CDN choice: Self-hosted vs unpkg vs esm.sh vs skypack?
3. Publishing workflow: Manual vs automated npm+CDN publish?
4. Version strategy: semver strict vs date-based vs git-sha?

**Wish completed**: `.wishes/done/hosted-wasm.md`
