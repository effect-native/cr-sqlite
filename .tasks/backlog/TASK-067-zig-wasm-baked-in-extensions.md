# TASK-067: Zig WASM baked-in extensions (sqlite-vec / FTS / BJSON)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/wasm-extras.md`
- Zig wasm build scripts: `zig/wasm-build/`
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (add a new section under Gaps)

## Description
Our wasm build does not support loadable extensions. This task bakes a small set of useful extensions into the wasm artifact:

- `sqlite-vec`
- Full text search (FTS)
- BJSON

This is strictly about build composition and test evidence; not about exposing a large JS API surface.

## Files to Modify
- `zig/wasm-build/build-sqlite-wasm.sh`
- `zig/browser-test/tests/crsql-wasm.spec.ts` (add assertions proving extensions present)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `zig/browser-test/tests/crsql-wasm.spec.ts` contains deterministic evidence that each extension is available.
- [ ] The wasm build includes the extensions without requiring dynamic loading.
- [ ] Verification:
  - `make -C zig test-browser` (or the repo’s existing browser test command)

## Progress Log
### 2025-12-17
- Task created from `.wishes/wasm-extras.md` during "update tasks".

## Completion Notes
[fill in when done]
