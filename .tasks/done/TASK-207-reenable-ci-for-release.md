# TASK-207 — Re-enable CI for Public Release

## Goal
Re-enable GitHub Actions CI when approaching public release.

## Status
- State: backlog
- Priority: LOW (requires execution; decision made)
- Blocked by: (none)
- Created: 2025-12-25

## Context
CI was disabled (TASK-206) because:
1. WASM build requires Zig 0.14 compat (we only support latest Zig 0.15+)
2. Some tests depend on Rust/C oracle not available in CI
3. macOS GitHub Actions has transient nix install issues

Before re-enabling, we need to:
1. Implement WASM build (required for release)
2. Set up oracle binaries in CI (or skip oracle-dependent tests)
3. Fix any remaining platform-specific issues

## Files to Modify
- `.github/workflows/zig-tests.yaml` — Re-enable and fix

## Acceptance Criteria
1. [x] Release readiness decision made (see blocked-on-tom wish)
2. [x] CI passes on Linux (ubuntu-latest)
3. [x] CI passes on macOS (macos-latest)
4. [x] WASM build passes

## Parent Docs / Cross-links
- Disabling task: `.tasks/done/TASK-206-disable-ci-temporarily.md` (after completion)
- Release decision: `.wishes/blocked-on-tom/release-readiness-decision.md`
- Oracle strategy: `.tasks/active/TASK-214-ci-oracle-strategy.md`

## Progress Log
- 2025-12-25: Created, blocked on release decision.
- 2025-12-25: Tom decided: scope = Native + WASM + Browser; version = `0.16.300-preview`; distribution = npm (effect-native) + GitHub Releases + nix tags; docs = none for preview.
- 2025-12-25: Re-enabled CI workflow. Implemented split strategy (TASK-214).

## Completion Notes
CI re-enabled in `.github/workflows/zig-tests.yaml`:

**Trigger paths restored:**
- `zig/**`, `lib/**`, `.github/workflows/zig-tests.yaml`

**Required jobs (must pass for release):**
- `build-native` (Linux + macOS matrix)
- `build-wasm` (WASM target)
- `test-unit` (Zig unit tests)
- `test-parity-zig-only` (23 Zig-only parity tests)
- `test-browser` (Playwright browser tests)
- `release-gate` (aggregates all required jobs)

**Optional job (informational):**
- `test-parity-oracle` (`continue-on-error: true`, runs `make test-parity`)

The `release-gate` job aggregates all required checks for branch protection.

**Testing note:** The workflow uses Nix to install Zig (`nix run nixpkgs#zig`),
which avoids issues with GitHub Actions' Zig installation on macOS.
