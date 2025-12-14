# 03-hooks-and-triggers

## Inventory

### SQLite connection hooks installed in C init
- `sqlite3_commit_hook(db, commitHook, pExtData)`
  - `core/src/crsqlite.c`
  - `commitHook` promotes `pendingDbVersion → dbVersion`, resets `seq`, clears `updatedTableInfosThisTx`.
- `sqlite3_rollback_hook(db, rollbackHook, pExtData)`
  - `rollbackHook` resets `pendingDbVersion`, `seq`, `updatedTableInfosThisTx`.
- LIBSQL-only: `libsql_close_hook(db, closeHook, pExtData)`
  - `closeHook` calls `crsql_finalize(pExtData)`.

### SQLite hooks NOT used by CR-SQLite logic
Confirmed absent from CR-SQLite code paths (outside vendored SQLite amalgamation):
- `sqlite3_update_hook`, `sqlite3_preupdate_hook`, `sqlite3_wal_hook`, `sqlite3_set_authorizer`, trace/profile hooks.

### Trigger-based capture (the real change-capture mechanism)
Triggers are created per CRR table in Rust:
- `core/rs/core/src/triggers.rs`
  - `"{table}__crsql_itrig"` AFTER INSERT
  - `"{table}__crsql_utrig"` AFTER UPDATE
  - `"{table}__crsql_dtrig"` AFTER DELETE
- Trigger guard: `WHEN crsql_internal_sync_bit() = 0`
- Trigger bodies call UDFs:
  - `crsql_after_insert` (`core/rs/core/src/local_writes/after_insert.rs`)
  - `crsql_after_update` (`core/rs/core/src/local_writes/after_update.rs`)
  - `crsql_after_delete` (`core/rs/core/src/local_writes/after_delete.rs`)

### Trigger removal / alter flow
- `core/rs/core/src/teardown.rs` drops triggers during `crsql_as_table` / alter flows.

## Runtime Role

- Commit/rollback hooks are bookkeeping only: they make `db_version` and `seq` behave like a transaction-scoped logical clock.
- Actual change capture is trigger-driven:
  - local writes invoke `crsql_after_*` UDFs which update clock tables and track `(db_version, seq)`.
- A “sync-bit” prevents recursion:
  - local triggers run only when `crsql_internal_sync_bit() = 0`.
  - merge/apply paths set the bit before writing base tables and clear it after.

## SQLite API Requirements

- Hooks: `sqlite3_commit_hook`, `sqlite3_rollback_hook`.
- Trigger support with `NEW`/`OLD` and `WHEN` clauses.
- UDFs callable from triggers.

## Porting Implications (Zig)

- You need both layers:
  - connection hooks for tx bookkeeping
  - trigger generator + UDF implementations for capture
- Hook chaining is desirable (current code clobbers any pre-existing hooks).
- Sync-bit must be connection-scoped and robustly cleared on error paths in merge logic.

## Risks / Unknowns

- Savepoint vs transaction edge cases: code uses savepoints in CRR creation; ensure `pendingDbVersion` semantics still match.
- Teardown drops legacy trigger names that aren’t created by current Rust; old DBs may contain extra artifacts.

## MVP Cut

- Implement commit/rollback hooks plus the three triggers per CRR table.
- Implement `crsql_internal_sync_bit` and wrap merge writes.
- Defer lower-level hooks (preupdate/update) since current semantics don’t require them.
