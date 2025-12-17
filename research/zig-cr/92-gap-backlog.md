# 92-gap-backlog

> Last updated: 2025-12-17 (Added CI health + Zig completeness tasks)

## Status

- MVP: ✅ complete (154/154 tests passing)
- Zig implementation: `zig/`
- Canonical task queue: `.tasks/{backlog,active,done}/`

## Now (next parallel assignments)

Pick disjoint tasks from `.tasks/backlog/`:

- **CI and Zig implementation health**
  - Fix GitHub Actions test failures: `.tasks/backlog/TASK-057-fix-github-actions-test-failures.md`
  - Ensure all Zig functionality fully implemented: `.tasks/backlog/TASK-058-ensure-zig-functionality-complete.md`
  - Design tests to expose unimplemented Zig functionality: `.tasks/backlog/TASK-059-design-tests-expose-unimplemented-zig.md`
  - *(Note: Local tests passing - 154/154 MVP, 52/52 parity, but CI is red)*

- **Unblock browser specs (to unblock TS work)**
  - Tom decision: browser spec naming + package boundary: `.tasks/backlog/TASK-056-tom-browser-spec-naming.md`
  - Phase 1 instructions: `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`
  - Phase 2 requirements: `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md`
  - (Then implement) Service Worker fallback: `.tasks/backlog/TASK-031-web-service-worker-fallback.md`
  - (Then implement) Reactive subscriptions: `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`

- **Upstream goodwill (blocked on Tom)**
  - Scope decision: `.tasks/backlog/TASK-055-tom-scope-upstream-feedback.md`
  - zig-sqlite feedback cards: `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

## Done (recent)

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

### CI and Zig implementation gaps

Source: GitHub Actions workflow failures + feature matrix audit

- [ ] Fix GitHub Actions test failures → `.tasks/backlog/TASK-057-fix-github-actions-test-failures.md` (2025-12-17)
- [ ] Ensure all Zig functionality fully implemented → `.tasks/backlog/TASK-058-ensure-zig-functionality-complete.md` (2025-12-17)
- [ ] Design tests to expose unimplemented Zig functionality → `.tasks/backlog/TASK-059-design-tests-expose-unimplemented-zig.md` (2025-12-17)

### Test infrastructure (previously resolved)

Source: `.tasks/DELEGATE_WORK_HANDOFF.md` (Round 34)

- [x] Fix Zig parity rowid slab failures → `.tasks/done/TASK-051-zig-parity-rowid-slab.md` (2025-12-15)
- [x] Triage + bucket browser-test failures → `.tasks/done/TASK-052-web-browser-test-triage.md` (2025-12-15, was port conflict)

### Web multi-tab (spec unblock → implementation)

Source: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`

Spec unblock (required before TS implementation):
- [ ] Tom decision: choose spec + package boundary → `.tasks/backlog/TASK-056-tom-browser-spec-naming.md`
- [ ] Phase 1 instructions (browser runtime) → `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`
- [ ] Phase 2 requirements (browser runtime) → `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md`

Implementation tasks (blocked until requirements exist):
- [ ] Service Worker fallback when SharedWorker missing → `.tasks/backlog/TASK-031-web-service-worker-fallback.md`
- [ ] Reactive subscriptions/notifications surface → `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`

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
- [ ] Phase 5: real SQLite integration + production transports (separate task once Phase 4 complete)

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
- Track release engineering tasks in `.tasks/backlog/` (create new ones as needed).
