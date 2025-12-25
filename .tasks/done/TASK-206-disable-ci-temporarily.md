# TASK-206 — Disable CI Temporarily

## Goal
Disable GitHub Actions CI workflows until we're closer to public release.

## Status
- State: done
- Priority: HIGH (CI noise is distracting)
- Created: 2025-12-25
- Completed: 2025-12-25

## Context
CI is failing on:
1. WASM build (Zig 0.14 incompatibility - we only support latest Zig)
2. macOS nix install (transient GitHub Actions issue)
3. Some parity tests that depend on Rust/C oracle not available on Linux

These failures are noise. The core functionality works (verified locally on darwin). We'll re-enable CI when approaching public release.

## Files to Modify
- `.github/workflows/zig-tests.yaml` — Disable or skip

## Acceptance Criteria
1. [x] CI workflows disabled (renamed or paths changed to not trigger)
2. [x] No more failing CI notifications

## Parent Docs / Cross-links
- Blocked task: `.tasks/backlog/TASK-207-reenable-ci-for-release.md`
- Release decision: `.wishes/blocked-on-tom/release-readiness-decision.md`

## Progress Log
- 2025-12-25: Created per Tom's direction.

## Completion Notes
- 2025-12-25: Disabled CI by changing trigger paths in `.github/workflows/zig-tests.yaml`
- Changed `zig/**` to `disabled-zig-ci-trigger/**` so workflows won't trigger
- Added comments explaining why and how to re-enable
