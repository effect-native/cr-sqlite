# Rails Solid Cable: Source Notes

Repo: `.refs/solid_cable`

## Summary
Solid Cable is an Action Cable subscription adapter that replaces Redis with a **database-backed message log**.

- Broadcast = insert row into `solid_cable_messages`.
- Each process runs a listener thread that **polls** the DB for new rows and delivers them to local subscribers.
- Subscriptions are in-process maps (no DB state for subscribers).
- Retention is handled by trimming old rows (probabilistically invoked).

## Key Modules / Files
- Adapter: `.refs/solid_cable/lib/action_cable/subscription_adapter/solid_cable.rb`
- Message model: `.refs/solid_cable/app/models/solid_cable/message.rb`
- Trim job: `.refs/solid_cable/app/jobs/solid_cable/trim_job.rb`
- Schema template: `.refs/solid_cable/lib/generators/solid_cable/install/templates/db/cable_schema.rb`

## Schema
Table: `solid_cable_messages`
- `channel` BLOB(<=1024)
- `payload` BLOB
- `created_at`
- `channel_hash` i64

Indexes: `channel_hash`, `channel`, `created_at`.

## Algorithm Notes
- Listener bootstraps by setting cursors to `Message.maximum(:id)` to avoid delivering old rows on subscribe.
- Poll query is basically `WHERE channel_hash IN (...) AND id > last_id ORDER BY id`.

## SQLite / cr-sqlite Suitability
### Plain SQLite
Works well for same-host shared DB (WAL mode recommended). Multi-host shared SQLite is risky.

### cr-sqlite
Current algorithm depends on a **single monotonic integer id** for cursors; replicated multi-writer DBs don’t have a total order like that.

To run Cable semantics on cr-sqlite you’d need:
- message identity as `(site_id, db_version, seq)` or ULID
- cursor logic based on CR-SQLite clocks, not rowid
- delivery idempotency and pruning semantics redesigned for replication

So: feasible but it becomes “Solid Cable v2” with different internals.
