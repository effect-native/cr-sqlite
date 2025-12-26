# TASK-223 — Verify WASM Build Uses Zig 0.15

## Goal
Ensure the WASM build uses Zig 0.15 (not 0.14) and that CI/release workflows reference the correct toolchain.

## Status
- State: done
- Priority: HIGH (release blocker)
- Created: 2025-12-26
- Completed: 2025-12-26
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
1. [x] `nix run nixpkgs#zig -- version` returns 0.15.x — **Verified: 0.15.2**
2. [x] WASM build succeeds with Zig 0.15: `cd zig && nix run nixpkgs#zig -- build wasm` — **Verified: Build succeeded**
3. [x] No references to Zig 0.14 in build scripts or CI workflows — **Verified: No 0.14 references found**
4. [x] CI workflows use Zig 0.15 (or nixpkgs default which is 0.15) — **Verified: All use `nix run nixpkgs#zig`**

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`
- WASM build fix: `.tasks/done/TASK-212-fix-wasm-build-for-release.md`
- Release decision: `.wishes/blocked-on-tom/release-readiness-decision.md`

## Progress Log
- 2025-12-26: Created as release blocker per Tom's request.
- 2025-12-26: Verification complete — all criteria pass.

## Completion Notes
**Date:** 2025-12-26

### Verification Results

1. **Zig Version**: `nix run nixpkgs#zig -- version` → **0.15.2** ✓

2. **WASM Build**: `cd zig && nix run nixpkgs#zig -- build wasm` → **Succeeded** ✓
   - Output artifacts:
     - `libcrsqlite.a` (5.26 MB) — static library for embedding
     - `crsqlite.wasm` (5.26 MB) — standalone WASM object

3. **No 0.14 References**: Searched across all relevant files:
   - `zig/build.zig` — clean
   - `zig/wasm-build/build-sqlite-wasm.sh` — clean  
   - `.github/workflows/zig-tests.yaml` — clean
   - `.github/workflows/publish.yaml` — clean
   - `flake.nix` — clean

4. **CI Workflow Verification**:
   - `zig-tests.yaml`: Uses `nix run nixpkgs#zig` (nixpkgs default = 0.15.2)
   - `publish.yaml`: Uses `nix run nixpkgs#zig` (nixpkgs default = 0.15.2)
   - No hardcoded Zig version overrides

### Conclusion
The WASM build correctly uses Zig 0.15.2 from nixpkgs. All CI and release workflows use the nixpkgs default Zig, which is 0.15.2. No legacy 0.14 references exist in the codebase.

**Release Blocker Status**: RESOLVED — WASM toolchain is on Zig 0.15.
