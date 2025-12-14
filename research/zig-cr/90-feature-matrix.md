# 90-feature-matrix

## Inventory

This matrix maps “what exists today” to “what a Zig port needs”. It’s derived from:
- `research/zig-cr/01-extension-surface.md`
- `research/zig-cr/02-virtual-tables.md`
- `research/zig-cr/03-hooks-and-triggers.md`
- `research/zig-cr/04-schema-and-metadata.md`
- `research/zig-cr/05-conflict-resolution-semantics.md`
- `research/zig-cr/06-clock-versioning.md`
- `research/zig-cr/09-storage-serialization.md`
- `research/zig-cr/10-test-oracle.md`
- `research/zig-cr/20-zig-sqlite-capabilities.md`

## Runtime Role

### Core replication surface
- `sqlite3_crsqlite_init` → loads and wires everything
  - Current impl: C orchestration + Rust bundle
  - Zig port: export init symbol, set API-routines thunk, register all UDFs/vtabs/hooks

- `crsql_as_crr` / `crsql_as_table`
  - Current: Rust, creates/drops metadata tables + triggers
  - Zig: must generate identical schema (or provide migration plan)

- Local write capture (`crsql_after_*` + triggers)
  - Current: triggers call Rust UDFs to update clocks
  - Zig: same triggers + UDFs; must support sync-bit gate

- `crsql_changes` vtab
  - Current: C module struct + Rust x* methods; reads UNION across `__crsql_clock`, writes merge
  - Zig: writable vtab (xUpdate) + best-index + union-query generation + rowid slabs

- Merge semantics
  - Current: Rust `changes_vtab_write.rs`
  - Zig: port cl/col_version/value/site_id tie-breakers, tombstone/resurrect rules

- Ordering clock
  - Current: `dbVersion/pendingDbVersion/seq` + commit/rollback hooks
  - Zig: preserve invariants and `pre_compact_dbversion` behavior

### Serialization / wire formats
- PK blob format (`crsql_pack_columns`)
  - Current: Rust packed-column format in `pack_columns.rs`
  - Zig: must match byte-for-byte for replication compatibility

## SQLite API Requirements

Minimum APIs needed for parity:
- Loadable-extension API-routines thunking (`sqlite3_api_routines*`)
- UDF registration + value/result APIs
- Writable virtual tables (xUpdate + tx callbacks)
- Commit/rollback hooks
- Triggers (NEW/OLD + WHEN)
- Modern SQL features used in schema/merge:
  - `RETURNING`
  - `STRICT` tables
  - `WITHOUT ROWID`

## Porting Implications (Zig)

- `.refs/zig-sqlite` is a good starting point but is not sufficient out of the box:
  - its vtab framework is read-only (no xUpdate)
  - it mishandles blob args (uses `sqlite3_value_text`)
  - it lacks entrypoint scaffolding to assign `sqlite3_api = pApi`
- Use Ghostty’s build/allocator/testing idioms as “how to structure large Zig” reference.
- Use Bun’s ownership (`Data`) and parsing patterns as a reference for safe byte handling and error cleanup.

## Risks / Unknowns

- Sentinel encoding and `cl` parity semantics are subtle and must be matched.
- Large UNION query compilation cost scales with number of CRR tables.
- Hook clobbering: current extension overwrites commit/rollback hooks without chaining.

## MVP Cut

The minimal “pass C tests” path is captured in `research/zig-cr/91-mvp-roadmap.md`.
