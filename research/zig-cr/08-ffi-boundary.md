# 08-ffi-boundary

## Inventory

Boundary files:
- C declarations of Rust exports: `core/src/rust.h`
- C init entry + call into Rust: `core/src/crsqlite.c`
- C vtab module that references Rust symbols: `core/src/changes-vtab.c`
- Rust exported init symbols:
  - `core/rs/bundle/src/lib.rs` (`sqlite3_crsqlrustbundle_init`)
  - `core/rs/core/src/lib.rs` (`sqlite3_crsqlcore_init`)
  - `core/rs/fractindex-core/src/lib.rs` (`sqlite3_crsqlfractionalindex_init`)
- Rust SQLite API thunk storage: `core/rs/sqlite-rs-embedded/sqlite3_capi/src/capi.rs`

Key exported Rust symbols referenced by C and/or SQLite:
- Bundle/core init functions listed above
- `crsql_changes_*` vtab methods (`core/rs/core/src/changes_vtab.rs`)
- `crsql_merge_insert` (`core/rs/core/src/changes_vtab_write.rs`)
- Ext-data helpers: `crsql_ensure_table_infos_are_up_to_date`, `crsql_fill_db_version_if_needed`, `crsql_next_db_version`, `crsql_clear_stmt_cache`, `crsql_recreate_db_version_stmt`, etc.

## Runtime Role

Today’s architecture is hybrid:
- C owns the loadable-extension init symbol and registers the `crsql_changes` module.
- Rust registers most SQL functions and additional vtabs, and implements most vtab logic for `crsql_changes`.
- Rust calls SQLite via a global `sqlite3_api_routines*` thunk table (loadable extension style).

## SQLite API Requirements

- Loadable extension API-routines pattern (equivalent to `sqlite3ext.h`): Rust and C both rely on receiving `sqlite3_api_routines*` and storing it for indirect calls.
- Destructor conventions: SQLite frees strings/blobs with `sqlite3_free`.

## Porting Implications (Zig)

- If rewriting in Zig, you can remove the C↔Rust boundary entirely and expose:
  - one init symbol (`sqlite3_crsqlite_init`)
  - Zig implementations of UDFs/vtabs/hooks.
- If staging (hybrid) is desired, treat the current ABI surface as a guide:
  - `crsql_ExtData` lifetime must be consistent across languages
  - memory passed to SQLite for errors/results must use SQLite allocator or a compatible allocator
- Be aware `.refs/zig-sqlite` currently lacks some loadable-entrypoint scaffolding; you’ll need to implement `sqlite3_api` assignment yourself.

## Risks / Unknowns

- `core/src/rust.h` includes stale declarations (some functions are not exported or exported under different symbol names). Trust `#[no_mangle] extern "C"` Rust functions as truth.
- Rust relies on a global allocator compatible with SQLite (`SQLite3Allocator`), so passing owned memory to SQLite works. Zig port must be explicit about allocation and destructor behavior.

## MVP Cut

- For a Zig rewrite MVP, avoid cross-language boundaries; implement a single-language `ExtData` and keep ABI surface minimal.
- Only add interop if you intentionally choose a staged migration (e.g., keep fractindex in Rust temporarily).
