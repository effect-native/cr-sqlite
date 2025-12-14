# 91-mvp-roadmap

## Inventory

Primary acceptance criteria:
- `core/src/changes-vtab-rowid.test.c`
- `core/src/changes-vtab.test.c`
- `core/src/rows-impacted.test.c`
- `core/src/crsqlite.test.c`

Supporting docs:
- `research/zig-cr/10-test-oracle.md`
- `research/zig-cr/09-storage-serialization.md`

## Runtime Role

An MVP Zig port should validate the end-to-end loop:
1) enable a table as CRR (`crsql_as_crr`)
2) local writes produce clock metadata via triggers
3) `crsql_changes` streams changes
4) inserting those rows into another DB’s `crsql_changes` merges them

## SQLite API Requirements

- UDFs + vtabs in a loadable extension.
- Triggers and `RETURNING`.
- Commit/rollback hooks.

## Porting Implications (Zig)

### Phase 0: loadable extension bring-up
- Implement `sqlite3_crsqlite_init`:
  - set SQLite API-routines thunk
  - register UDFs and vtabs
  - install commit/rollback hooks

### Phase 1: pass `changes-vtab-rowid.test.c`
- Implement minimal `crsql_changes` read cursor:
  - union over tracked tables (can be hard-coded for MVP to “all clock tables”) but must support multi-table enumeration
  - rowid slab scheme via `ROWID_SLAB_SIZE`

### Phase 2: pass `changes-vtab.test.c`
- Implement `crsql_pack_columns` (byte-for-byte format) and make `crsql_changes.pk` match expected blobs.
- Implement best-index/filter sufficient for `site_id` and `db_version` constraints.

### Phase 3: pass `rows-impacted.test.c`
- Implement `crsql_changes` write path (`xUpdate` INSERT-only):
  - merge semantics: `cl` gating, `col_version` compare, deterministic value compare, delete tombstones
  - `crsql_rows_impacted()` counting + reset on commit

### Phase 4: pass `crsqlite.test.c`
- Implement full CRR lifecycle:
  - `crsql_as_crr` creates `__crsql_clock`, `__crsql_pks`, triggers
  - `crsql_as_table` tears them down
  - `crsql_begin_alter` / `crsql_commit_alter` compaction + trigger recreation
- Validate replication loop A→B→C and back-convergence.

## Risks / Unknowns

- `STRICT` and `RETURNING` require modern SQLite; ensure your target SQLite builds support them.
- Sentinel semantics (`"-1"` and `cl` parity) must match for delete/resurrect behavior.

## MVP Cut

- If you’re willing to stage features:
  - defer `fractindex-core` UDFs (`crsql_fract_*`) until core replication passes.
  - defer `clset`.
  - add performance caching only after correctness.
