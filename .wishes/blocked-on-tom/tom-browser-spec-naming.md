# Tom blocker: pick browser runtime spec + package boundary

## What’s blocked
All browser multi-tab work is spec-gated and currently blocked on a naming/boundary decision:
- `.tasks/backlog/TASK-056-tom-browser-spec-naming.md`

Downstream tasks blocked by this:
- `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md` (Phase 1 instructions)
- `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md` (Phase 2 requirements)
- `.tasks/backlog/TASK-031-web-service-worker-fallback.md` (implementation)
- `.tasks/backlog/TASK-032-web-reactive-subscriptions.md` (implementation)

## What Tom needs to decide
Please reply by updating `.tasks/backlog/TASK-056-tom-browser-spec-naming.md` with:
- Spec directory name under `effect-native/.specs/`
  - Example options: `crsqlite-web-multitab`, `crsql-mesh-runtime-web`, `crsqlite-browser-runtime`
- Intended npm package name(s)
  - One package vs split (coordinator / client / provider)
- One sentence boundary per package

## Why this matters
If we guess the package boundaries, we’ll write the wrong spec tree and waste a round.

## Where to look for context
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
- Spec workflow rules: `effect-native/.specs/AGENTS.md`

## Added
- 2025-12-15
