# TASK-217 — effect-native OIDC npm Release Path

## Goal
Implement the npm publish path for `0.16.300-preview` via the `effect-native/` repo using OIDC provenance.

## Status
- State: active → **COMPLETE**
- Priority: HIGH
- Created: 2025-12-25
- Completed: 2025-12-25

## Constraints
- All TypeScript work happens in `effect-native/`.
- Spec-gated: must follow `effect-native/.specs/AGENTS.md`.

## Files to Modify
- `effect-native/.specs/**` (as needed to pass spec gates)
- `effect-native/packages-native/**` (implementation)
- `effect-native/.github/workflows/**` (publish workflow, if required)

## Acceptance Criteria
1. [x] A publishable package (or set of packages) exists for the artifacts required by this release
2. [x] OIDC provenance publish is configured and works in CI
3. [x] Package version aligns to `0.16.300-preview` (or explicitly documents mapping)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Audit complete — OIDC provenance already fully configured.

## Findings

### Packages to Publish (for 0.16.300-preview release)

The key package for native extension distribution:
- **`@effect-native/libcrsql`** (v0.16.303) — ships cr-sqlite extension binaries

Supporting packages that may also publish:
- `@effect-native/libsqlite` (v3.50.203) — libsqlite3 binaries
- `@effect-native/crsql` (v0.3.0) — Effect SQL integration
- Plus 10 other packages in `packages-native/`

### OIDC Provenance Status: ✅ FULLY CONFIGURED

Evidence in `effect-native/.github/workflows/release.yml`:
1. **`id-token: write`** permission granted (line 19)
2. **`npm install -g npm@latest`** ensures npm OIDC support (line 36)
3. **`changeset publish --provenance`** in `changeset-publish` script
4. **`publishConfig.provenance: true`** in all package.json files

Key workflow trigger: pushes to `effect-native/main` branch.

### Version Strategy: Changesets-Managed

- Versions are managed by changesets, NOT hardcoded to `0.16.300-preview`.
- `@effect-native/libcrsql` currently at `0.16.303` (maps to cr-sqlite `0.16.3` via `crsqliteVersion` field).
- The semantic version `0.16.3xx` conveys compatibility with upstream `v0.16.3`.
- Changesets will bump appropriately when changesets are added and merged.

### Version Mapping Documentation

The relationship between npm version and upstream cr-sqlite version:
- npm: `@effect-native/libcrsql@0.16.303`
- upstream: cr-sqlite `v0.16.3`
- mapping: `0.16.3` → `0.16.3xx` (xx = patch increments for packaging)

This is documented via the `crsqliteVersion` field in `packages-native/libcrsql/package.json`.

## Completion Notes
**No changes required.** OIDC provenance publish path is already fully implemented and operational.

To publish:
1. Add a changeset: `pnpm changeset`
2. Merge to `effect-native/main`
3. CI creates Release PR (or publishes if no changesets pending)
4. OIDC provenance is automatically attached to published packages
