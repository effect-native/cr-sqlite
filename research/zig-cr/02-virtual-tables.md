# 02-virtual-tables

## Inventory

### Virtual tables present

1) `crsql_changes` (eponymous-only vtab)
- C wiring:
  - `core/src/changes-vtab.c`
  - `core/src/changes-vtab.h`
  - registered in `core/src/crsqlite.c` as module name `crsql_changes`
- Key point: the `sqlite3_module` struct is in C, but *most x* methods are implemented in Rust and exported as `crsql_changes_*` symbols.
  - Rust: `core/rs/core/src/changes_vtab.rs`, `changes_vtab_read.rs`, `changes_vtab_write.rs`

2) `crsql_unpack_columns` (helper vtab)
- Rust-only module: `core/rs/core/src/unpack_columns_vtab.rs`

3) `clset` (helper vtab)
- Rust-only module: `core/rs/core/src/create_cl_set_vtab.rs`

### `crsql_changes` schema (declared in C)
Declared in `core/src/changes-vtab.c`:
```sql
CREATE TABLE x(
  [table] TEXT NOT NULL,
  [pk] BLOB NOT NULL,
  [cid] TEXT NOT NULL,
  [val] ANY,
  [col_version] INTEGER NOT NULL,
  [db_version] INTEGER NOT NULL,
  [site_id] BLOB NOT NULL,
  [cl] INTEGER NOT NULL,
  [seq] INTEGER NOT NULL
)
```

### `crsql_changes` x* coverage
Module struct in `core/src/changes-vtab.c`:
- Implemented:
  - xConnect/xDisconnect/xOpen/xClose (C)
  - xBestIndex/xFilter/xNext/xEof/xColumn/xRowid/xUpdate/xBegin/xCommit (Rust)
- Not implemented: xCreate/xDestroy, xSync, xRollback, savepoint methods, etc.

## Runtime Role

### `crsql_changes`
- Read path: exposes a “changes feed” by UNIONing over all `"<tbl>__crsql_clock"` tables and joining:
  - `"<tbl>__crsql_pks"` to reconstruct PKs
  - `crsql_site_id` to map ordinal → blob
  - a second clock self-join to compute `cl` via a sentinel entry
- Write path: `INSERT INTO crsql_changes ...` applies remote changes (“merge”) into base tables and updates clocks.

### `crsql_unpack_columns`
- Turns a packed blob from `crsql_pack_columns(...)` into a rowset of scalar values.

### `clset`
- Side-effecting module that creates a base table and upgrades it into CRR form; query interface appears stubby.

## SQLite API Requirements

- Vtab lifecycle: `sqlite3_module` + `sqlite3_declare_vtab`
- Planning: `sqlite3_index_info` constraints/order-by mapping (Rust builds an `idxStr` SQL fragment)
- Rowid slab constant: `ROWID_SLAB_SIZE` in `core/src/consts.h` (`10000000000000`)

Behavior exercised by tests:
- Filtering: constraints like `WHERE db_version >= ? AND db_version < ?` and `site_id IS/IS NOT crsql_site_id()`
- Ordering default: `ORDER BY db_vrsn, seq ASC` if caller doesn’t supply ordering
- `_rowid_` slab allocation per underlying CRR table

## Porting Implications (Zig)

- `crsql_changes` is the primary vtab to port; it requires:
  - dynamic SQL generation (UNION ALL over tracked tables)
  - a table-info cache (schema-derived per-table data)
  - a writable vtab (`xUpdate`) with merge semantics
  - transactional integration (`xBegin`/`xCommit`)
- A Zig SQLite wrapper that only supports read-only vtabs won’t be sufficient.
- Preserve the rowid slab scheme; C tests assert exact offsets.

## Risks / Unknowns

- `core/src/changes-vtab.h` comment describes an older schema; treat it as stale.
- Rust defines `INSERT_SENTINEL` and `DELETE_SENTINEL` both as `"-1"` in `core/rs/core/src/c.rs`; code distinguishes semantics via `cl` parity and/or other fields. This is a compatibility landmine.
- `clset` query methods look incomplete and may not be covered by tests.

## MVP Cut

- Implement `crsql_changes` read path + rowid slabs first (enables replication pull).
- Add `xUpdate` for INSERT-only next (enables replication apply), with merge rules matching current Rust.
- `crsql_unpack_columns` is small and can be added early once the packed-blob format is ported.
- Defer `clset` unless you need that schema-management workflow.
