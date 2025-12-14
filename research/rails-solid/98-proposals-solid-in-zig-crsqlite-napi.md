# Proposals: Solid {Queue,Cache,Cable} in Zig + (optional) cr-sqlite

This document proposes re-implementations of the Rails Solid_* family in Zig, backed by SQLite, and (where it genuinely helps) powered by cr-sqlite replication.

Context: the CR-SQLite Zig rewrite docs (`research/zig-cr/*`) describe a trigger-based capture engine and a `crsql_changes` writable virtual table that forms the replication boundary.

Related source notes:
- `research/rails-solid/solid-queue-source-notes.md`
- `research/rails-solid/solid-cache-source-notes.md`
- `research/rails-solid/solid-cable-source-notes.md`

---

## High-level finding: where cr-sqlite helps (and where it doesn’t)

- **Solid Cache**: using cr-sqlite is typically a net negative. Cache eviction is time-based and intentionally best-effort; replicating it wastes bandwidth and produces odd convergence behavior.
- **Solid Cable**: cr-sqlite can help if we design the message identity/cursor logic around CR clocks, not SQLite rowids.
- **Solid Queue**: cr-sqlite *cannot* safely provide “at-most-once execution” in a multi-writer replicated setting without introducing a leader/provider or a new lease/claim semantics layer. For most products: use a single executor.

This aligns with the zig-cr research constraints:
- cr-sqlite provides deterministic convergence of table updates; it does not provide global locks/leases.
- current Solid Cable / Solid Queue implementations assume a single globally ordered integer PK for cursors/claiming.

---

## Proposal 1: `solid-cache-zig` (SQLite-native, local-only)

### Goal
A disk-backed cache store with Solid Cache-like behavior and Node/Bun-friendly performance:
- bulk read/write operations
- stable upserts (don’t churn row identity on overwrites)
- deterministic, local eviction
- correct atomic increment/decrement under SQLite concurrency

### Storage schema
Single table, optimized for SQLite:

```sql
CREATE TABLE solid_cache_entries (
  key_hash INTEGER PRIMARY KEY, -- signed 64-bit
  key      BLOB NOT NULL,        -- <= 1024 bytes after normalization/truncation
  value    BLOB NOT NULL,        -- opaque payload blob (often a serialized entry)
  created_at_ms INTEGER NOT NULL,
  byte_size INTEGER NOT NULL
);

CREATE INDEX solid_cache_entries_byte_size ON solid_cache_entries(byte_size);
```

Notes:
- Use `key_hash` as PK to avoid a second integer id and keep index fixed-width.
- Preserve `created_at_ms` on overwrite (FIFO-ish behavior).

### Key normalization + hashing
- Normalize keys as UTF-8 bytes.
- Enforce max key bytes (1024). If too long: truncate prefix and append a short hash suffix.
- Compute `key_hash` = first 8 bytes of SHA256 interpreted as signed i64 (matches Solid Cache’s intent).
- On collision: verify stored `key` bytes match requested key bytes; otherwise treat as miss (and optionally store a second collision row keyed by `(key_hash, key)` if we want to be paranoid).

### Atomic increment/decrement (SQLite-correct)
Avoid “select then update” locking patterns.
Use a single statement:

```sql
INSERT INTO solid_cache_entries(key_hash, key, value, created_at_ms, byte_size)
VALUES (?, ?, encode_int64(?), ?, ?)
ON CONFLICT(key_hash) DO UPDATE SET
  value = encode_int64(decode_int64(value) + excluded_increment)
WHERE key = excluded.key;
```

Implementation details:
- store integer counters as a dedicated encoding envelope so reads can distinguish “counter value” vs arbitrary payload
- fail with a typed error if existing value is non-counter

### Eviction
Deterministic local policy (avoid random sampling):
- `max_entries`: delete oldest rows by `created_at_ms`
- `max_age_ms`: delete where `created_at_ms < now - max_age_ms`
- `max_size_bytes`: maintain an approximate rolling total; if over, delete oldest until under

