# TASK-038: Add Effect submodules + TS-work rule (unblock TypeScript)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/effect-native.md`
- Repo submodules file: `.gitmodules`
- Agent rules: `AGENTS.md`

## Description
Add the submodules required for TypeScript work and codify the rule that **all TS work lives in the `effect-native/` submodule**, following the spec-first workflow defined by `effect-native/.specs/AGENTS.md`.

Submodules to add:
- References:
  - `git@github.com:Effect-TS/effect.git`
  - `git@github.com:Effect-TS/effect-smol.git`
- Work:
  - `git@github.com:effect-native/effect-native.git`

Then update `AGENTS.md` with a clear rule:
- TypeScript work happens only in `effect-native/`
- For TS changes, agents must read and follow `effect-native/.specs/AGENTS.md`

## Files to Modify
- `.gitmodules`
- `AGENTS.md`
- (new directories created by git submodule add)

## Acceptance Criteria
- [x] `git submodule status` shows all three submodules present.
- [x] `AGENTS.md` documents the TS-work rule and points at `effect-native/.specs/AGENTS.md`.
- [x] Existing non-TS tasks remain valid (no churn).

## Progress Log
### 2025-12-14
- Task created from `.wishes/effect-native.md`
- Subagent began work: marked In Progress
- Added `.refs/effect` submodule
- Added `.refs/effect-smol` submodule
- Added `effect-native` submodule
- Updated `AGENTS.md` with TypeScript Work Rule section
- Verified all acceptance criteria met
- Task complete

## Completion Notes
### 2025-12-14
- Added three git submodules:
  - `.refs/effect` (Effect-TS/effect @ fb78c4061cec89718c49f842a91263a9bb8cf3cf)
  - `.refs/effect-smol` (Effect-TS/effect-smol @ e0e47d38139e9f182908dc6f26125d59ad0f1219)
  - `effect-native` (effect-native/effect-native @ 9f6ce02ea21e81110df4ebd2c80f863fdc0173fb)
- Updated `AGENTS.md` with new "TypeScript Work Rule" section directing all TS work to `effect-native/` submodule
- Verified `effect-native/.specs/AGENTS.md` exists for spec-first workflow reference
