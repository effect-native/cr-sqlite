# Rails Solid Cache: Source Notes

Repo: `.refs/solid_cache`

## Summary
Solid Cache is an `ActiveSupport::Cache::Store` implementation that persists cache entries in a DB table (`solid_cache_entries`). It targets “very large” cache capacity on SSD and trades away LRU; it is closer to FIFO with write-triggered eviction.

Key design choices:
- Uniqueness/indexing on a fixed-width `key_hash` (signed 64-bit derived from SHA256), not the full key.
- Stores the full serialized `ActiveSupport::Cache::Entry` blob in a `value` BLOB.
- TTL lives inside the serialized entry; the table has no `expires_at`.
- Eviction is **probabilistically scheduled** on writes; deletion selects oldest IDs and samples to reduce contention.
- Optional sharding across DB connections using Maglev hashing.

## Key Modules / Files
- Store: `.refs/solid_cache/lib/solid_cache/store.rb`
- Store API: `.refs/solid_cache/lib/solid_cache/store/api.rb`
- Entry model: `.refs/solid_cache/app/models/solid_cache/entry.rb`
- Expiration logic: `.refs/solid_cache/app/models/solid_cache/entry/expiration.rb`
- Schema templates: `.refs/solid_cache/lib/generators/solid_cache/install/templates/db/cache_schema.rb`

## Schema
Table: `solid_cache_entries`
- `key` BLOB(<=1024)
- `value` BLOB
- `created_at`
- `key_hash` i64 (unique)
- `byte_size` int

Indexes: unique `key_hash`, plus `byte_size` for size estimation.

## Algorithm Notes
- Reads deserialize the blob and rely on Rails semantics for `race_condition_ttl` etc.
- Writes are `upsert_all` by `key_hash`, and do **not** update `created_at` on overwrite.
- Eviction checks `max_entries`, `max_size` (estimated), and `max_age`.

## SQLite / cr-sqlite Suitability
### Plain SQLite
Solid Cache is explicitly built to run on SQLite (ships `cache_structure.sqlite3.sql`). Strong fit.

### cr-sqlite
Replicating a cache is generally a poor match:
- cache is ephemeral; replication wastes bandwidth/storage.
- eviction is time- and randomness-driven → nondeterministic histories.

If we use cr-sqlite here, it likely only makes sense for special cases:
- “offline-first replicated KV store” (not a cache)
- or strictly local-only cache tables (non-replicated DB).
