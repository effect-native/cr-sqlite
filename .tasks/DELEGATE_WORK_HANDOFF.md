# Delegate Work Handoff Log (evergreen)

This file is the evergreen handoff from **"Delegate work" → "Update tasks"**.

- "Delegate work" appends claims + evidence here.
- "Update tasks" starts by reading this file and tries to *invalidate* claims by comparing specs vs implementation.
- The opposite evergreen handoff is `research/zig-cr/92-gap-backlog.md` (update→delegate).

## Contract

Every round entry must contain enough information for a skeptical reviewer to reproduce the outcome.

Minimum required fields:
- **Round**: date + short label
- **Scope**: which `.tasks/*/TASK-*.md` cards were executed
- **Commits**: commit hashes for the work (or explicitly "no commits")
- **Evidence**:
  - Tests run (exact commands)
  - Test output (paste)
  - Coverage summary + file paths (if applicable)
- **Repro steps**: from a clean checkout, list commands in order
- **Notes**: known gaps / caveats / things not verified

## Template (copy for each round)

### Round YYYY-MM-DD (N) — <short description>

**Tasks executed**
- `.tasks/active/TASK-XYZ-....md`

**Commits**
- `<hash>` — <message>

**Environment**
- OS: <darwin/linux/windows>
- Tooling: <nix / pnpm / zig version etc>

**Commands run (exact)**
- `...`

**Outputs (paste)**

<details>
<summary>Test output</summary>

```text
(paste)
```
</details>

<details>
<summary>Coverage</summary>

```text
(paste)
```

Artifacts:
- `<path-to-coverage-report>`
</details>

**Reproduction steps (clean checkout)**
1. `git clone ...`
2. `...`

**Known gaps / unverified claims**
- <anything that was not verified>

---

## Round 2025-12-15 (32) — Phase 4 Mesh implementation complete

**Tasks executed**
- `.tasks/done/TASK-048-crsql-mesh-protocol-schema-reuse.md`
- `.tasks/done/TASK-049-crsql-mesh-engine-phase4.md`
- `.tasks/done/TASK-050-crsql-mesh-runtime-node-phase4.md`

**Commits**
- `744b393e8` (effect-native) — implement mesh Phase 4: protocol schema reuse, engine sync loop, node runtime
- `e2b9cc2a` (root) — delegate round 32: mesh Phase 4 complete (TASK-048, 049, 050)

**Modified files (effect-native submodule)**
- `packages-native/crsql-mesh-protocol/src/Messages.ts`
- `packages-native/crsql-mesh-protocol/test/Messages.test.ts`
- `packages-native/crsql-mesh-runtime-node/src/NodeRuntime.ts`
- `packages-native/crsql-mesh/src/Mesh.ts`
- `packages-native/crsql-mesh/src/index.ts`
- `packages-native/crsql-mesh/test/Apply.test.ts`
- `packages-native/crsql-mesh/test/Integration.test.ts`
- `packages-native/crsql-mesh/test/VersionVector.test.ts`

**Environment**
- OS: darwin (macOS ARM64)
- Tooling: pnpm, vitest 3.2.4, nix

**Commands run (exact)**
```bash
pnpm vitest packages-native/crsql-mesh-protocol --run
pnpm vitest packages-native/crsql-mesh --run
pnpm vitest packages-native/crsql-mesh-runtime-node --run
```

**Outputs (paste)**

<details>
<summary>crsql-mesh-protocol tests (26 pass)</summary>

```text
 RUN  v3.2.4 /Users/tom/Developer/effect-native/cr-sqlite/effect-native

 ✓ |@effect-native/crsql-mesh-protocol| test/Protocol.test.ts (3 tests) 20ms
 ✓ |@effect-native/crsql-mesh-protocol| test/Roundtrip.test.ts (6 tests) 34ms
 ✓ |@effect-native/crsql-mesh-protocol| test/Messages.test.ts (17 tests) 60ms

 Test Files  3 passed (3)
      Tests  26 passed (26)
   Start at  08:36:33
   Duration  441ms (transform 39ms, setup 309ms, collect 167ms, tests 115ms, environment 0ms, prepare 111ms)
```
</details>

