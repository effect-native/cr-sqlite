# TASK-210 — Release Versioning + Tags (0.16.300-preview)

## Goal
Make `0.16.300-preview` a first-class, consistent version across:
- git tags
- npm publish (effect-native OIDC)
- GitHub Releases (native artifacts)
- nix (tags)

## Status
- State: active
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
1. [x] A single canonical version string is defined: `0.16.300-preview`
2. [x] A single canonical git tag format is defined and used: `v0.16.300-preview`
3. [x] Root `package.json`, `flake.nix`, and any version reporters agree (or explicitly document divergence)
4. [x] `npm run sync-version` does not clobber preview versions back to `0.16.3-1`

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Starting execution. Analyzed current state:
  - `package.json`: `0.16.3-1`
  - `flake.nix`: `0.16.3` (hardcoded in 2 places: derivation version + printVersion)
  - `sync-version.ts`: Gets version from `nix run .#print-version`, compares base version, appends `-1` suffix
  - `scripts/update-crsqlite-oracle.sh`: Downloads upstream v0.16.3 binaries (unrelated, keep as-is)
- 2025-12-25: Completed all changes:
  - Updated `package.json` version: `0.16.3-1` → `0.16.300-preview`
  - Updated `flake.nix` derivation version: `0.16.3` → `0.16.300-preview`
  - Updated `flake.nix` printVersion app: `0.16.3` → `0.16.300-preview`
  - Updated `sync-version.ts` to handle prerelease versions correctly (use canonical version directly, don't append `-1`)
  - Verified `nix run .#print-version` returns `0.16.300-preview`
  - Verified `npm run sync-version` correctly preserves the preview version

## Completion Notes
- Date: 2025-12-25
- Files modified:
  - `package.json`: version `0.16.3-1` → `0.16.300-preview`
  - `flake.nix`: version in 2 places: derivation and printVersion app
  - `scripts/sync-version.ts`: added prerelease version handling
- Verified:
  - `nix run .#print-version` outputs `0.16.300-preview`
  - `npm run sync-version` preserves the preview version (no clobbering)
- Note: `scripts/update-crsqlite-oracle.sh` intentionally kept at upstream `0.16.3` (downloads vlcn-io oracle binaries)
- Canonical git tag for release: `v0.16.300-preview`
- Documented divergence: `effect-native/packages-native/libcrsql/src/version.ts` exports `CRSQLITE_VERSION = "0.16.3"` which refers to the **upstream vlcn-io release** bundled with the package, not our release version. This is correct - the effect-native packages have their own versioning via changesets.
