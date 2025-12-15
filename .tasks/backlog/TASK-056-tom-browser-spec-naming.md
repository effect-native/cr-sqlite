# TASK-056: Tom decision — Pick browser runtime spec name + package boundary

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
Tom

## Parent Docs / Cross-links
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
- Spec workflow: `effect-native/.specs/AGENTS.md`
- Spec tasks:
  - `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`
  - `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md`

## Description
Before writing browser runtime specs, we need a crisp naming + boundary decision so we don’t create the wrong package(s) and then fight the repo structure.

## Files to Modify
- `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`

## Acceptance Criteria
- [ ] Update `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md` with:
  - The chosen spec directory name under `effect-native/.specs/` (e.g., `crsqlite-web-multitab` vs `crsql-mesh-runtime-web`)
  - The intended npm package name(s) (one package vs split coordinator/client/provider)
  - One-sentence boundary statement for each package (“owns coordination”, “owns provider worker”, etc.)

## Progress Log
### 2025-12-15
- Task created to prevent mis-scoped browser spec work.

## Completion Notes
[fill in when done]