Eviction trigger:
- performed on write, bounded to `N` rows per write to keep latency stable
- optionally a background eviction thread for heavy workloads

### cr-sqlite
Explicitly *not* replicated.
If you want “replicated KV”, implement a different product with deterministic last-writer semantics and an explicit TTL model.

---

## Proposal 2: `solid-cable-zig` (two variants)

Solid Cable is “DB-backed pubsub”. The key design choice is: do we want it to work across *replicas* (cr-sqlite) or only across *processes sharing one DB* (plain SQLite)?

### Variant 2A: Local (single DB, multi-process)

#### Storage schema

```sql
CREATE TABLE solid_cable_messages (
  message_id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_hash INTEGER NOT NULL,
  channel BLOB NOT NULL,
  payload BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE INDEX solid_cable_messages_channel_hash ON solid_cable_messages(channel_hash, message_id);
CREATE INDEX solid_cable_messages_created_at ON solid_cable_messages(created_at_ms);
```

#### Delivery algorithm
- Each process maintains:
  - in-process subscriber map: `channel_hash -> set(callback)`
  - `last_seen_message_id` cursor
- Poll loop:
  - query: `WHERE channel_hash IN (...) AND message_id > ? ORDER BY message_id LIMIT ?`
  - deliver in order

This matches the Ruby adapter’s behavior and is the best choice for “single host, no Redis”.

### Variant 2B: Replicated (cr-sqlite-backed)

#### Why this needs redesign
Ruby Solid Cable assumes a single monotonic integer `id` for `id > last_id` polling. Replicated multi-writer databases do not have a single total order rowid.

We instead build around CR-SQLite’s clock identity:
- `(site_id, db_version, seq)` is naturally unique and monotone per site.

#### Storage schema
A CRR table tracked by cr-sqlite:

```sql
CREATE TABLE solid_cable_messages (
  site_id BLOB NOT NULL,
  db_version INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  channel_hash INTEGER NOT NULL,
  channel BLOB NOT NULL,
  payload BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY(site_id, db_version, seq)
);
```

How to populate `(site_id, db_version, seq)`:
- Option A: store them explicitly at insert time by calling cr-sqlite functions that expose current tx clock (if/when we expose such a UDF).
- Option B: store a ULID/UUID as PK and use `created_at_ms` + tie-breakers for ordering (less aligned with cr-sqlite internals).

#### Cursor model
Per process, per channel watermark:
- `last_delivered` as a set of “max seen per site_id” clocks, or
- a durable “delivered up to db_version” if we use `crsql_changes` as the feed.

Practical MVP approach:
- Use `crsql_changes` as the *subscription feed* (filtered to `solid_cable_messages` rows).
- Apply an idempotent “deliver once per change row” rule keyed by the `(site_id, db_version, seq)` identity.

#### Retention / pruning
In CRDT land, deletion is replicated and permanent.
Two realistic strategies:
- **bounded log with explicit tombstones**: insert message rows, later delete rows older than retention; accept that deletion replicates.
- **no deletion**: keep messages forever and treat this as an append-only stream (only viable for small workloads).

Recommendation:
- For a product that wants replicated pubsub, accept replicated deletes and document the operational cost.

---

## Proposal 3: `solid-queue-zig` (three variants)

Solid Queue is the hardest one because job execution is a side effect.

### Variant 3A: Local queue (SQLite-only)

#### Storage schema
Match Solid Queue’s state-machine tables, but optimize for SQLite:

