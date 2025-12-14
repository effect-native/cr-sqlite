# 100-proposal-node-multiprocess-crsqlite-mesh

## Goal

Make “SQLite in a load-balanced multi-process runtime” behave like the native `crsqlite-mt` promise, but in Node.js / Bun / Deno deployments:

- each process (or worker) uses its **own local SQLite database file** (no shared locks)
- writes are local and fast
- replicas converge via **CR-SQLite replication**
- adoption is “one small wrapper”, not a rewrite

This proposal is the multi-process analog of:

- the native per-thread VFS design: [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md)
- the browser multi-tab designs: [`96-proposal-multitab-wasm-sqlite-crsqlite.md`](./96-proposal-multitab-wasm-sqlite-crsqlite.md) and [`97-proposal-multitab-crsqlite-mesh.md`](./97-proposal-multitab-crsqlite-mesh.md)

---

## Proposal: `@libcrsql/crsqlite-mesh` (TS library)

### One sentence

A TypeScript library that wraps a local SQLite connection and continuously syncs CRRs across processes using `crsql_changes` pull/apply over a pluggable transport.

### Key constraint (be honest)

This is **eventual consistency**, not “one linearizable database behind a load balancer”. If you need strict serializable semantics across processes, you need a real central database or a single-writer provider.

---

## Architecture

### What runs in each process

- A local SQLite database file, owned by that process
- CR-SQLite enabled on the relevant tables
- A background sync loop

### Transport shapes (pluggable)

The library defines a minimal interface:

- `publish(batch)`
- `subscribe(handler)`

Transport implementations are separate packages to keep burden low:

- `@libcrsql/crsqlite-mesh-transport-ws` (WebSocket hub)
- `@libcrsql/crsqlite-mesh-transport-redis` (Redis pub/sub)
- `@libcrsql/crsqlite-mesh-transport-udsocket` (Unix domain socket, same-host)

The core library should not care which one you pick.

### Recommended default topology: “dumb relay hub”

For multi-host load balancing, the simplest reliable shape is:

- a stateless relay service (WebSocket) that only routes messages
- every app process connects and exchanges changesets

The relay does not run SQLite and does not need CR-SQLite.

Why this is lower-badness than peer-to-peer:

- fewer network edge cases (NAT, membership churn)
- central place to apply backpressure
- still no shared DB locks

---

## Replication contract (same as CR-SQLite everywhere)

### Outgoing

For each local DB:

- track `last_sent_db_version`
- on local commit, pull new rows:
  - `SELECT * FROM crsql_changes WHERE db_version > ? ORDER BY db_version, seq;`
- publish a batch:
  - `{ fromSiteId, dbName, minDbVersion, maxDbVersion, rows[] }`

### Incoming

For each received batch:

- apply in a single transaction:
  - `BEGIN;`
  - `INSERT INTO crsql_changes (...) VALUES (...);` per row
  - `COMMIT;`

The deterministic merge rules live in CR-SQLite; the library just ships rows.

### Dedupe

- batches can repeat; duplicates must not break correctness
- dedupe on `(fromSiteId, maxDbVersion)` (coarse) or `batchId` (explicit)

This is the same idempotency requirement discussed for provider migration in [`96-proposal-multitab-wasm-sqlite-crsqlite.md`](./96-proposal-multitab-wasm-sqlite-crsqlite.md).

---

## Minimal API (pit-of-success)

The default API should prevent users from “forgetting to sync”.

```ts
const db = await openCrsqliteMesh({
  dbPath: "./data/app.sqlite",
  dbName: "app",
  sqlite: bunSqlite() | betterSqlite3() | denoSqlite(),
  transport,
})

await db.exec("CREATE TABLE ...")
await db.exec("SELECT crsql_as_crr('items')")

await db.exec("INSERT INTO items ...")
```

Key choice: the wrapper owns the lifecycle (open + start sync).

---

## Adoption story (realistic)

### Node/Bun

- Works best with drivers that support loadable extensions and synchronous execution.
- If the runtime cannot load extensions, this proposal is blocked.

### Deno

- Same story: must be able to load or statically embed CR-SQLite.

### “Zero code change” is not the goal

Multi-process environments already require deployment/config changes. The real pit-of-success is:

- the app code stops caring about cross-process locking
- sync happens automatically
- conflicts converge deterministically

---

## Hard edges and explicit policies

### DDL

Same as [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md):

- MVP policy: DDL only during a migration window.
- The library can enforce this by exposing an explicit `pauseSyncForMigration()` API.

### Global uniqueness

Same problem as in multi-thread:

- local `UNIQUE` is not a global lock
- if the product needs global uniqueness, it must be modeled as a CRDT-friendly pattern (or coordinated centrally)

The library must not pretend otherwise.

---

## Stress tests (designed to break it)

### 1) Load balancer churn

- 8 processes behind a load balancer
- randomly kill and restart workers during write traffic

Pass criteria:

- convergence after churn
- no unbounded backlog growth

### 2) Split brain / partition

- partition the relay (or block transport) for 60s
- both sides continue writing

Pass criteria:

- convergence after reconnect
- deterministic winners

### 3) Hot key conflict storm

- all processes update the same 100 keys

Pass criteria:

- convergence
- bounded CPU and batch sizes (must backpressure)

---

## Non-goals

- Not a replacement for Postgres in strongly consistent systems.
- Not a global query fabric (you query your local replica).
- Not a distributed transaction manager.