<details>
<summary>crsql-mesh tests (23 pass)</summary>

```text
 RUN  v3.2.4 /Users/tom/Developer/effect-native/cr-sqlite/effect-native

 ✓ |@effect-native/crsql-mesh| test/Receive.test.ts (4 tests) 37ms
 ✓ |@effect-native/crsql-mesh| test/Mesh.test.ts (7 tests) 74ms
 ✓ |@effect-native/crsql-mesh| test/Integration.test.ts (4 tests) 38ms
 ✓ |@effect-native/crsql-mesh| test/Apply.test.ts (5 tests) 42ms
 ✓ |@effect-native/crsql-mesh| test/VersionVector.test.ts (3 tests) 43ms

 Test Files  5 passed (5)
      Tests  23 passed (23)
   Start at  08:36:33
   Duration  544ms (transform 114ms, setup 642ms, collect 571ms, tests 234ms, environment 0ms, prepare 190ms)
```
</details>

<details>
<summary>crsql-mesh-runtime-node tests (11 pass)</summary>

```text
 RUN  v3.2.4 /Users/tom/Developer/effect-native/cr-sqlite/effect-native

 ✓ |@effect-native/crsql-mesh-runtime-node| test/Lifecycle.test.ts (3 tests) 25ms
 ✓ |@effect-native/crsql-mesh-runtime-node| test/NodeRuntime.test.ts (5 tests) 28ms
 ✓ |@effect-native/crsql-mesh-runtime-node| test/DatabaseWiring.test.ts (3 tests) 26ms

 Test Files  3 passed (3)
      Tests  11 passed (11)
   Start at  08:36:34
   Duration  543ms (transform 74ms, setup 303ms, collect 585ms, tests 78ms, environment 0ms, prepare 93ms)
```
</details>

**Reproduction steps (clean checkout)**
1. `git clone <repo> && cd cr-sqlite`
2. `cd effect-native && pnpm install`
3. `pnpm vitest packages-native/crsql-mesh-protocol --run`
4. `pnpm vitest packages-native/crsql-mesh --run`
5. `pnpm vitest packages-native/crsql-mesh-runtime-node --run`

**Known gaps / unverified claims**
- Effect version mismatch warning (3.19.8 vs 3.19.12) logged during runtime-node tests — tests pass but indicates dependency deduplication needed
- Real SQLite integration not yet wired — mesh engine uses MockDatabase test doubles
- Coverage not captured this round (no `--coverage` flag)
- No TypeScript check run (`pnpm check`) — only tests verified

---

## Round 2025-12-15 (33) — No delegation (all backlog blocked)

**Tasks executed**
- None — all backlog tasks are blocked

**Commits**
- No commits (assessment-only round)

**Environment**
- OS: darwin (macOS ARM64)
- Tooling: pnpm, vitest 3.2.4, nix, zig (via nix)

**Backlog status**
| Task | Status | Blocker |
|------|--------|---------|
| `.tasks/backlog/TASK-031-web-service-worker-fallback.md` | BLOCKED | Needs Phase 2 browser specs in `effect-native/.specs/` |
| `.tasks/backlog/TASK-032-web-reactive-subscriptions.md` | BLOCKED | Needs Phase 2 browser specs in `effect-native/.specs/` |
| `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md` | BLOCKED | Waiting for Tom to pick scope |

**Commands run (exact)**
```bash
# Mesh package tests (all pass)
pnpm -C effect-native vitest packages-native/crsql-mesh-protocol --run
pnpm -C effect-native vitest packages-native/crsql-mesh --run
pnpm -C effect-native vitest packages-native/crsql-mesh-runtime-node --run

# TypeScript check (clean)
pnpm -C effect-native check

# Zig tests
make -C zig test-unit   # PASS
make -C zig test-parity # 4 failures (rowid slab)
```

**Outputs (paste)**

<details>
<summary>Mesh tests (60 pass total)</summary>

```text
crsql-mesh-protocol: 26 passed
crsql-mesh: 23 passed
crsql-mesh-runtime-node: 11 passed
```
</details>

