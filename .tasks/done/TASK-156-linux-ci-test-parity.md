# TASK-156 — Linux CI + test parity (not just Darwin)

## Goal
Make sure our build + test workflows run on Linux (CI + local), not only Darwin.

## Status
- State: active
- Priority: HIGH (CI is broken)

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
- 2025-12-22: Update tasks evaluation — waiting for Tom direction on CI priorities.
- 2025-12-23: Tom requested Linux CI support. Analyzed CI failures:
  - CI uses `setup-zig@v2` with Zig 0.14.0
  - Makefile uses `nix run nixpkgs#zig` which is Zig 0.15.2
  - Version mismatch causes extension to load but functions return empty
  - Also 2 failing unit tests in `clset_vtab.zig` (edge case: "_schema" alone)
  - WASM build fails due to Zig 0.14 incompatibility
- 2025-12-25: Deep investigation of Linux parity test failures:
  - CI run 20506960231 shows parity tests returning empty values on Linux
  - Unit tests PASS (same process), parity tests FAIL (cross-process via shell)
  - Extension loads successfully (no "no such function" errors)
  - Functions return empty instead of expected values
  - Root cause investigation: global variable visibility in shared library
  - Added diagnostic logging to `zig/src/ffi/init.zig` (via CRSQL_DEBUG=1)
  - Added API initialization checks in `site_identity.zig` functions
  - Added diagnostic step to CI workflow to surface errors

## Fixes Applied
1. **CI Workflow**: Updated `.github/workflows/zig-tests.yaml` to use nix for zig consistently
   - All jobs now use `nix run nixpkgs#zig --` instead of raw `zig`
   - Ensures same Zig version (0.15.2) across CI and local dev
   - Updated cache keys to `zig-nix-*`

2. **Unit Test Fix**: Fixed `endsWithSchema()` in `zig/src/clset_vtab.zig`
   - Changed `name.len < suffix.len` to `name.len <= suffix.len`
   - Prevents "_schema" alone from being considered valid (empty base name)

3. **Diagnostic Logging**: Added debug output to init.zig (2025-12-25)
   - Enable with `CRSQL_DEBUG=1` environment variable
   - Logs each initialization step and any failures
   - Added API initialization checks in UDF implementations

4. **CI Diagnostics**: Added "Diagnose extension loading" step
   - Runs before parity tests to surface extension load issues
   - Shows file info, sqlite version, and basic function tests

## Investigation Status (2025-12-25)
**Root cause suspected:** Global variable `sqlite3_api` in `sqlite_c.zig` may not be
properly shared across shared library boundaries on Linux. The symptom is:
- Extension init completes successfully (unit tests pass)
- But when SQLite calls the UDF, the global `sqlite3_api` may be uninitialized
- This causes `result_int64()` to silently do nothing (null API pointer check)

**Next steps:**
1. Run CI to capture diagnostic output
2. If API is null in UDF context, need to investigate Zig's shared library symbol visibility
3. May need to change global variable to use `export` or different storage class

## Completion Notes
- 2025-12-25: CI disabled per TASK-206 (Tom's direction)
- Linux parity tests show 343/388 passing on CI (vs 362/387 on darwin)
- Failures are oracle-dependent tests (fract, trigger) that need Rust/C binary
- Core sync functionality works on Linux (rows_impacted, basic ops all pass)
- Will re-enable CI when approaching release (TASK-207)