```sql
CREATE TABLE sq_jobs (
  job_id INTEGER PRIMARY KEY AUTOINCREMENT,
  queue_name TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  run_at_ms INTEGER,
  payload BLOB NOT NULL,
  concurrency_key BLOB,
  created_at_ms INTEGER NOT NULL,
  finished_at_ms INTEGER
);

CREATE TABLE sq_ready (
  job_id INTEGER PRIMARY KEY,
  queue_name TEXT NOT NULL,
  priority INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE sq_claimed (
  job_id INTEGER PRIMARY KEY,
  claimed_by BLOB NOT NULL,        -- worker identity
  claimed_at_ms INTEGER NOT NULL,
  lease_expires_at_ms INTEGER NOT NULL
);

CREATE TABLE sq_failed (
  job_id INTEGER PRIMARY KEY,
  error_json BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE INDEX sq_ready_poll_all ON sq_ready(priority, job_id);
CREATE INDEX sq_ready_poll_by_queue ON sq_ready(queue_name, priority, job_id);
CREATE INDEX sq_claimed_by_lease ON sq_claimed(lease_expires_at_ms);
```

Deliberate differences from Ruby Solid Queue:
- Use a single `sq_claimed` lease with explicit `lease_expires_at_ms` (SQLite-friendly and recovery-friendly).
- Avoid `processes` registry unless needed; leases + periodic reaping usually suffice.

#### Claim algorithm (SQLite-friendly)
Avoid `FOR UPDATE SKIP LOCKED`. Prefer a short transaction:
1. Select candidate job_ids with `LIMIT ?`.
2. For each candidate: attempt `INSERT INTO sq_claimed(job_id, ...) VALUES(...)`.
   - if insert succeeds, delete from `sq_ready` and hand to worker
   - if insert fails (already claimed), skip

Or, if available, do it with `RETURNING` + `UPDATE ... WHERE job_id IN (SELECT ...)` patterns.

#### Exactly-once vs at-least-once
On SQLite you can get “at-least-once” unless the user job handler is idempotent.
To get closer to “exactly once”, support user-provided idempotency keys and record completion by key.

### Variant 3B: Replicated job *intent* + single executor (recommended)

This is the safe way to combine queues with cr-sqlite.

#### Core idea
- Replicate a `jobs_intent` table (CRR) that defines what should run.
- Elect a single executor (provider/leader) that performs claims and runs handlers.
- Executor writes completion state back to the replicated intent table so all replicas observe progress.

#### Leadership mechanisms
- **Browser/WASM**: reuse the single-provider design from `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`.
- **Node/Bun**:
  - simplest: “only run the worker in one process” (user configuration)
  - more advanced: an advisory lock row in a non-replicated local DB, or an external leader election (out of scope for cr-sqlite itself)

#### Why this makes sense
cr-sqlite is a great fit for “producers can enqueue offline, sync later”; it’s not a fit for “multiple workers race to execute the same job across partitions”.

### Variant 3C: True multi-writer replicated queue (research-only)

This requires new semantics beyond current Solid Queue.
If attempted, it needs a spec and tests that define:
- what happens under partition
- whether duplicates are allowed
- how leases are resolved

Recommendation: treat as separate research; don’t merge into MVP plans.

---

## N-API integration proposal (Node + Bun)

Goal: a **single stable native ABI** that works in Node and Bun with minimal friction.

### Packaging overview
- Build one `.node` addon per module, or one combined addon exporting 3 namespaces.
- Distribute prebuilt binaries per platform/arch (like this repo’s `lib/crsqlite-<platform>-<arch>.*`).

Suggested layout:
- `lib/solid-zig-darwin-aarch64.node`, etc.
- `index.js` selects the correct `.node` file at runtime and exports typed JS wrappers.

### Addon design: one “core DB runtime” + module facades
Expose one internal `DbHandle` that owns:
- `sqlite3*`
- prepared statement cache
- configuration (busy_timeout, WAL, synchronous)
- a dedicated thread or a mutex

Then build 3 module facades on top:
- cache: simple sync methods
- cable: subscription + TSFN callback path
- queue: worker loop + TSFN job-dispatch callback path

### Memory + buffer interop
- Accept inputs as `string | Buffer | Uint8Array`.
- For outputs, return `Buffer` (Node) but ensure it is also a `Uint8Array` for Bun.
- Avoid copying by using `napi_create_external_buffer` when returning large payloads; attach a finalizer that frees Zig-allocated memory.

