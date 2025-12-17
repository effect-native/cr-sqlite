# Tom blocker: Effect Bun scratchpad

## What’s blocked
A third scratchpad was requested:
- `.wishes/scratchpad.md` asks for `scratch/effect-bun-scratchpad`

Creating this is **TypeScript-heavy** and (per repo rules) all TypeScript work must happen in the `effect-native/` submodule and be spec-gated.

## Constraints
- No new TypeScript projects outside `effect-native/`.
- Must follow `effect-native/.specs/AGENTS.md` and treat `effect-native/.specs/*` as source of truth.

## What Tom needs to decide
1. Where this lives (suggested): `effect-native/scratch/effect-bun-scratchpad/` (or a workspace package under `effect-native/packages-native/`)
2. Whether to write a spec first (suggested): add a minimal spec under `effect-native/.specs/` describing the scratchpad goal + run command.
3. Whether it must use:
   - `@effect/platform`, `@effect/platform-bun`, `@effect/sql`, `@effect/sql-sqlite-bun`
   - `@effect/language-service`, `@effect/vitest`, `@effect/eslint-plugin`

## Why this matters
If we do this in the root repo we violate the TS work rule, and it becomes hard to keep aligned with the spec gates.

## Added
- 2025-12-17
