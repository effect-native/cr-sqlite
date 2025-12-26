# TASK-223 — Verify WASM Build Uses Zig 0.15

## Goal
Ensure the WASM build uses Zig 0.15 (not 0.14) and that CI/release workflows reference the correct toolchain.

## Status
- State: triage
- Priority: HIGH (release blocker)
- Created: 2025-12-26
- Triggered by: Tom's request to verify WASM toolchain version

## Context
The release scope for `0.16.300-preview` includes Native + WASM + Browser. Round 77 fixed WASM build compatibility for Zig 0.15 (TASK-212), but we need to verify:
1. The WASM build actually uses Zig 0.15 (not 0.14)
2. CI workflows reference Zig 0.15
3. Build scripts don't have hardcoded 0.14 references

## Files to Verify
- `zig/build.zig` — WASM target configuration
- `zig/wasm-build/build-sqlite-wasm.sh` — WASM build script
- `.github/workflows/zig-tests.yaml` — CI workflow
- `.github/workflows/publish.yaml` — Release workflow
- `flake.nix` — Nix toolchain version

## Acceptance Criteria
1. [ ] `nix run nixpkgs#zig -- version` returns 0.15.x
2. [ ] WASM build succeeds with Zig 0.15: `cd zig && nix run nixpkgs#zig -- build wasm`
3. [ ] No references to Zig 0.14 in build scripts or CI workflows
4. [ ] CI workflows use Zig 0.15 (or nixpkgs default which is 0.15)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`
- WASM build fix: `.tasks/done/TASK-212-fix-wasm-build-for-release.md`
- Release decision: `.wishes/blocked-on-tom/release-readiness-decision.md`

## Progress Log
- 2025-12-26: Created as release blocker per Tom's request.

## Completion Notes
(Empty until done.)
