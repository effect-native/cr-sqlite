# 04-schema-and-metadata

## Inventory

### Global tables

#### `crsql_master`
- Created in `core/rs/core/src/bootstrap.rs`.
- DDL: `CREATE TABLE IF NOT EXISTS "crsql_master" ("key" TEXT PRIMARY KEY, "value" ANY);`
- Keys observed:
  - `crsqlite_version` (schema compatibility gating)
  - `pre_compact_dbversion` (monotonic db_version floor across compactions)
  - `config.*` (persisted config, e.g. `config.merge-equal-values`)

#### `crsql_site_id`
- Created in `core/rs/core/src/bootstrap.rs`.
- DDL: `CREATE TABLE "crsql_site_id" (site_id BLOB NOT NULL, ordinal INTEGER PRIMARY KEY);` plus unique index on site_id.
- Semantics: local site id stored at `ordinal=0`, remote sites get ordinals on demand.

#### `crsql_tracked_peers`
- Still created in `bootstrap.rs` (status unclear / may be legacy).

### Per-CRR table objects

For a user table `T`:

#### `T__crsql_pks`
- Created in `bootstrap.rs`.
- Maps PK tuple → `__crsql_key INTEGER PRIMARY KEY`.
- Unique index on the PK columns.

#### `T__crsql_clock`
- Created in `bootstrap.rs`.
- DDL (templated):
  - `(key INTEGER, col_name TEXT, col_version INTEGER, db_version INTEGER, site_id INTEGER DEFAULT 0, seq INTEGER, PRIMARY KEY(key,col_name)) WITHOUT ROWID, STRICT`.
  - Index on `db_version`.

#### Triggers
- Created in `core/rs/core/src/triggers.rs`:
  - `T__crsql_itrig`, `T__crsql_utrig`, `T__crsql_dtrig`
  - `WHEN crsql_internal_sync_bit() = 0`

### Vtabs
- `crsql_changes` module is registered from C init, implemented in Rust.
- `crsql_unpack_columns` and `clset` are Rust modules.

## Runtime Role

- `__crsql_pks` gives stable compact integer keys.
- `__crsql_clock` stores per-cell metadata and ordering fields (`db_version`, `seq`, `site_id ordinal`).
- `crsql_master` stores global metadata/config and preserves `db_version` monotonicity across compaction.
- Triggers + UDFs keep clock tables updated for local writes.

## SQLite API Requirements

- Requires relatively modern SQLite features used in DDL and DML:
  - `STRICT` tables
  - `WITHOUT ROWID`
  - `RETURNING` (used for site ordinal allocation and pk key creation)
- Uses `PRAGMA schema_version` and `PRAGMA data_version` for cache invalidation.
- Uses `sqlite_master` introspection for automigrate and CRR detection.

## Porting Implications (Zig)

- Object names are part of compatibility surface (`crsql_master`, `crsql_site_id`, `T__crsql_clock`, `T__crsql_pks`, trigger names). Changing them breaks existing DBs.
- `db_version` computation uses a union over all clock tables plus `pre_compact_dbversion`; this design needs either a faithful port or an explicit redesign/migration.
- Sentinel semantics in clock rows (values like `"-1"` and `cl` parity) appear to be “wire format” for metadata tables; treat as stable.

## Risks / Unknowns

- `crsql_tracked_peers` may be vestigial.
- Trigger naming drift: teardown drops patterns not created by current Rust.
- Migration strategy in this fork appears more “gating/reject old DBs” than incremental migrations.

## MVP Cut

- Implement creation/maintenance of `crsql_master`, `crsql_site_id`, `T__crsql_pks`, `T__crsql_clock`, and the three triggers.
- Defer `clset` and any peer-tracking features until needed.
