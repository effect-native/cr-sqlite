# 92-gap-backlog

## Inventory

Derived from:
- `research/zig-cr/20-zig-sqlite-capabilities.md`
- `research/zig-cr/02-virtual-tables.md`
- `research/zig-cr/09-storage-serialization.md`

## Runtime Role

This is the “things to build before Zig CR-SQLite can work” list, biased toward gaps in `.refs/zig-sqlite`.

## SQLite API Requirements

### Gaps in `.refs/zig-sqlite` for a CR-SQLite port

1) **Loadable extension init scaffolding**
- Need an equivalent of `SQLITE_EXTENSION_INIT2(pApi)` in Zig to set the global thunk table used by `c/loadable_extension.zig`.

2) **Writable vtab support**
- `crsql_changes` needs:
  - `xUpdate` (INSERT-only)
  - `xBegin`/`xCommit` (and potentially rollback)
- `.refs/zig-sqlite/vtab.zig` currently generates read-only vtabs.

3) **Blob-safe arg decoding**
- `.refs/zig-sqlite/helpers.zig` currently uses `sqlite3_value_text` for slice extraction, even for blobs.
- CR-SQLite requires stable binary decoding (`sqlite3_value_blob` + `sqlite3_value_bytes`).

4) **`sqlite3_vtab_config`**
- Thunk layer stubs it with a compile error.
- If you need to configure vtab behaviors (constraint support / innocuous / direct-only), you must implement it or avoid it.

5) **Missing/unknown hook APIs**
- CR-SQLite uses commit/rollback hooks (covered), but if you later want preupdate hooks, confirm availability and add to thunk layer.

## Porting Implications (Zig)

- Decide early whether to:
  - fork `.refs/zig-sqlite` into a purpose-built “zig-sqlite-extension” layer, or
  - write a minimal C ABI shim in Zig and only import the bits you need.
- Keep `ExtData` and its cached prepared statements in Zig with explicit allocator lifetime.

## Risks / Unknowns

- If you rely on returning memory to SQLite, you must ensure allocation/destructor matches SQLite expectations.
- Some SQLite APIs in the thunk layer are intentionally unsupported due to varargs; avoid them (e.g., use `sqlite3_errmsg` / fixed strings rather than `sqlite3_mprintf`) or implement safe alternatives.

## MVP Cut

- Solve (1) init scaffolding, (2) writable vtab, (3) blob decoding first.
- Defer `sqlite3_vtab_config` unless you hit a concrete need.
