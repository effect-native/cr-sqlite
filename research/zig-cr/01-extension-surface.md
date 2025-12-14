# 01-extension-surface

## Inventory

### Loadable extension entrypoint
- Exported init symbol: `sqlite3_crsqlite_init`
  - `core/src/crsqlite.c`
  - `core/src/crsqlite.h`
  - Signature (SQLite): `int sqlite3_crsqlite_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)`
  - Signature (LIBSQL build): also receives `const libsql_api_routines *pLibsqlApi`

### Static build auto-extension hook
- Exported helper: `core_init(const char *dummy)`
  - `core/src/core_init.c`
  - Calls `sqlite3_auto_extension((void*)sqlite3_crsqlite_init)`

### C virtual table module registered in init
- Module name: `crsql_changes`
  - Registered in `core/src/crsqlite.c` via `sqlite3_create_module_v2(db, "crsql_changes", &crsql_changesModule, pExtData, 0)`
  - Module struct: `sqlite3_module crsql_changesModule` in `core/src/changes-vtab.c`
  - Schema declared in `changesConnect`: 9-column “changes rows” table

### Per-connection extension state (C struct)
- `crsql_ExtData` in `core/src/ext-data.h`
  - Lifecycle:
    - `crsql_newExtData(db, siteIdBuffer)` allocates and prepares statements (`core/src/ext-data.c`)
    - `crsql_finalize(pExtData)` finalizes statements but does not free (used on LIBSQL close hook)
    - `crsql_freeExtData(pExtData)` finalizes + frees site id + frees struct

### Rust bundle init invoked from C init
- C calls `sqlite3_crsqlrustbundle_init(db, pzErrMsg, pApi)`
  - Declared in `core/src/crsqlite.c`
  - Implemented in `core/rs/bundle/src/lib.rs`
  - Registers most SQL functions + Rust vtabs, returns pointer used as `crsql_ExtData*`.

### Effective SQL surface after init
Registered from the Rust bundle init (not directly from `crsqlite.c`):
- Fractional index helpers: `crsql_fract_as_ordered`, `crsql_fract_key_between`, `crsql_fract_fix_conflict_return_old_key`
- Core: `crsql_as_crr`, `crsql_as_table`, `crsql_changes` vtab (module), `crsql_site_id`, `crsql_db_version`, `crsql_next_db_version`, `crsql_increment_and_get_seq`, `crsql_get_seq`, `crsql_pack_columns`, `crsql_unpack_columns` vtab, `crsql_rows_impacted`, `crsql_config_get/set`, `crsql_finalize`, etc.

### Constants
- `CRSQLITE_VERSION` in `core/src/consts.h` (130000)

## Runtime Role

On connection init (`sqlite3_crsqlite_init`):
1. Installs SQLite API routines pointers (and LIBSQL API pointers if present).
2. Calls Rust bundle init to register SQL functions + Rust vtabs, and to create/initialize per-connection state.
3. Registers the C `crsql_changes` vtab module, passing the ext state as `pAux`.
4. Installs transaction hooks:
   - `sqlite3_commit_hook(db, commitHook, pExtData)`
   - `sqlite3_rollback_hook(db, rollbackHook, pExtData)`
   - LIBSQL-only: `libsql_close_hook(db, closeHook, pExtData)` which calls `crsql_finalize(pExtData)`.

## SQLite API Requirements

- Extension init plumbing: `SQLITE_EXTENSION_INIT2(pApi)` (and LIBSQL equivalent)
- Auto-extension: `sqlite3_auto_extension`
- Vtab registration: `sqlite3_create_module_v2`, `sqlite3_declare_vtab`
- Hooks: `sqlite3_commit_hook`, `sqlite3_rollback_hook`
- Statement APIs used by ext state: `sqlite3_prepare_v3` (PERSISTENT), `sqlite3_step`, `sqlite3_reset`, `sqlite3_finalize`
- Allocation: `sqlite3_malloc`, `sqlite3_free`, `sqlite3_mprintf`

## Porting Implications (Zig)

- Must export `sqlite3_crsqlite_init` with the correct signature and call the equivalent of `SQLITE_EXTENSION_INIT2` (set thunk table) so subsequent SQLite calls work.
- Init is orchestrational today; a Zig rewrite must replace `sqlite3_crsqlrustbundle_init` behavior: register the full SQL surface and construct per-connection state.
- The per-connection state is shared between:
  - hooks
  - `crsql_changes` vtab
  - local write triggers (via UDFs)
  so the Zig port should model this as a single `ExtData` struct.
- Consider implementing hook chaining to avoid clobbering existing commit/rollback hooks (currently a TODO).

## Risks / Unknowns

- The real extension surface is mostly in Rust today; porting only the C entrypoint would be incomplete.
- Cleanup differs by build (SQLite vs LIBSQL close hook). Ownership/lifetime of `ExtData` must be made explicit.

## MVP Cut

A “bring-up” MVP that validates loading and minimal replication plumbing:
- Export `sqlite3_crsqlite_init` and register `crsql_changes` module + commit/rollback hooks.
- Implement enough per-connection state to allow `crsql_changes` reads and rowid slab logic.
- Defer full SQL surface (only if acceptable for a spike); for compatibility, you’ll ultimately need all UDFs/vtabs registered in Rust today.
