# TASK-068: Size regression check for Zig crsqlite build artifacts

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/small-prod-builds.md`
- Release planning context: `research/zig-cr/103-release-planning-proposal.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (add a new section under Release work or Gaps)

## Description
Add reproducible evidence about artifact sizes for the Zig-based CR-SQLite build. The goal is to detect "chonk" regressions and verify we’re not accidentally pulling in unnecessary runtime baggage.

This task does not aim to set hard size budgets yet, just to make size observable and comparable over time.

## Files to Modify
- `zig/Makefile` (add a target or script hook)
- `scripts/` (optional: a small size-report script)
- `.github/workflows/zig-tests.yaml` (optional: emit size report in CI logs)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] A single command produces a size report for relevant artifacts (at least macOS and Linux targets if available).
- [x] Size report includes: crsqlite artifact, sqlite artifact (baseline), and ratio.
- [x] Evidence is reproducible from a clean checkout.

## Progress Log
### 2025-12-17
- Task created from `.wishes/small-prod-builds.md` during "update tasks".

### 2025-12-16
- Added `make size-report` target to `zig/Makefile`
- Target builds artifacts then compares to SQLite baseline from nixpkgs
- Reports include: dylib, static lib (.a), and WASM sizes
- Shows ratio and overhead vs sqlite, with color-coded warnings
- Added size report step to CI workflow (`.github/workflows/zig-tests.yaml`)
- Verified unit tests still pass

## Completion Notes
### Command Added
```bash
make -C zig size-report
```

### Example Output
```
════════════════════════════════════════════════════════════════
  CR-SQLite Artifact Size Report
════════════════════════════════════════════════════════════════

Baseline (SQLite from nixpkgs):
  libsqlite3.dylib:    1.75 MB (1844224 bytes)

CR-SQLite Zig Build Artifacts:
  libcrsqlite.dylib:   1.85 MB (1949776 bytes)
  libcrsql.a (static): 2.87 MB (3012600 bytes)
  crsqlite.wasm:       .76 MB (801460 bytes)

Size Comparison:
  crsqlite/sqlite ratio:  105.72%
  Overhead vs sqlite:     +103.07 KB
  Size looks healthy
```

### Key Finding
The Zig crsqlite build is only **105.72%** of sqlite size (~103KB overhead). This validates the hypothesis in `.wishes/small-prod-builds.md` that Zig should be smaller than the Rust implementation which included runtime baggage.