### Async + callbacks
- **Cable subscribe**:
  - subscription registry lives in Zig
  - poller thread reads DB, enqueues deliveries
  - use `napi_threadsafe_function` per subscription (or a single TSFN multiplexed by channel)

- **Queue worker handler**:
  - queue worker threads claim jobs
  - deliver a `Job` object to JS handler via TSFN
  - completion is acked back into Zig via an explicit `job.ack()/job.fail()` method
  - backpressure: bounded queue from native -> JS; when full, native pauses claiming

### Error model
Map all native errors to structured JS errors:
- `SqliteError { code, message, sql? }`
- `BusyTimeoutError`
- `ClosedError`

Keep these in JS for good stack traces, but include native error codes.

### Bun compatibility
Bun supports N-API addons; avoid Node-internal APIs.
Do not require `node-gyp` at install time for DX; prefer prebuilds.

---

## TypeScript client proposal (best DX)

### Goals
- One import, everything typed.
- Works in ESM.
- Minimal platform footguns.
- Good lifecycle management.

### JS/TS layering
1. `native.ts` loads addon and exposes minimal raw bindings.
2. `solid-cache.ts`, `solid-cable.ts`, `solid-queue.ts` provide ergonomic wrappers.

### API sketches

#### SolidCache
```ts
type SolidCacheOptions = {
  maxEntries?: number
  maxSizeBytes?: number
  maxAgeMs?: number
}

class SolidCache {
  static open(path: string, options?: SolidCacheOptions): SolidCache
  get(key: string | Uint8Array): Uint8Array | null
  set(key: string | Uint8Array, value: Uint8Array, opts?: { ttlMs?: number }): void
  getMany(keys: ReadonlyArray<string | Uint8Array>): Array<Uint8Array | null>
  setMany(entries: ReadonlyArray<{ key: string | Uint8Array; value: Uint8Array; ttlMs?: number }>): void
  increment(key: string | Uint8Array, by?: number): number
  close(): void
}
```

#### SolidCable
Two consumption modes:

1) callback subscriptions (lowest overhead)
```ts
class SolidCable {
  static open(path: string, opts?: { pollingIntervalMs?: number; retentionMs?: number }): SolidCable
  broadcast(channel: string, payload: Uint8Array): void
  subscribe(channel: string, onMessage: (payload: Uint8Array) => void): () => void
  close(): void
}
```

2) `AsyncIterable` (best DX)
```ts
class SolidCable {
  messages(channel: string): AsyncIterable<Uint8Array>
}
```
Implementation: subscription callback pushes into an internal async queue.

#### SolidQueue
Provide an “engine + worker helper” API:

```ts
type EnqueueOptions = {
  queue: string
  runAtMs?: number
  priority?: number
  idempotencyKey?: string
}

type WorkerOptions = {
  queues: string[]
  concurrency: number
  leaseMs?: number
  handler: (job: { id: number; payload: Uint8Array; queue: string }) => Promise<void>
}

class SolidQueue {
  static open(path: string): SolidQueue
  enqueue(payload: Uint8Array, options: EnqueueOptions): number
  startWorker(options: WorkerOptions): { shutdown(): Promise<void> }
  close(): void
}
```

### Optional “Effect DX” layer (fits this repo)
Provide an additional package entrypoint `@effect-native/solid-zig/effect`:
- `SolidCacheLive`, `SolidCableLive`, `SolidQueueLive` as scoped services
- `Effect.acquireRelease` lifecycle wrappers

This keeps the base package framework-agnostic while giving best-in-class DX in Effect codebases.

---

## Concrete next step recommendation

If the goal is a product you can ship quickly:
1. Build `solid-cache-zig` (local-only) first (low semantic risk).
2. Build `solid-cable-zig` local variant next.
3. Build `solid-queue-zig` local variant next.
4. Only then decide whether replicated Cable / replicated Queue-intent is required, and write specs/tests that define behavior under partitions and multi-writer merges.
