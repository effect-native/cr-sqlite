# Tom: Review `crsql-mesh*` Phase-1 specs + choose the smallest safe next slice

You’re the only person who can unblock Phase 2.

Goal: reduce future ThingBadness by making a few crisp decisions up front (fewer packages, fewer knobs, clearer boundaries).

## What to read (Phase 1 only)

Start here:
- [`effect-native/.specs/crsqlite-global-mesh-packages/instructions.md`](../../effect-native/.specs/crsqlite-global-mesh-packages/instructions.md)

Then read these (the actual `crsql-*` set):
- [`effect-native/.specs/crsql-mesh/instructions.md`](../../effect-native/.specs/crsql-mesh/instructions.md)
- [`effect-native/.specs/crsql-mesh-protocol/instructions.md`](../../effect-native/.specs/crsql-mesh-protocol/instructions.md)
- [`effect-native/.specs/crsql-mesh-transport/instructions.md`](../../effect-native/.specs/crsql-mesh-transport/instructions.md)
- [`effect-native/.specs/crsql-mesh-runtime/instructions.md`](../../effect-native/.specs/crsql-mesh-runtime/instructions.md)
- [`effect-native/.specs/crsql-mesh-integration/instructions.md`](../../effect-native/.specs/crsql-mesh-integration/instructions.md)

Context proposals:
- [`research/zig-cr/102-proposal-crsqlite-global-mesh.md`](../../research/zig-cr/102-proposal-crsqlite-global-mesh.md)
- Upstream reference (read-only):
  - [`../../.refs/effect/packages/sql/`](../../.refs/effect/packages/sql/)
  - [`../../.refs/effect/packages/sql-sqlite-bun/`](../../.refs/effect/packages/sql-sqlite-bun/)

## Decisions (please answer each checkbox)

### A) Name alignment (reduces chaos)
- [ ] **Package name**: pick one canonical name for the core engine: `@effect-native/crsql-mesh` vs `@effect-native/crsql-mesh-core` (some docs currently use both).

### B) Smallest “first ship” package set (reduces burden)
Pick the smallest set of NEW packages we implement first (no bikeshedding, just pick):
- [ ] Option 1 (smallest): protocol + transport interface + core engine
- [ ] Option 2 (practical web-first): Option 1 + browser runtime adapter
- [ ] Option 3 (practical node-first): Option 1 + node runtime adapter

### C) Runtime split decisions (reduces control-freak knobs)
- [ ] Bun: separate `@effect-native/crsql-mesh-runtime-bun` package, or fold into `...-runtime-node`
- [ ] Electron: separate `...-runtime-electron`, or explicitly defer

### D) `@effect-native/crsql` boundary (reduces future betrayals)
Where do the “db primitives” stop and “sync orchestration” start?
- [ ] Confirm the split: `@effect-native/crsql` owns typed change rows + pull/apply helpers; mesh package owns version vectors + anti-entropy loop.

### E) Approval gate
- [ ] Approved to proceed to **Phase 2 (requirements.md)** for the chosen packages under `effect-native/.specs/AGENTS.md`.

## Notes

Thing-golf bias:
- Prefer fewer packages first.
- Prefer fewer configuration knobs.
- Prefer boundaries that keep `@effect-native/crsql` useful standalone.

## When you’re done

- Move this file to `.wishes/done/` and add a short “Decisions” summary.
- Then we’ll generate Phase 2 `requirements.md` for exactly the packages you approved.
