# TASK-216 — Nix Release Uses Zig Artifacts + Matches Preview Version

## Goal
Ensure nix packaging for this repo produces the Zig artifacts and reports version `0.16.300-preview`.

## Status
- State: done
- Priority: HIGH
- Created: 2025-12-25
- Completed: 2025-12-25

## Context / Evidence
- `flake.nix` currently builds `core/` Rust/C and has `version = "0.16.3"` and `print-version` returns `0.16.3`.

## Files to Modify
- `flake.nix`
- Any nix scripts referenced by release pipeline

## Acceptance Criteria
1. [x] `nix build` produces Zig extension artifacts (not Rust/C)
2. [x] `nix run .#print-version` returns `0.16.300-preview`
3. [ ] Tag-based fetch / nix usage works for released tag (requires actual tag to test)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Rewrote `flake.nix` to build from `zig/` using Zig instead of Rust/C.

## Completion Notes
- Removed rust-overlay and sqlite-rs-embedded inputs (no longer needed)
- Changed build to use `zig build -Doptimize=ReleaseFast -p $out` in `zig/` directory
- Set `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LOCAL_CACHE_DIR` to `$TMPDIR` for Nix sandbox compatibility
- Renamed output from `libcrsqlite.dylib` → `crsqlite.dylib` for legacy naming consistency
- Verified: `result/lib/crsqlite.dylib` exists (2.7MB Zig build vs ~15MB Rust build)
- Verified: `nix run .#print-version` returns `0.16.300-preview`
- Verified: Extension loads and responds to `crsql_version()` (returns `0.0.1-zig-scaffold`)
