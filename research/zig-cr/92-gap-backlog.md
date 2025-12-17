# 92-gap-backlog

> Last updated: 2025-12-16 (Round 38 — Browser migration F13-F14 + Phase 5 + Size report)

## Status

- MVP: ✅ complete (154/154 tests passing)
- Zig implementation: `zig/`
- Canonical task queue: `.tasks/{backlog,active,done}/`

## Now (next parallel assignments)

Pick disjoint tasks from `.tasks/backlog/`:

- **Tests now green**
  - Zig parity: 52/52 passing (TASK-051 done)
  - Browser tests: 18/18 passing (TASK-052 done — was port conflict, not code bug)
  - Mesh tests: 81/81 passing (Round 38 — F13-F14 + Phase 5 integration)

- **Browser Multi-Tab Implementation (Round 37 — complete)**
  - ✅ Browser foundation F5-F8: `.tasks/done/TASK-063-browser-multitab-foundation.md`
    - Coordinator + Provider classes
    - 9 coordinator tests, 14 provider tests
  - ✅ Browser specs: `.tasks/done/TASK-053-spec-browser-runtime-phase1.md`, `.tasks/done/TASK-054-spec-browser-runtime-phase2.md`
  - ✅ Reactive subscriptions F9-F10: `.tasks/done/TASK-032-web-reactive-subscriptions.md`
    - db_version notification broadcast from provider to clients
    - 8 new tests (4 coordinator, 4 provider)
  - ✅ Service Worker fallback F11-F12: `.tasks/done/TASK-031-web-service-worker-fallback.md`
    - ServiceWorkerCoordinator class
    - 12 new tests

- **Upstream goodwill (de-prioritized)**
  - Scope decision (later): `.tasks/backlog/TASK-055-tom-scope-upstream-feedback.md`
  - zig-sqlite feedback cards (later): `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

## Done (recent)

- **Unified mesh specs** (2025-12-16)
  - Mesh requirements unified: `.tasks/done/TASK-057-unify-mesh-requirements.md` — Protocol, transport, runtime, browser multi-tab requirements consolidated
  - Mesh design unified: `.tasks/done/TASK-058-unify-mesh-design.md` — Browser multi-tab design sketch added
  - Mesh plan unified: `.tasks/done/TASK-059-unify-mesh-plan.md` — Browser multi-tab RGRTDD slices added
  - Redirect notices: `.tasks/done/TASK-060-redirect-protocol-spec.md`, `.tasks/done/TASK-061-redirect-transport-spec.md`, `.tasks/done/TASK-062-redirect-runtime-spec.md`

- **Mesh Phase 4 implementation complete** (2025-12-15)
  - Protocol schema reuse: `.tasks/done/TASK-048-crsql-mesh-protocol-schema-reuse.md` — Types now re-exported from CrSqlSchema, 26 tests pass
  - Mesh engine: `.tasks/done/TASK-049-crsql-mesh-engine-phase4.md` — Receive loop, periodic sync, diff exchange, transactional apply, progress observation, 23 tests pass
  - Node runtime: `.tasks/done/TASK-050-crsql-mesh-runtime-node-phase4.md` — DB open, CR-SQLite load, protocol init, lifecycle hooks, 11 tests pass

- **Round 33 assessment** (2025-12-15)
  - No delegation: `.tasks/DELEGATE_WORK_HANDOFF.md`
  - Tests status: mesh tests green, TS check green, Zig parity failing (rowid slab) per Round 33

- **Mesh packages (Phase 4 scaffolding + partial implementation)** (2025-12-14)
  - `@effect-native/crsql-mesh-transport` — Transport tag + deterministic InMemoryTransport (good)
- **Mesh Phase 2 requirements (node-first)**: `.tasks/done/TASK-046-phase2-requirements-crsql-mesh.md` (2025-12-14)
- **Mesh Phase 3 designs + Phase 4 RGRTDD plans**: `effect-native/.specs/crsql-mesh/plan.md` (2025-12-15)
- **Mesh protocol Phase 4 RGRTDD plan**: `effect-native/.specs/crsql-mesh-protocol/plan.md` (2025-12-15)
- **Mesh transport Phase 4 RGRTDD plan**: `effect-native/.specs/crsql-mesh-transport/plan.md` (2025-12-15)
- **Mesh runtime (node) Phase 4 RGRTDD plan**: `effect-native/.specs/crsql-mesh-runtime/plan.md` (2025-12-15)
- **Phase 1 RN runtime specs**: `.tasks/done/TASK-047-phase1-react-native-runtime-specs.md` (2025-12-14)
- **Mobile static embedding guide**: `.tasks/done/TASK-033-mobile-static-embedding-guide.md` → `research/zig-cr/104-mobile-static-embedding-guide.md` (2025-12-14)
- Perf hotspots: `.tasks/done/TASK-029-performance-hotspot-closure.md`
- macOS universal: `.tasks/done/TASK-026-A-macos-universal-binary.md`
- Windows `.dll`: `.tasks/done/TASK-030-windows-dll-build.md`
- Zig npm packaging: `.tasks/done/TASK-034-npm-package-zig-native.md`
- Release planning proposal: `.tasks/done/TASK-036-release-planning-proposal.md` → `research/zig-cr/103-release-planning-proposal.md`

## Gaps (only what’s still open)

- WASM baked-in extensions (sqlite-vec / FTS / BJSON): `.tasks/backlog/TASK-067-zig-wasm-baked-in-extensions.md`
- Scratchpad demos wiring: `.tasks/backlog/TASK-069-wire-scratchpads.md`

### Test infrastructure (resolved)

Source: `.tasks/DELEGATE_WORK_HANDOFF.md` (Round 34)

- [x] Fix Zig parity rowid slab failures → `.tasks/done/TASK-051-zig-parity-rowid-slab.md` (2025-12-15)
- [x] Triage + bucket browser-test failures → `.tasks/done/TASK-052-web-browser-test-triage.md` (2025-12-15, was port conflict)

### Web multi-tab (spec unblock → implementation)

Source: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`

