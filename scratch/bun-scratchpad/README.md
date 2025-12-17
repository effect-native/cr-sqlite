# bun-scratchpad

Minimal CR-SQLite demo using `bun:sqlite`.

## Run

```bash
bun run scratch/bun-scratchpad/index.ts
```

## What it demonstrates

1. Loading a custom libsqlite3 that supports extension loading (via `Database.setCustomSQLite()`)
2. Loading the CR-SQLite extension with `db.loadExtension()`
3. Creating a CRR (conflict-free replicated relation) table
4. Basic CRUD operations (INSERT, UPDATE, DELETE)
5. Tracking `crsql_db_version()` as data changes
6. Viewing changes in `crsql_changes` virtual table
7. Getting the database's unique `crsql_site_id()`

## Dependencies

- Requires the libsqlite3 library from `effect-native/packages-native/libsqlite/`
- Uses the Zig-built CR-SQLite extension from `lib/crsqlite-zig-*.dylib`

## Expected output

```
=== CR-SQLite Demo with bun:sqlite ===

1. Loading custom libsqlite3 from: .../libsqlite3.dylib
2. Created in-memory SQLite database
   SQLite version: 3.50.2

3. Loading CR-SQLite extension from: .../crsqlite-zig-darwin-aarch64.dylib
   Extension loaded! Version: 0.0.1-zig-scaffold

4. Creating 'items' table...
5. Converting to CRR with crsql_as_crr('items')...
   Table is now a CRR!

6. Initial db_version: 0

7. Inserting items...
   Inserted: Apples (qty: 10)
   ...

=== Demo complete! ===
```
