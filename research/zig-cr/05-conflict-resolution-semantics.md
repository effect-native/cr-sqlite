# 05-conflict-resolution-semantics

## Inventory

Primary implementation files:
- Merge/write path: `core/rs/core/src/changes_vtab_write.rs`
- Prepared SQL used by merge: `core/rs/core/src/tableinfo.rs`
- Value comparison: `core/rs/core/src/compare_values.rs`
- DB version monotonicity: `core/rs/core/src/db_version.rs`
- Config influencing tie-breaks: `core/rs/core/src/config.rs`
- Sentinel constants: `core/rs/core/src/c.rs`

Key functions/symbols:
- `crsql_merge_insert` → `merge_insert(...)` (entry for vtab INSERT)
- `did_cid_win(...)` (per-column winner check when `cl` ties)
- `merge_delete(...)` (tombstone + clock cleanup)
- `merge_sentinel_only_insert(...)` / `zero_clocks_on_resurrect(...)`
- `set_winner_clock(...)` (writes winning clock row)

## Runtime Role

CR-SQLite treats rows from `INSERT INTO crsql_changes ...` as an incoming replication stream. For each incoming change row it decides whether it wins against local state, and if so it:
- applies the value (or delete) to the base table
- updates `"<tbl>__crsql_clock"` to record the winning metadata
- updates `rowsImpacted` accounting for user-facing telemetry (`crsql_rows_impacted()`)

Winner selection is hierarchical:
1) causal length (`cl`) dominates
2) then per-column clock (`col_version`)
3) then deterministic value ordering
4) optionally site-id ordering (config gated)

## SQLite API Requirements

- Writable virtual table support:
  - `xUpdate` (INSERT-only contract)
  - `xBegin`/`xCommit` (rowsImpacted reset)
- Prepared statement usage (merge path executes many SQL statements)
- SQLite comparison/value APIs (via `sqlite3_value_*`, `sqlite3_result_*` in Rust wrappers)
- Requires `RETURNING` for `crsql_site_id` ordinal allocation

## Porting Implications (Zig)

- Implement the same merge decision logic to remain compatible with existing DBs/tests.
- Porting requires a faithful model of:
  - `cl` computation (local cl derived from delete sentinel, or default 1 when any clock exists)
  - delete semantics (tombstone via delete sentinel, drop other clocks)
  - resurrection semantics (odd `cl` can resurrect; zero out non-sentinel clocks)
  - per-column winner check when `cl` ties
- `db_version` written during merge uses `crsql_next_db_version(merging_version)` (monotonic local clock that is >= incoming); don’t treat incoming `db_version` as authoritative.
- Value ordering is a deterministic comparator over SQLite types and payloads; port it carefully.
- The `mergeEqualValues` config changes behavior when values tie: it enables a site-id byte-wise tie-break.

## Risks / Unknowns

- Sentinel constants are surprising: Rust currently sets both `INSERT_SENTINEL` and `DELETE_SENTINEL` to `"-1"` in `core/rs/core/src/c.rs`. Semantics depend on `cl` parity and surrounding logic; this is a compatibility hazard.
- Delete path has an explicit ordering requirement: set winner clock before dropping other clocks; otherwise max db_version tracking can be lost.

## MVP Cut

- MVP merge port (enough for C tests):
  - `cl` gating + delete handling + per-column `col_version` / value compare
  - `rowsImpacted` accounting
- Defer advanced policies (like enabling `mergeEqualValues`) only if you’re willing to diverge from current config behavior.
