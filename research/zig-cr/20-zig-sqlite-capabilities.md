# 20-zig-sqlite-capabilities

## Inventory

Relevant files:
- Loadable extension thunk layer: `.refs/zig-sqlite/c/loadable_extension.zig`
- High-level DB wrapper: `.refs/zig-sqlite/sqlite.zig`
- Virtual table framework: `.refs/zig-sqlite/vtab.zig`
- Value/result helpers: `.refs/zig-sqlite/helpers.zig`

## Runtime Role

`.refs/zig-sqlite` provides:
- a Zig wrapper around SQLite database handles and statements
- a vtab framework for implementing read-only virtual tables
- a loadable-extension-style thunk layer that forwards `sqlite3_*` calls through `sqlite3_api_routines` (like `sqlite3ext.h`)

## SQLite API Requirements

Covered by the thunk layer:
- many `sqlite3_*` functions including commit/rollback hooks and module registration.

Explicitly unsupported due to varargs:
- `sqlite3_mprintf` and related printf APIs
- `sqlite3_log`

Notably missing / problematic for CR-SQLite:
- no ready-made “extension init” helper to assign the global `sqlite3_api = pApi`
- `sqlite3_vtab_config` is a compile error stub
- vtab framework does not implement `xUpdate` or transaction callbacks (xBegin/xCommit/etc)
- helper arg decoding treats blobs as text (`sqlite3_value_text`) which corrupts binary payloads

## Porting Implications (Zig)

- You can reuse ideas (module scaffolding, statement wrappers), but CR-SQLite requires:
  - writable vtabs (`crsql_changes` needs xUpdate and commit/begin)
  - correct blob handling (`sqlite3_value_blob` for BLOB args)
  - entrypoint scaffolding to set `sqlite3_api` when built as a loadable extension
  - potentially `sqlite3_vtab_config` depending on desired vtab properties

## Risks / Unknowns

- If you build CR-SQLite as a loadable extension, your Zig code must ensure any memory returned to SQLite uses the correct allocator and destructor semantics.

## MVP Cut

- Use `.refs/zig-sqlite` as a reference, but plan to fork/extend:
  - add xUpdate + tx callbacks to vtab support
  - fix blob arg decoding
  - add init helper (`SQLITE_EXTENSION_INIT2` equivalent)
