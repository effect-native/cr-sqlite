# TASK-217 — effect-native OIDC npm Release Path

## Goal
Implement the npm publish path for `0.16.300-preview` via the `effect-native/` repo using OIDC provenance.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Constraints
- All TypeScript work happens in `effect-native/`.
- Spec-gated: must follow `effect-native/.specs/AGENTS.md`.

## Files to Modify
- `effect-native/.specs/**` (as needed to pass spec gates)
- `effect-native/packages-native/**` (implementation)
- `effect-native/.github/workflows/**` (publish workflow, if required)

## Acceptance Criteria
1. [ ] A publishable package (or set of packages) exists for the artifacts required by this release
2. [ ] OIDC provenance publish is configured and works in CI
3. [ ] Package version aligns to `0.16.300-preview` (or explicitly documents mapping)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
