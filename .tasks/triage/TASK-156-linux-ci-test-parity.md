# TASK-156 — Linux CI + test parity (not just Darwin)

## Goal
Make sure our build + test workflows run on Linux (CI + local), not only Darwin.

## Status
- State: triage
- Priority: high

## Context
We have strong Darwin coverage (local dev + artifacts), but Linux can silently rot unless we exercise it regularly.

This task adds/strengthens Linux execution for the same “canonical” test entrypoints we trust on macOS.

## Files to Modify
(Keep scope tight; expand only when necessary.)
- `.github/workflows/*` (add/adjust Linux jobs for the canonical test entrypoints)
- `flake.nix` / `flake.lock` (if Linux nix deps or build inputs differ)
- `zig/harness/test-*.sh` (fix Darwin-only assumptions: GNU vs BSD tools, paths, dylib/so, etc.)
- `Makefile` / `zig/Makefile` (if targets assume Darwin)
- `scripts/build-linux-docker.sh` (if it becomes the canonical Linux pathway)

## Acceptance Criteria
1. CI coverage
   - At least one GitHub Actions workflow runs the canonical test suite on `ubuntu-latest`.
   - The Linux job uses deterministic provisioning (prefer `nix`), not ad-hoc apt installs.

2. Canonical commands pass on Linux
   - From a clean checkout on Linux, the documented/canonical commands complete successfully:
     - `nix build` (or repo’s canonical build target)
     - `make test` / `make -C zig test-parity` (whichever is canonical for this repo)
   - No harness emits `SKIP:` / `SKIPPED:` and exits 0.

3. Cross-platform script hygiene
   - Any bash scripts used by CI (esp. `zig/harness/test-*.sh`) run on both Darwin + Linux.
   - OS/tooling differences are handled explicitly (e.g. GNU `sed` vs BSD `sed`, `mktemp`, `realpath`, `uname`, `.dylib` vs `.so`).

4. Repro notes captured
   - The task completion notes include the exact commands to reproduce Linux results locally.

## Parent Docs / Cross-links
- `.github/workflows/` (current CI coverage)
- `AGENTS.md` (Zig testing policy; nix usage; sqlite-cr wrapper constraints)
- `.tasks/done/TASK-144-cross-platform-compat-no-skip.md` (related “no skip” posture)
- `.tasks/triage/TASK-146-fail-fast-loud-harness.md` (harness discipline: failures must fail)
- `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-21: Created from request to ensure Linux coverage.

## Completion Notes
(Empty until done.)
