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
- [x] **Package name**: pick one canonical name for the core engine: `@effect-native/crsql-mesh`

### B) Smallest “first ship” package set (reduces burden)
Pick the smallest set of NEW packages we implement first (no bikeshedding, just pick):
- [x] Option 3 (practical node-first): Option 1 + node runtime adapter

### C) Runtime split decisions (reduces control-freak knobs)
- Bun: separate `@effect-native/crsql-mesh-runtime-bun` package? fold into `...-runtime-node` with @effect/package-{node,but,browser} as possible; add a -bun specific package only if necessary
- No Electron. I don't like Electron. I refuse to support it

### D) `@effect-native/crsql` boundary (reduces future betrayals)
Where do the “db primitives” stop and “sync orchestration” start?
- Confirm the split: `@effect-native/crsql` owns typed change rows + pull/apply helpers; mesh package owns version vectors + anti-entropy loop.

### E) Approval gate
- Approved to proceed to **Phase 2 (requirements.md)** for the chosen packages under `effect-native/.specs/AGENTS.md`.

## Notes

Thing-golf bias:
- Prefer fewer packages first.
- Prefer fewer configuration knobs.
- Prefer boundaries that keep `@effect-native/crsql` useful standalone.

## When you’re done

- Move this file to `.wishes/done/` and add a short “Decisions” summary.
- Then we’ll generate Phase 2 `requirements.md` for exactly the packages you approved.


---

From Tom:

- updated effect-native/.specs/crsqlite-global-mesh-packages/instructions.md with
  - package names for new react-native packages

- effect-native/.specs/crsql-mesh/instructions.md approved

- TODO: Agent, update effect-native/.specs/crsql-mesh-protocol/instructions.md to reference the existing effect-native/packages-native/crsql/ that already includes a lot of stuff that makes serialization/de-serialization much simpler and cleaner. Pay particular attention to effect-native/packages-native/crsql/src/CrSqlSchema.ts and its effect-native/packages-native/crsql/test/

Product decision: rely on SQLite's unhex() (available in sqlite >= 3.50.2).
If unhex() is missing or disabled in the host, we fail fast with UnhexUnavailable rather than adding feature-detection fallbacks.
NOTE: verifying unhex() presence as early as possible in layer creation so that it'll be easier to know when there's a configuration issue

- TODO(Agent): add specs for react-native packages

- @effect-native/crsql-mesh-runtime-node should rely on @effect/platform

## Decisions Summary (for agents)
- Core engine package name: `@effect-native/crsql-mesh`
- First ship slice: protocol + transport interface + core engine + runtime-node
- Bun: fold into runtime-node unless proven necessary
- Electron: out of scope
- Protocol: reuse `@effect-native/crsql` schemas; require SQLite `unhex()`; fail fast with `UnhexUnavailable`
