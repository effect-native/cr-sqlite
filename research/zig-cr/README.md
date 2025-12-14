# Zig CR-SQLite Rewrite Research (Swarm Plan)

## Goal
Assess what it would take to re-implement the legacy CR-SQLite extension (C + Rust) in Zig, with a clear path to an MVP loadable extension and an explicit backlog of missing pieces.

This research is intentionally *parallelized*:
- Many small, focused agents each produce one markdown report.
- A short synthesis step merges them into a single implementation roadmap.

## Assumptions / Decisions To Confirm
These decisions change the scope of work materially:
1. Compatibility target: strict compatibility with current SQL APIs and vtab schemas vs allow breaking changes.
2. Purity: pure Zig rewrite vs staged hybrid (temporary Rust/C interop).
3. Early bring-up platform: macOS `.dylib` vs Linux `.so`.

If you decide later, this research still works; the synthesis will note forks.

## Output Contract (All Agents)
Each agent report must include these sections:
- **Inventory**: files / symbols / APIs involved.
- **Runtime Role**: what this code does at runtime.
- **SQLite API Requirements**: the SQLite interfaces it relies on.
- **Porting Implications (Zig)**: Zig features, patterns, wrappers needed.
- **Risks / Unknowns**: unresolved questions.
- **MVP Cut**: what can be deferred in a first working port.

## Agent Swarm Assignments
Each bullet corresponds to one agent report file in this folder.

### CR-SQLite legacy (C/Rust)
- `01-extension-surface.md`: C entrypoints, init/load, exported symbols.
- `02-virtual-tables.md`: vtab(s) inventory, x* methods, schemas.
- `03-hooks-and-triggers.md`: hooks (preupdate/update/commit/rollback/authorizer).
- `04-schema-and-metadata.md`: internal tables, migrations, naming.
- `05-conflict-resolution-semantics.md`: merge rules, winning semantics, tombstones.
- `06-clock-versioning.md`: site ids, causal ordering, clocks.
- `07-fractindex-rust.md`: fractindex role, APIs, feasibility to rewrite.
- `08-ffi-boundary.md`: current C↔Rust ABI; recommended Zig boundary.
- `09-storage-serialization.md`: binary formats, varints, blobs.
- `10-test-oracle.md`: behavior coverage from `core/src/*.test.c`.
- `11-performance-hotspots.md`: perf-sensitive paths and allocator patterns.

### Zig references (best practices + wrappers)
- `20-zig-sqlite-capabilities.md`: what `.refs/zig-sqlite` already provides; gaps.
- `21-ghostty-best-practices.md`: idioms for large Zig codebases; build/test patterns.
- `22-bun-best-practices.md`: idioms for protocol parsing/IO; error handling patterns.

## Synthesis Deliverables
After reports exist, produce:
- `90-feature-matrix.md`: feature → current impl → Zig plan → dependencies/gaps.
- `91-mvp-roadmap.md`: smallest end-to-end implementation plan.
- `92-gap-backlog.md`: missing Zig bindings + SQLite APIs to add.

## Reports
- `research/zig-cr/01-extension-surface.md`
- `research/zig-cr/02-virtual-tables.md`
- `research/zig-cr/03-hooks-and-triggers.md`
- `research/zig-cr/04-schema-and-metadata.md`
- `research/zig-cr/05-conflict-resolution-semantics.md`
- `research/zig-cr/06-clock-versioning.md`
- `research/zig-cr/07-fractindex-rust.md`
- `research/zig-cr/08-ffi-boundary.md`
- `research/zig-cr/09-storage-serialization.md`
- `research/zig-cr/10-test-oracle.md`
- `research/zig-cr/11-performance-hotspots.md`
- `research/zig-cr/20-zig-sqlite-capabilities.md`
- `research/zig-cr/21-ghostty-best-practices.md`
- `research/zig-cr/22-bun-best-practices.md`

## Working Method
1. Run agents concurrently with tight scopes.
2. Do *not* implement; research only.
3. Keep reports short, factual, and actionable.
