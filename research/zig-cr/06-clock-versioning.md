# 06-clock-versioning

## Inventory

Key files:
- DB version logic: `core/rs/core/src/db_version.rs`
- Ext-data stmt recreation for max version: `core/rs/core/src/ext_data.rs`
- Union query builder: `core/rs/core/src/util.rs`
- Local write sequencing: `core/rs/core/src/local_writes/mod.rs`
- Site id bootstrap + mapping: `core/rs/core/src/bootstrap.rs`
- Commit/rollback hooks: `core/src/crsqlite.c`
- Ext-data init + PRAGMA statements: `core/src/ext-data.c`

Key state fields (per connection):
- `dbVersion` (committed)
- `pendingDbVersion` (transaction-scoped)
- `seq` (transaction-scoped per-change order)

## Runtime Role

CR-SQLite uses a Lamport-ish logical clock:
- `db_version` is a transaction-scoped version chosen at first local write (or merge), cached in `pendingDbVersion`.
- All local trigger-driven metadata writes within a transaction share the same `db_version`.
- `seq` is a per-transaction monotone counter that totally orders multiple changes that share a `db_version`.
- On commit: `pendingDbVersion` is promoted to `dbVersion`, and `seq` resets.
- On rollback: `pendingDbVersion` is discarded, and `seq` resets.

Site identity:
- `crsql_site_id` stores a blob site id at `ordinal=0` for the local node.
- Clock tables store `site_id` as an integer ordinal; reads join back to return the blob.

Compaction floor:
- `pre_compact_dbversion` stored in `crsql_master` preserves monotonic `db_version` across clock-table compaction.

## SQLite API Requirements

- PRAGMAs for cache invalidation and correctness:
  - `PRAGMA schema_version` (invalidate table-info + db-version statements)
  - `PRAGMA data_version` (avoid unnecessary dbVersion refresh)
- Queries over `sqlite_master` and `pragma_table_info`
- `RETURNING` used for ordinal allocation in `crsql_site_id`.

## Porting Implications (Zig)

- Model `dbVersion/pendingDbVersion/seq` in a single per-connection `ExtData` struct.
- Implement `crsql_next_db_version(merging_version)` so it returns:
  - `max(dbVersion+1, pendingDbVersion, merging_version)` and stores into `pendingDbVersion`.
- Ensure `seq` increments for each clock row written by local triggers.
- Maintain `pre_compact_dbversion` behavior if you want DB compatibility across alter/compaction.

## Risks / Unknowns

- `fill_db_version_if_needed` currently consults `PRAGMA data_version` potentially more often than necessary; behavior may rely on this in subtle ways.
- Savepoint-heavy workflows may interact with commit hooks differently; confirm expectations.

## MVP Cut

- Implement: `crsql_site_id`, `crsql_db_version`, `crsql_next_db_version`, `crsql_increment_and_get_seq`, commit/rollback bookkeeping.
- Defer compaction floor only if you accept potential version regression after dropping clock rows.
