# TASK-039: Spec Phase 1 — Global Mesh Package Map (Effect Native)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: [`.wishes/effect-native.md`](../../.wishes/effect-native.md)
- Proposal: [`research/zig-cr/102-proposal-crsqlite-global-mesh.md`](../../research/zig-cr/102-proposal-crsqlite-global-mesh.md)
- TS workflow rules: [`effect-native/.specs/AGENTS.md`](../../effect-native/.specs/AGENTS.md)
- Existing package (Effect SQL surface): [`effect-native/packages-native/crsql/`](../../effect-native/packages-native/crsql/)
- Existing package (native binaries): [`effect-native/packages-native/libcrsql/`](../../effect-native/packages-native/libcrsql/)
- Upstream Effect SQL packages:
  - [`./.refs/effect/packages/sql/`](../../.refs/effect/packages/sql/)
  - [`./.refs/effect/packages/sql-sqlite-bun/`](../../.refs/effect/packages/sql-sqlite-bun/)

## Description
Create the Phase-1 `instructions.md` for the global mesh work, focused on *package boundaries*.

This deliverable defines:
- the set of new atomic packages we intend to add (names + responsibilities)
- which existing packages must change (and why)
- which upstream Effect SQL packages we’re integrating with

This task must follow the spec-first workflow.

## Files to Create/Modify
- `effect-native/.specs/crsqlite-global-mesh-packages/instructions.md`
- `effect-native/.specs/README.md` (add a link to the new spec)

## Acceptance Criteria
- [x] `effect-native/.specs/crsqlite-global-mesh-packages/instructions.md` exists and follows Phase 1 rules.
- [x] The doc includes an explicit "Out of Scope" section.
- [x] The doc lists candidate packages as *names only* (no code, no pseudo-code).
- [x] The doc links back to `research/zig-cr/102-proposal-crsqlite-global-mesh.md`.
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created to kick off TS mesh planning
- Created `effect-native/.specs/crsqlite-global-mesh-packages/instructions.md`
- Updated `effect-native/.specs/README.md` to link to new spec
- Phase 1 complete — awaiting orchestrator approval before Phase 2

## Completion Notes
Phase 1 deliverable complete. Created instructions.md with:
- Context explaining current packages and need for mesh capabilities
- User story for local-first developers
- 10 candidate new packages (protocol, core, transport interface, 4 transport adapters, 3 runtime adapters)
- 2 existing packages to modify (crsql, libcrsql)
- 3 upstream Effect SQL integration targets
- Explicit Out of Scope section (auth, encryption, schema migration during sync, etc.)
- Links back to source proposal
