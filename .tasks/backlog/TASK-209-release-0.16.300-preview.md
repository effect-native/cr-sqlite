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

This list is intended to be exhaustive. Each blocker must have an owning task card.

### Tom sign-off (explicit gate)
- [ ] **Tom release sign-off recorded**: `.wishes/blocked-on-tom/release-readiness-decision.md`

### Versioning + tag semantics
- [ ] **Define the canonical version string and tag shape** (`0.16.300-preview` + `v0.16.300-preview`) and ensure all release automation keys off it.
  - Task: `.tasks/backlog/TASK-210-release-versioning-and-tags.md`

### Required build artifacts (scope = Native + WASM + Browser)
- [ ] **Native Zig extension release artifacts exist and are verifiable** (darwin + linux at minimum).
  - Task: `.tasks/backlog/TASK-211-release-native-zig-artifacts.md`
- [ ] **WASM build works on current Zig toolchain and is reproducible in CI**.
  - Task: `.tasks/backlog/TASK-212-fix-wasm-build-for-release.md`
- [ ] **Browser bundle uses local CR-SQLite WASM (not CDN sql.js)**.
  - Evidence of prior gap: `.tasks/done/TASK-069-wire-scratchpads.md`
  - Task: `.tasks/backlog/TASK-213-browser-provider-loads-crsqlite-wasm.md`

### CI / validation
- [ ] **CI re-enabled and passing** on Linux + macOS, including WASM + browser tests.
  - Task: `.tasks/backlog/TASK-207-reenable-ci-for-release.md`
- [ ] **Oracle-dependent tests have a CI strategy**.
  - Either provide Rust/C oracle binaries in CI OR explicitly skip oracle-dependent jobs.
  - Evidence of issue: `.tasks/done/TASK-206-disable-ci-temporarily.md`
  - Task: `.tasks/backlog/TASK-214-ci-oracle-strategy.md`

### Distribution wiring
- [ ] **GitHub Release workflow ships Zig artifacts** (not the legacy `core/` Rust/C publish flow).
  - Task: `.tasks/backlog/TASK-215-github-release-zig-artifacts.md`
- [ ] **nix packaging uses Zig artifacts and matches `0.16.300-preview`** (tags → nix).
  - Task: `.tasks/backlog/TASK-216-nix-release-uses-zig.md`
- [ ] **npm publish path exists in `effect-native/`** (OIDC provenance publish).
  - Task: `.tasks/backlog/TASK-217-effect-native-oidc-npm-release.md`

### Backwards-compat surface verification
- [ ] **Backwards-compat checklist for upstream `0.16.3` is explicit and checked off** (functions, tables, browser runtime expectations).
  - Task: `.tasks/backlog/TASK-218-compat-checklist-0.16.3.md`

### Parity / quality gate
- [ ] **Empty BLOB PK encoding parity (WF-028)** — time-boxed fix attempt; punt to RC if overflow.
  - Wish: `.wishes/blocked-on-tom/zig-empty-blob-pk-encoding-parity.md`
- [ ] **Test suite review and ranking** — identify blind spots, stupid tests, missing coverage.
  - Task: `.tasks/backlog/TASK-219-test-suite-review-and-ranking.md`

## Files to Modify
- `.tasks/backlog/TASK-209-release-0.16.300-preview.md` (this file)

## Acceptance Criteria
1. [ ] Every blocker above has an owning `.tasks/**/TASK-*.md` card
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
