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
- [x] **Define the canonical version string and tag shape** (`0.16.300-preview` + `v0.16.300-preview`) and ensure all release automation keys off it.
  - Task: `.tasks/done/TASK-210-release-versioning-and-tags.md`
  - Status: DONE (Round 77) — package.json, flake.nix, sync-version.ts all aligned

### Required build artifacts (scope = Native + WASM + Browser)
- [x] **Native Zig extension release artifacts exist and are verifiable** (darwin + linux at minimum).
  - Task: `.tasks/done/TASK-211-release-native-zig-artifacts.md`
  - Status: DONE (Round 77) — all 5 platforms build successfully
- [x] **WASM build works on current Zig toolchain and is reproducible in CI**.
  - Task: `.tasks/done/TASK-212-fix-wasm-build-for-release.md`
  - Status: DONE (Round 77) — Zig 0.15 compat fixed
- [ ] **Verify WASM build uses Zig 0.15** (not 0.14).
  - Task: `.tasks/triage/TASK-223-verify-wasm-uses-zig-0.15.md`
- [x] **Browser bundle uses local CR-SQLite WASM (not CDN sql.js)**.
  - Task: `.tasks/done/TASK-213-browser-provider-loads-crsqlite-wasm.md`
  - Status: DONE (Round 77) — no CDN dependency, 30/30 browser tests pass

### CI / validation
- [x] **CI re-enabled** on Linux + macOS (workflow restored, split strategy implemented).
  - Task: `.tasks/done/TASK-207-reenable-ci-for-release.md`
  - Status: DONE (Round 78)
- [ ] **Verify CI passes on GitHub after re-enable** (required jobs green).
  - Task: `.tasks/triage/TASK-220-verify-ci-passes-after-reenable.md`
- [x] **Merge atomicity test expectations match current sync policy** (and pass in CI).
  - Task: `.tasks/done/TASK-221-merge-atomicity-test-alignment.md`
  - Status: DONE (Round 79) — tests updated, 9/9 pass
- [x] **Oracle-dependent tests have a CI strategy**.
  - Task: `.tasks/done/TASK-214-ci-oracle-strategy.md`
  - Status: DONE (Round 78) — required vs optional jobs split, 23 zig-only tests identified

### Distribution wiring
- [x] **GitHub Release workflow ships Zig artifacts** (not the legacy `core/` Rust/C publish flow).
  - Task: `.tasks/done/TASK-215-github-release-zig-artifacts.md`
  - Status: DONE (Round 77) — publish.yaml rewritten for Zig
- [x] **nix packaging uses Zig artifacts and matches `0.16.300-preview`** (tags → nix).
  - Task: `.tasks/done/TASK-216-nix-release-uses-zig.md`
  - Status: DONE (Round 78) — flake.nix builds from zig/, version correct
- [x] **npm publish path exists in `effect-native/`** (OIDC provenance publish).
  - Task: `.tasks/done/TASK-217-effect-native-oidc-npm-release.md`
  - Status: DONE (Round 78) — already fully configured; `id-token: write` + `changeset publish --provenance`

### Backwards-compat surface verification
- [x] **Backwards-compat checklist for upstream `0.16.3` is explicit and checked off** (functions, tables, browser runtime expectations).
  - Task: `.tasks/done/TASK-218-compat-checklist-0.16.3.md`
  - Status: DONE (Round 77) — 19/23 functions, wire-identical, intentional differences documented

### Parity / quality gate
- [x] **Empty BLOB PK encoding parity (WF-028)** — time-boxed fix attempt; punt to RC if overflow.
  - Status: DONE (Round 77) — fixed in api.zig bind_blob(), 9/9 tests pass
- [x] **Test suite review and ranking** — identify blind spots, stupid tests, missing coverage.
  - Task: `.tasks/done/TASK-219-test-suite-review-and-ranking.md`
  - Status: DONE (Round 77) — 72 tests reviewed, blind spots documented

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
- 2025-12-25: Round 77 — 8 tasks completed (versioning, artifacts, WASM, browser, GitHub release, compat checklist, test review, WF-028 fix)
- 2025-12-25: Round 78 — 4 tasks completed (CI re-enable, oracle strategy, nix Zig, npm OIDC)
- 2025-12-25: **All technical blockers cleared.** Only remaining: Tom sign-off + CI verification.

## Completion Notes
(Empty until done.)
