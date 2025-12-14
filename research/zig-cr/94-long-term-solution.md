# 94-long-term-solution (Ideal Architecture)

This is the “perfect” long-term shape: one semantics engine, multiple platform frontends, and a stable wire format.

## North Star

- One canonical semantics implementation (Zig) used everywhere.
- One canonical wire format for replication payloads and PK blobs.
- Multiple integration skins for SQLite:
  - loadable extension (`.so/.dylib/.dll`) where possible
  - static embedding where required (wasm, iOS, many Android builds)

## Architectural split

### A) `crsql-core` (semantics engine; SQLite-agnostic)
Owns:
- merge rules (`cl` → `col_version` → value compare → optional site_id)
- tombstones and resurrection semantics
- ordering invariants (`db_version/pendingDbVersion/seq`)

Consumes:
- a stream of mutation events (insert/update/delete with old/new values)
- transaction boundary events (begin/commit/rollback)

Produces:
- “effects” to persist (clock updates, pk key creation requests, change feed rows)

### B) `crsql-codec` (wire formats)
Owns:
- `crsql_pack_columns` / `unpack_columns` byte format (must match existing tests)
- versioned encoding for any future replication bundles

This should be isolated and golden-tested with byte vectors.

### C) `crsql-sqlite-frontend` (SQLite adapter)
Owns:
- schema bootstrap (`crsql_master`, `crsql_site_id`)
- CRR enable/disable (`crsql_as_crr` / `crsql_as_table`)
- trigger generator (local change capture)
- vtabs (`crsql_changes`, `crsql_unpack_columns`, optional `clset`)
- commit/rollback hooks

Important design rule:
- Triggers capture mutations into a transaction-scoped staging area.
- Commit hook finalizes by calling into `crsql-core` and materializing outputs.
- Rollback hook discards staging.

### D) `crsql-ffi` (small C ABI)
Owns:
- `sqlite3_crsqlite_init` (loadable extension entrypoint)
- `crsql_init(db)` helper for static embedding

Keep the ABI minimal: don’t make C the contract beyond what SQLite requires.

## Platform mapping

### Web (WASM) — highest priority
- Build SQLite + CR layer into one wasm module.
- No runtime extension loading.
- Expose a tiny JS API:
  - open db
  - enable CRR
  - read changes
  - apply changes

### Linux — second priority
- Build a loadable `.so` with `sqlite3_crsqlite_init`.
- Provide a test harness that loads it and runs the existing oracle tests.

### macOS
- `.dylib` and static embedding option.

### Windows
- `.dll` with explicit export decorations and calling convention checks.

### iOS / Android
- Static embedding only.
- Provide an init function to register everything on each SQLite connection.

## Build system approach

Use Ghostty-style practices (`research/zig-cr/21-ghostty-best-practices.md`):
- thin top-level `build.zig`
- centralized config parsing
- shared dependency object

Targets:
- wasm32-wasi (or wasm32-emscripten depending on sqlite build)
- x86_64-linux-gnu (baseline glibc)
- aarch64-linux-gnu
- macOS arm64 + x86_64
- windows x86_64
- iOS (aarch64) + Android (aarch64/x86_64)

## Testing strategy

- Keep the existing C tests as the compatibility oracle.
- Add Zig-level unit tests for:
  - codec byte vectors
  - merge semantics edge cases (tombstone/resurrect)
- Add wasm-runner integration tests mirroring the same oracle assertions.

## Performance strategy (after correctness)

Hotspots (`research/zig-cr/11-performance-hotspots.md`):
- Cache union query and/or prepared stmt keyed by `schema_version`.
- Amortize `PRAGMA data_version` checks (once per tx).
- Aggressive statement caching in `TableInfo`-like structure.

## Recommendation summary

- Build wasm as a **static embedded** SQLite+CR module.
- Build linux as a **loadable extension**.
- Keep semantics engine and codec shared.
- Treat C tests + packed blob bytes as the contract; resist redesign until parity.
