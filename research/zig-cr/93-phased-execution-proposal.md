# 93-phased-execution-proposal (Web-first, Linux-second)

This proposal turns `research/zig-cr/*` into a concrete execution plan that:
- maximizes concurrency (many subagents / workstreams)
- follows RGRTDD (Red → Green → Refactor → Regression)
- uses a GAN-style adversarial collaborator (“the spec adversary”) to prevent vague requirements and accidental scope drift

## Inputs (source of truth)

Behavioral contract:
- `research/zig-cr/10-test-oracle.md`
- `core/src/changes-vtab-rowid.test.c`
- `core/src/changes-vtab.test.c`
- `core/src/rows-impacted.test.c`
- `core/src/crsqlite.test.c`

Implementation realities:
- `research/zig-cr/01-extension-surface.md`
- `research/zig-cr/02-virtual-tables.md`
- `research/zig-cr/03-hooks-and-triggers.md`
- `research/zig-cr/04-schema-and-metadata.md`
- `research/zig-cr/05-conflict-resolution-semantics.md`
- `research/zig-cr/06-clock-versioning.md`
- `research/zig-cr/09-storage-serialization.md`
- `research/zig-cr/11-performance-hotspots.md`

Zig reference constraints:
- `research/zig-cr/20-zig-sqlite-capabilities.md`
- `research/zig-cr/92-gap-backlog.md`

## Methodology: RGRTDD + GAN

### RGRTDD
- **Red**: add/enable tests that express the next behavior slice. Failures are allowed; *errors are defects* (load errors, crashes, missing symbols).
- **Green**: implement the minimum to pass that slice.
- **Refactor**: only once green, make structure “future-proof”.
- **Regression**: keep every green slice in CI; never break previous greens.

### GAN adversary roles
- **Spec Adversary (red team)**: tries to break assumptions and force explicit contracts. Examples:
  - blob vs text confusion
  - NULL semantics (`IS`/`IS NOT` vs `!=`)
  - sentinel ambiguity (`"-1"` dual use)
  - transaction boundaries and savepoints
  - platform SQLite feature mismatches (`STRICT`, `RETURNING`, `WITHOUT ROWID`)

- **Implementer (blue team)**: makes the smallest changes that satisfy the contract, no “nice-to-haves” until after parity.

## Platform goal ordering

1) **Web (WASM)**: highest priority. Ship an experimental beta that provides the CR surface in-browser.
2) **Linux**: second priority. Ship a loadable extension `.so` and a CLI harness.
3) Expand to macOS, Windows, iOS, Android.

The key architectural constraint is that *extension loading is not uniformly available* (web, iOS, many Android builds). Plan for “statically embedded init” on those targets.

---

## Phase 0 — Project scaffolding (parallel, 1–2 days)

### Acceptance criteria
- A new Zig workspace exists for the rewrite, but does not affect existing C/Rust build.
- A minimal wasm SQLite harness proves required SQLite features exist.

### Parallel workstreams (subagents)
1. **WASM SQLite Capabilities Agent**
   - confirms `STRICT`, `RETURNING`, triggers, vtabs are enabled in the chosen SQLite wasm build
2. **Zig Build/Packaging Agent**
   - drafts `build.zig` for: wasm static, linux shared, (later) mac/windows
3. **Test Harness Agent (host-side)**
   - creates a runner that can execute the existing oracle tests against:
     - wasm harness (JS-side tests)
     - linux `.so` harness (dlopen / load_extension)

### GAN adversary checklist
- If `RETURNING` or `STRICT` is missing in wasm build, stop and fix that first.

---

## Phase 1 — “Wire format first” (codec slice)

Why first: if the packed PK blob format is wrong, everything else is unreproducible (`research/zig-cr/09-storage-serialization.md`).

### Red (tests)
- Add golden vectors for `crsql_pack_columns` / `unpack_columns` round-trip.
- Mirror expectations from `core/src/changes-vtab.test.c` PK assertions.

### Green (implementation)
- Implement:
  - `crsql_pack_columns(...)`
  - `crsql_unpack_columns` vtab (or a pure decode function plus vtab)

### Acceptance criteria
- Golden vectors match byte-for-byte.
- `core/src/changes-vtab.test.c`’s PK blob expectation is reproducible.

### Parallel workstreams
1. **Codec Agent**: implements pack/unpack exactly.
2. **Blob Boundary Agent**: ensures wasm and Zig glue do not coerce blobs to text.
3. **Fuzzer Agent (optional)**: randomized encode/decode stability tests (no external net).

---

## Phase 2 — Clock + site identity slice

### Red
- Tests that:
  - `crsql_site_id()` returns stable 16-byte blob
  - `crsql_next_db_version(merging_version)` follows monotonic rules
  - `seq` increments within a tx and resets on commit/rollback

### Green
- Implement `ExtData` with:
  - `dbVersion`, `pendingDbVersion`, `seq`
  - `crsql_site_id` table and ordinal mapping
  - commit/rollback hooks

### Acceptance criteria
- `research/zig-cr/06-clock-versioning.md` invariants hold.