Spec unblock (completed 2025-12-16 Round 35):
- [x] Tom decision: choose spec concept + defer boundaries → `.tasks/done/TASK-056-tom-browser-spec-naming.md`
- [x] Unify mesh requirements (including browser multi-tab EARS) → `.tasks/done/TASK-057-unify-mesh-requirements.md`
- [x] Unify mesh design (including browser multi-tab sketch) → `.tasks/done/TASK-058-unify-mesh-design.md`
- [x] Unify mesh plan (delegation-friendly RGRTDD) → `.tasks/done/TASK-059-unify-mesh-plan.md`

Spec redirects (completed 2025-12-16 Round 35):
- [x] Redirect protocol spec → `.tasks/done/TASK-060-redirect-protocol-spec.md`
- [x] Redirect transport spec → `.tasks/done/TASK-061-redirect-transport-spec.md`
- [x] Redirect runtime spec → `.tasks/done/TASK-062-redirect-runtime-spec.md`

Note: per Tom (2025-12-16), browser multi-tab specs land in the unified full product spec under `effect-native/.specs/crsql-mesh/` and boundaries/names are deferred until they block progress (see `research/thing-golf.md`).

Foundation (completed Round 36):
- [x] Coordinator + Provider foundation (F5-F8) → `.tasks/done/TASK-063-browser-multitab-foundation.md`

Implementation tasks (completed Round 37):
- [x] Reactive subscriptions F9-F10 → `.tasks/done/TASK-032-web-reactive-subscriptions.md`
- [x] Service Worker fallback F11-F12 → `.tasks/done/TASK-031-web-service-worker-fallback.md`

Implementation tasks (completed Round 38):
- [x] Provider migration F13-F14 → `.tasks/done/TASK-064-browser-multitab-provider-migration.md`
  - 12 new tests (5 coordinator migration, 7 provider idempotency)
  - Idempotent write guard via txId

Remaining browser multi-tab work:
- [ ] Browser integration polish F15 → `.tasks/backlog/TASK-065-browser-multitab-integration-polish.md`

Note: TS work is spec-gated under `effect-native/.specs/AGENTS.md`.

### Global mesh (Phase 4 implementation complete)

Source: `research/zig-cr/102-proposal-crsqlite-global-mesh.md` and `effect-native/.specs/crsqlite-global-mesh-packages/instructions.md`

Spec artifacts:
- [x] Phase 1 instructions: `.tasks/done/TASK-039-spec-global-mesh-package-map.md`
- [x] Phase 2 requirements: `.tasks/done/TASK-046-phase2-requirements-crsql-mesh.md`
- [x] Phase 3 designs: `effect-native/.specs/crsql-mesh*/design.md`
- [x] Phase 4 plans: `effect-native/.specs/crsql-mesh*/plan.md`

Implementation (Phase 4 complete):
- [x] Protocol: schema type reuse from CrSqlSchema → `.tasks/done/TASK-048-crsql-mesh-protocol-schema-reuse.md`
- [x] Mesh engine: anti-entropy loop + transactional apply → `.tasks/done/TASK-049-crsql-mesh-engine-phase4.md`
- [x] Node runtime: DB open + CR-SQLite extension load + lifecycle hooks → `.tasks/done/TASK-050-crsql-mesh-runtime-node-phase4.md`
- [x] Phase 5: real SQLite integration evidence → `.tasks/done/TASK-066-mesh-phase5-real-sqlite-integration.md` (Round 38)
  - 3 new integration tests proving mesh diff/apply logic works with MeshDatabase interface

### Mobile static embedding docs

Source: `research/zig-cr/93-phased-execution-proposal.md`

- [x] iOS/Android static embedding guide → `research/zig-cr/104-mobile-static-embedding-guide.md` (done 2025-12-14)

### Upstream feedback capture (optional)

Source wish: `.wishes/gather-upstream-feedback.md`

- [ ] Tom scope decision → `.tasks/backlog/TASK-055-tom-scope-upstream-feedback.md`
- [ ] Collect zig-sqlite improvement ideas as blocked-on-tom cards → `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

## Release work

Source: `research/zig-cr/103-release-planning-proposal.md`

- Zig artifacts exist for macOS; Linux CI + platform packages are the next shipping blockers.
- [x] Size regression observability: `.tasks/done/TASK-068-zig-artifact-size-regression.md` (Round 38)
  - `make -C zig size-report` command
  - Zig crsqlite is only 105.72% of SQLite size (~103KB overhead)
- Track release engineering tasks in `.tasks/backlog/` (create new ones as needed).
