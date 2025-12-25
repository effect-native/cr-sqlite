# TASK-209 — Release 0.16.300-preview (Zig CR-SQLite)

## Goal
Ship the first public preview release `0.16.300-preview`, targeting backwards compatibility with the abandoned upstream `cr-sqlite` `v0.16.3` surface.

## Status
- State: backlog
- Priority: HIGH (primary focus)
- Version: `0.16.300-preview`
- Created: 2025-12-25

## Release Definition (what “done” means)
The release is considered ready when:
1. All required artifacts are produced and verifiable (native + WASM + browser bundle).
2. Distribution channels are publishable:
   - npm (OIDC) via `effect-native`
   - GitHub Releases for native binaries
   - nix via GitHub tags
3. Tom personally signs off the release readiness decision.

## Blockers (must be cleared)

### Tom sign-off (explicit gate)
- [ ] **Tom release sign-off recorded**: `.wishes/blocked-on-tom/release-readiness-decision.md`

### Required build artifacts
- [ ] **WASM build works on current Zig toolchain** (prior CI notes mention Zig 0.14 incompatibility)
  - Related: `.tasks/backlog/TASK-207-reenable-ci-for-release.md`
- [ ] **Browser bundle uses local CR-SQLite WASM** (not CDN sql.js)
  - Evidence of prior gap: `.tasks/done/TASK-069-wire-scratchpads.md`

### CI / validation
- [ ] **CI re-enabled and passing** on Linux + macOS, including WASM
  - Task: `.tasks/backlog/TASK-207-reenable-ci-for-release.md`
- [ ] **Oracle-dependent tests have a CI strategy**
  - Either provide Rust/C oracle binaries in CI OR explicitly skip oracle-dependent jobs.
  - Evidence of issue: `.tasks/done/TASK-206-disable-ci-temporarily.md`

### Packaging / distribution wiring
- [ ] **npm release path defined and implemented in `effect-native/`** (OIDC publish)
  - Note: TypeScript changes must be spec-gated under `effect-native/.specs/`.
- [ ] **GitHub Release artifact matrix defined + produced** (at minimum darwin + linux)
- [ ] **nix packaging hooks validated via tag** (flake / fetch-from-git tag flow)

### Backwards-compat surface verification
- [ ] **Required upstream surface areas confirmed** for `0.16.3`-compat
  - This is a checklist task: enumerate what “backwards compatible” means for this release (functions, tables, wire behavior).
  - The goal is to avoid accidentally shipping a preview missing required pieces.

## Files to Modify
- `.tasks/backlog/TASK-209-release-0.16.300-preview.md` (this file)

## Acceptance Criteria
1. [ ] Every blocker above has an owning `.tasks/**/TASK-*.md` card (or explicit rationale why not)
2. [ ] Each blocker has a clear verification command or observable proof
3. [ ] Blockers list stays current as new gaps are discovered

## Parent Docs / Cross-links
- Release sign-off: `.wishes/blocked-on-tom/release-readiness-decision.md`
- CI disabled: `.tasks/done/TASK-206-disable-ci-temporarily.md`
- CI re-enable: `.tasks/backlog/TASK-207-reenable-ci-for-release.md`
- Canonical gap tracking: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-25: Created release tracking task; blockers captured from existing evidence.

## Completion Notes
(Empty until done.)
