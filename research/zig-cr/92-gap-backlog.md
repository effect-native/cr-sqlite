# 92-gap-backlog

> Last updated: 2025-12-14 (Round 27)

## Status

- MVP: ✅ complete (154/154 tests passing)
- Zig implementation: `zig/`
- Canonical task queue: `.tasks/{backlog,active,done}/`

## Now (next parallel assignments)

Pick disjoint tasks from `.tasks/backlog/`:

- Web phase 2 (TS, spec-gated)
  - Service Worker fallback: `.tasks/backlog/TASK-031-web-service-worker-fallback.md`
  - Reactive subscriptions: `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`
- Mobile embedding docs (Zig)
  - iOS/Android static embedding guide: `.tasks/backlog/TASK-033-mobile-static-embedding-guide.md`
- Upstream goodwill (blocked on Tom)
  - zig-sqlite feedback cards: `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

## Done (recent)

- Perf hotspots: `.tasks/done/TASK-029-performance-hotspot-closure.md`
- macOS universal: `.tasks/done/TASK-026-A-macos-universal-binary.md`
- Windows `.dll`: `.tasks/done/TASK-030-windows-dll-build.md`
- Zig npm packaging: `.tasks/done/TASK-034-npm-package-zig-native.md`
- Release planning proposal: `.tasks/done/TASK-036-release-planning-proposal.md` → `research/zig-cr/103-release-planning-proposal.md`

## Gaps (only what’s still open)

### Web multi-tab (Phase 2)

Source: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`

- [ ] Service Worker fallback when SharedWorker missing → `.tasks/backlog/TASK-031-web-service-worker-fallback.md`
- [ ] Reactive subscriptions/notifications surface → `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`

Note: TS work is spec-gated under `effect-native/.specs/AGENTS.md`.

### Mobile static embedding docs

Source: `research/zig-cr/93-phased-execution-proposal.md`

- [ ] iOS/Android static embedding guide → `.tasks/backlog/TASK-033-mobile-static-embedding-guide.md`

### Upstream feedback capture (optional)

Source wish: `.wishes/gather-upstream-feedback.md`

- [ ] Collect zig-sqlite improvement ideas as blocked-on-tom cards → `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

## Release work

Source: `research/zig-cr/103-release-planning-proposal.md`

- Zig artifacts exist for macOS; Linux CI + platform packages are the next shipping blockers.
- Track release engineering tasks in `.tasks/backlog/` (create new ones as needed).