### Parallel workstreams
1. **SQLite Hook Agent**: commit/rollback and lifecycle handling.
2. **Schema Bootstrap Agent**: create `crsql_master` and `crsql_site_id`.
3. **Windows Calling Convention Scout (early)**: plan for `__declspec(dllexport)` / ABI constraints (prep only).

---

## Phase 3 — `crsql_as_crr` + trigger-based local capture

### Red
- Add tests that:
  - `crsql_as_crr('t')` creates `t__crsql_clock`, `t__crsql_pks`, triggers
  - local INSERT/UPDATE/DELETE emits `crsql_changes` rows (even before merge apply exists)

### Green
- Implement:
  - `crsql_as_crr` / `crsql_as_table`
  - triggers `__crsql_{i,u,d}trig`
  - UDFs `crsql_after_insert/update/delete`
  - `crsql_internal_sync_bit()` guard

### Acceptance criteria
- Local writes show up in `crsql_changes` read path once it exists.

### Parallel workstreams
1. **Trigger Generator Agent**: DDL correctness (quoting/escaping).
2. **Local Writes Agent**: clock row updates + `seq` bumping.
3. **Stmt Cache Agent**: statement caching strategy (needed for perf later).

---

## Phase 4 — `crsql_changes` read path (WASM-first)

### Red
- Port the relevant parts of:
  - `core/src/changes-vtab-rowid.test.c`
  - `core/src/changes-vtab.test.c` (read-only assertions)
into the wasm harness (and later reuse for linux).

### Green
- Implement `crsql_changes` read path:
  - union query across all CRR tables
  - best-index constraint mapping for `db_version` and `site_id`
  - default ordering `ORDER BY db_version, seq`
  - rowid slab logic (`ROWID_SLAB_SIZE`)

### Acceptance criteria
- `changes-vtab-rowid` parity achieved.
- `changes-vtab` read-only counts/filters match.

### Parallel workstreams
1. **Vtab Read Agent**: xBestIndex/xFilter/xNext/xColumn/xRowid.
2. **Table Enumeration Agent**: list tracked tables reliably.
3. **Query Builder Agent**: union string builder + caching keyed by `schema_version`.

GAN adversary note: tests prefer `site_id IS crsql_site_id()` over `!=`. Mirror that; don’t “fix” SQL semantics.

---

## Phase 5 — `crsql_changes` apply path (merge) + `rows_impacted`

### Red
- Port `core/src/rows-impacted.test.c` into wasm harness.

### Green
- Implement writable vtab:
  - `xUpdate` (INSERT-only)
  - `xBegin`/`xCommit` (impacted reset)
- Implement merge semantics:
  - `cl` dominates
  - then `col_version`
  - then deterministic value ordering
  - tombstone delete handling
  - resurrection semantics
- Implement `crsql_rows_impacted()`

### Acceptance criteria
- `rows-impacted` parity.

### Parallel workstreams
1. **Merge Engine Agent**: implements the rules from `research/zig-cr/05-conflict-resolution-semantics.md`.
2. **Value Comparator Agent**: deterministic ordering across SQLite types.
3. **Impacted Counter Agent**: exact semantics + reset rules.

---

## Phase 6 — End-to-end replication loop + alter workflow

### Red
- Port `core/src/crsqlite.test.c` behavior into wasm harness.

### Green
- Implement whatever remains for:
  - end-to-end A→B→C sync
  - `crsql_begin_alter` / `crsql_commit_alter`
  - compaction floor `pre_compact_dbversion`

### Acceptance criteria
- `crsqlite.test.c` parity (or a wasm-adjusted equivalent that asserts the same contract).

### Parallel workstreams
1. **Alter/Compaction Agent**
2. **Schema Migration/Gating Agent** (if you keep `crsqlite_version` gating)
3. **Perf Agent** (cache union stmt, amortize `PRAGMA data_version`)

---

## Phase 7 — Linux packaging (second priority, but run in parallel once Phase 2 exists)

### Deliverables
- `crsqlite-linux-x86_64.so` and later `crsqlite-linux-aarch64.so`
- A linux test harness that loads the `.so` and runs the existing C tests.

### Acceptance criteria
- The *same* semantic suite passes on linux.

### Parallel workstreams
1. **Linux `.so` Agent**: build + symbol exports.
2. **Harness Agent**: run C tests by loading extension.
3. **CI Agent**: minimal GitHub actions matrix for wasm + linux.

---

## Cross-platform expansion plan (post beta)

### macOS
- `.dylib` loadable extension and/or static embedding.

### Windows
- `.dll` export correctness + host SQLite differences.

### iOS / Android
- static embedding only; provide a “call init per connection” API.

---

## Risk register (top 6)

1. Blob/text confusion across boundaries (particularly wasm).
2. Writable vtab API surface and transaction integration.
3. Sentinel semantics (`"-1"`) and `cl` parity subtlety.
4. SQLite feature availability by platform (`STRICT`, `RETURNING`).
5. Performance scaling with many CRR tables (UNION query compilation).
6. Hook clobbering: commit/rollback hooks overwrite existing hooks; consider chaining later.
