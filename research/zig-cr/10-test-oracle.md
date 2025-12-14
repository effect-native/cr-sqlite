# 10-test-oracle

## Inventory

Primary C tests:
- `core/src/crsqlite.test.c` (end-to-end sync and alter)
- `core/src/is-crr.test.c` (CRR detection)
- `core/src/rows-impacted.test.c` (merge telemetry)
- `core/src/changes-vtab.test.c` (filters + pk blob bytes)
- `core/src/changes-vtab-rowid.test.c` (rowid slab semantics)

## Runtime Role

These tests define the behavioral contract the Zig port must match for compatibility:
- replication pull via `SELECT * FROM crsql_changes ...`
- replication apply via `INSERT INTO crsql_changes VALUES (...)`
- correct change filtering (site_id, db_version)
- stable ordering and rowid slab allocation
- correct pk blob encoding
- correct merge semantics (winner selection and delete semantics)
- correct schema-alter workflow via `crsql_begin_alter` / `crsql_commit_alter`

## SQLite API Requirements

- Must support `load_extension` surface and provide `crsql_*` UDFs.
- Must support vtabs including writable vtabs (`crsql_changes`).
- Must support modern SQLite features exercised indirectly:
  - triggers
  - `RETURNING`
  - `STRICT` tables / `WITHOUT ROWID`

## Porting Implications (Zig)

A Zig rewrite should treat these test patterns as acceptance criteria:
- Sync loop pattern:
  - read: `SELECT * FROM crsql_changes WHERE db_version > ? AND site_id IS NOT ?`
  - apply: `INSERT INTO crsql_changes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
- Site-id semantics:
  - local site id from `crsql_site_id()`
  - remote site IDs propagate when changes are relayed (site_id is preserved)
- Filtering semantics:
  - tests prefer `site_id IS crsql_site_id()` / `IS NOT` over `!=` due to NULL semantics
- Rowid slabs:
  - `_rowid_` values must match `ROWID_SLAB_SIZE` offsets exactly
- Rows impacted:
  - `crsql_rows_impacted()` increments only when merge actually modifies base state
  - resets after commit

## Risks / Unknowns

- Some tests include comments acknowledging known vtab constraint quirks; match their chosen SQL forms to avoid false negatives.

## MVP Cut

If you want a staged port:
1) Pass `changes-vtab-rowid.test.c` + `changes-vtab.test.c` first (read path + pk encoding).
2) Then pass `rows-impacted.test.c` (merge write path + telemetry).
3) Finally pass `crsqlite.test.c` (full replication and alter workflow).
