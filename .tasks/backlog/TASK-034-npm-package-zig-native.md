# TASK-034: npm Packaging for Zig-built Native Extensions

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

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
- [ ] Build pipeline produces Zig artifacts for at least one platform and places them in a deterministic location.
- [ ] Runtime loader can select Zig artifacts deterministically (or explicitly documents why it can’t yet).
- [ ] `dist.test.ts` (or equivalent existing packaging sanity tests) extended to assert Zig artifacts presence/selection.
- [ ] No regression in existing C/Rust artifact selection.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

## Completion Notes
[fill in when done]
