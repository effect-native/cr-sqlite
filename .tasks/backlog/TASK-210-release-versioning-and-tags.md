# TASK-210 — Release Versioning + Tags (0.16.300-preview)

## Goal
Make `0.16.300-preview` a first-class, consistent version across:
- git tags
- npm publish (effect-native OIDC)
- GitHub Releases (native artifacts)
- nix (tags)

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Required Decisions / Clarifications
- Canonical git tag name: `v0.16.300-preview` (assumed)
- Root repo `package.json` currently uses `0.16.3-1`; decide whether it becomes `0.16.300-preview` or remains separate from release version.

## Files to Modify
- `package.json` (root) (version)
- `flake.nix` (version strings printed + derivation version)
- `scripts/sync-version.ts` (version sync semantics)
- Any release scripts that assume `0.16.3`

## Acceptance Criteria
1. [ ] A single canonical version string is defined: `0.16.300-preview`
2. [ ] A single canonical git tag format is defined and used: `v0.16.300-preview`
3. [ ] Root `package.json`, `flake.nix`, and any version reporters agree (or explicitly document divergence)
4. [ ] `npm run sync-version` does not clobber preview versions back to `0.16.3-1`

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