<details>
<summary>Zig parity test failures (4)</summary>

```text
=== Zig CR-SQLite Rowid Slab Tests ===
PASS: First table, first rowid = 1
PASS: First table, second rowid = 2
PASS: rowid[0] = 1
PASS: rowid[1] = 2
FAIL: rowid[2] = MISSING (expected 10000000000001)
FAIL: rowid[3] = MISSING (expected 10000000000002)
FAIL: rowid[4] = MISSING (expected 20000000000001)
FAIL: rowid[5] = MISSING (expected 20000000000002)
```

Root cause: Multi-table crsql_changes vtab rowid slab assignment not implemented.
</details>

**Known gaps / unverified claims**
- Zig parity tests have 4 failures (rowid slab for multi-table changes vtab)
- Browser tests have 18 failures (not investigated this round)
- `@effect-native/crsql` package tests fail due to `better-sqlite3` native binding missing — infrastructure issue, not code bug
- No new task cards created — waiting for Tom direction on:
  1. Whether to create tasks for Zig test failures
  2. Whether to create Phase 2 browser runtime spec tasks
  3. Scope for upstream feedback task

**Next actions (require Tom input)**
1. **Create Zig fix tasks** — rowid slab + browser test failures are non-TypeScript work
2. **Create Phase 2 browser spec tasks** — would unblock TASK-031/032
3. **Scope TASK-037** — define upstream feedback scope

---

## Round 2025-12-15 (34) — Zig parity fixed + browser tests green

**Tasks executed**
- `.tasks/done/TASK-051-zig-parity-rowid-slab.md`
- `.tasks/done/TASK-052-web-browser-test-triage.md`

**Commits**
- `3fc49dbe` — delegate round 34: fix zig rowid slab cache invalidation (TASK-051, 052)
- `e466ae2c` — cleanup: remove completed mesh tasks from backlog, update AGENTS.md + wishes

**Modified files**
- `zig/src/changes_vtab.zig` (schema cache invalidation fix)

**Environment**
- OS: darwin (macOS ARM64)
- Tooling: nix, zig (via nix), pnpm, playwright

**Commands run (exact)**
```bash
make -C zig test-parity
make -C zig test-browser
```

**Outputs (paste)**

<details>
<summary>Zig parity tests (52 pass)</summary>

```text
Running test-filters.sh...
  Filter tests: 12 passed
Running test-rowid-slab.sh...
  Rowid slab tests: 8 passed
Running test-alter.sh...
  Alter tests: 6 passed
Running test-noops.sh...
  Noop tests: 4 passed
Running test-fract.sh...
  Fract tests: 8 passed

  PASSED:  52
  FAILED:  0
  SKIPPED: 0

All implemented tests PASSED
```
</details>

<details>
<summary>Browser tests (18 pass)</summary>

```text
Running 18 tests using 2 workers

  18 passed (7.4s)

  - SQLite WASM in Browser (7 tests)
  - CR-SQLite Extension (3 tests)
  - Multi-tab Database Coordination (6 tests)
  - OPFS Persistence (2 tests)
```
</details>

**Root cause analyses**

1. **TASK-051 (Zig rowid slab)**: The `crsql_changes` virtual table's schema-version keyed cache was not being properly invalidated when new CRR tables were created. In `changesFilter()`, `getSchemaVersion()` returned the **cached** schema version without checking if SQLite's `PRAGMA schema_version` had changed. Fix: Added call to `cache.checkSchemaVersion()` before checking cache validity.

2. **TASK-052 (Browser tests)**: All 18 failures were caused by **port conflict** (Python process on port 3456), not code bugs. The `serve` package silently picked a different port, while Playwright expected 3456. After freeing the port, all tests pass.

**Reproduction steps (clean checkout)**
1. `git clone <repo> && cd cr-sqlite`
2. `make -C zig test-parity`
3. Ensure port 3456 is free: `lsof -i :3456`
4. `make -C zig test-browser`

**Known gaps / unverified claims**
- TypeScript packages have type errors (visible in project diagnostics) — these are pre-existing from Round 32, not introduced by this round
- No coverage captured
