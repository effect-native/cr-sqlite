# TASK-216 — Nix Release Uses Zig Artifacts + Matches Preview Version

## Goal
Ensure nix packaging for this repo produces the Zig artifacts and reports version `0.16.300-preview`.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- `flake.nix` currently builds `core/` Rust/C and has `version = "0.16.3"` and `print-version` returns `0.16.3`.

## Files to Modify
- `flake.nix`
- Any nix scripts referenced by release pipeline

## Acceptance Criteria
1. [ ] `nix build` produces Zig extension artifacts (not Rust/C)
2. [ ] `nix run .#print-version` returns `0.16.300-preview`
3. [ ] Tag-based fetch / nix usage works for released tag

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
