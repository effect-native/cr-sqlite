# 11-performance-hotspots

## Inventory

Observed hotspots and where they live:
- `PRAGMA data_version` checks:
  - `core/src/ext-data.c` (`crsql_fetchPragmaDataVersion`)
  - `core/rs/core/src/db_version.rs` (`fill_db_version_if_needed`)
- `crsql_changes` UNION query generation:
  - `core/rs/core/src/changes_vtab_read.rs` (`changes_union_query`)
  - `core/rs/core/src/changes_vtab.rs` (prepares/executes union stmt)
- DB version union query generation:
  - `core/rs/core/src/util.rs` (`get_db_version_union_query`)
  - `core/rs/core/src/ext_data.rs` (`recreate_db_version_stmt`)
- Table-info refresh:
  - `core/rs/core/src/tableinfo.rs` (`pull_all_table_infos`, `pull_table_info`)
  - `PRAGMA schema_version` invalidation via `core/src/ext-data.c`
- Statement caching/reset:
  - `core/rs/core/src/stmt_cache.rs`
  - cached `ManagedStmt` fields in `core/rs/core/src/tableinfo.rs`

## Runtime Role

These hotspots dominate two workloads:
- write-heavy (local triggers calling `crsql_next_db_version` frequently)
- sync-heavy (polling `crsql_changes` with constraints over many CRR tables)

## SQLite API Requirements

- Persistent prepared statements (`sqlite3_prepare_v3(SQLITE_PREPARE_PERSISTENT)`) for performance.
- PRAGMAs `schema_version` and `data_version`.

## Porting Implications (Zig)

- Don’t build on top of helper APIs that prepare+finalize on every call for hot paths.
- Cache:
  - prepared statements used repeatedly (db version, clock writes, pk key lookups)
  - generated union SQL or even prepared `crsql_changes` stmt keyed by schema_version and constraint string
- Use a single growable buffer to build large dynamic SQL (avoid `join()` allocation churn).
- Consider a per-transaction “data_version checked” flag to amortize pragma checks.

## Risks / Unknowns

- Performance is sensitive to # of CRR tables because both `crsql_changes` and `db_version` computation generate SQL with one UNION arm per table.
- Replacing UNION with views/temp tables can improve compile time but increases schema management complexity.

## MVP Cut

- For MVP correctness, keep the same strategies but ensure statement caching exists.
- Defer deeper optimizations until after functional parity; then profile:
  - `crsql_changes` statement prepare time
  - `PRAGMA data_version` frequency
