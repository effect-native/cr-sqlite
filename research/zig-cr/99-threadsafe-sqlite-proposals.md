# 99-threadsafe-sqlite-proposals

## Goal

Make SQLite “threadsafe-by-default” in the only way that actually scales under write contention:

- each thread has its **own** `sqlite3*` connection and **its own** storage file
- threads never coordinate via SQLite file locks
- replicas converge via **CR-SQLite replication** (`crsql_changes` pull + `INSERT INTO crsql_changes` apply)
- adoption is **one tiny switch** (ideally a URI `vfs=` or one init call)

The selling point is not “SQLite with more mutexes”. It’s: **no shared connection, no shared WAL, no lock fights**.

## Non-goals (must be explicit)

- This is not linearizable “one database with perfect consistency”.
- This does not preserve global constraints (e.g. `UNIQUE(email)`) without extra policy.
- This does not attempt “concurrent DDL across replicas” in MVP.

If an app needs strict read-your-writes across threads without delay, it must use provider mode (below) or classic shared-db locking.

---

## Proposal: `crsqlite-mt` (the core bet)

### One sentence

A custom SQLite VFS that transparently maps `app.db` → per-thread replica files, plus a lightweight in-process replicator that keeps replicas eventually consistent using CR-SQLite.

### Why this is the pit-of-success

- Each thread uses SQLite normally: no connection sharing, no special mutex ceremony.
- Lock contention disappears because threads don’t touch the same file.
- CR-SQLite already defines the replication interface and conflict resolution.

### What changes for the user

One of:

- open with URI: `file:app.db?vfs=crsqlite-mt`
- or one init call once per process: `crsqlite_mt_init()` and then set `crsqlite-mt` as default VFS (app/config dependent)

Everything else (SQL, transactions, prepared statements) stays “just SQLite”.

---

## Architecture

### Components (minimal set)

1) **Path-mapping VFS**
- Input: logical path (e.g. `/data/app.db`)
- Output: replica path (e.g. `/data/.crsqlite/app.db/replica-<id>.sqlite`)

2) **Replica identity**
- Per-thread stable `replica_id` (allocated once per thread).
- A `site_id` for CR-SQLite derived from `replica_id` (or stored per replica DB).

3) **Replicator (in-process)**
- Detect local commits and publish outgoing changes.
- Receive incoming changes and apply them transactionally.

### Replication contract (lean on CR-SQLite surface)

Outgoing (per replica):

- Track `last_sent_db_version`.
- When local `db_version` advances:
  - `SELECT * FROM crsql_changes WHERE db_version > ? ORDER BY db_version, seq;`
  - publish that rows array to peers.

Incoming (per replica):

- Apply in a single transaction:
  - `BEGIN;`
  - `INSERT INTO crsql_changes (...) VALUES (...);` for each row
  - `COMMIT;`

This matches CR-SQLite’s fundamental model: changes are the wire format; merge is deterministic.

### Notifications (avoid polling where possible)

MVP can poll `SELECT crsql_db_version()` periodically, but the pit-of-success version is:

- hook “commit happened” on each connection
- trigger a replicator tick that pulls and broadcasts

This keeps the hot path bounded and reduces `PRAGMA data_version` churn.

---

## Required tradeoffs (say the quiet part loud)

### Consistency model

- **Eventual consistency across threads.**
- A thread can read stale data until it applies peers’ changes.

Practical implication: if thread A writes and thread B immediately reads, B might not see it yet.

### Constraints and invariants

- Constraints (`UNIQUE`, `FOREIGN KEY`, CHECKs) are only enforced **locally** at write time.
- When two replicas commit conflicting but locally-valid transactions, CR-SQLite merge rules decide the winner.

If an app treats constraints as a distributed lock, it will get burned.

### DDL policy (MVP)

Pick one and enforce it hard:

- MVP recommendation: **DDL is forbidden while `crsqlite-mt` is active** (or must occur during an explicit “migration window” where replication is paused and replicas are rebuilt).

Anything softer is betraying; schema drift is how you get silent divergence.

### Storage and memory

- N threads → N SQLite files and N page caches.
- This is the price of lock-free concurrency.

---

## Adoption packaging (minimize burden and knobs)

### MVP packaging

- `libcrsqlite_mt` (or similar) that:
  - registers the `crsqlite-mt` VFS
  - provides a single init function
  - does not require per-query routing or new query APIs

### “Zero code change” is possible but expensive

A drop-in `libsqlite3` replacement could force the VFS as default, but it is high-burden and high-risk:

- ABI compatibility obligations
- platform distribution headaches
- surprising interactions with other extensions

Recommendation: treat that as an optional productization layer later, not the MVP.

---

## Provider mode (opt-in fallback for strict semantics)

If an app truly needs “it behaves like a single SQLite database”, the only honest route is:

- one provider thread owns one SQLite connection
- other threads use RPC to execute statements

This is safe and predictable, but it’s a throughput bottleneck under write storms and violates the “dedicated SQLite per thread” goal.

This mode should be an explicit opt-in, not a hidden default.

---

## Stress tests (designed to invalidate the idea)

These are the tests that will expose whether `crsqlite-mt` is real or a trap.

### 1) Write storm throughput + convergence

- 32 threads, each performs 10k transactions (mix of insert/update)
- run for 30 seconds

Pass criteria:

- no deadlocks or crashes
- bounded memory growth
- after quiescence, all replicas converge to identical state checksum

### 2) High-contention same-key churn

- all threads repeatedly update the same 100 keys with random values

Pass criteria:

- replicas converge
- final winners are deterministic across process restarts

This targets merge determinism and tie-break correctness.

### 3) Crash mid-apply

- kill a thread while it is applying an incoming batch
- restart it and re-deliver the same batch

Pass criteria:

- no double-apply
- eventual convergence still happens

If this fails, the system is not trustworthy.

---

## Open decisions (must be pinned down before MVP claims)

- **Constraint semantics**: do we accept CR outcomes, or do we provide a coordination layer for “global uniqueness”?
- **DDL story**: do we hard-forbid, provider-route, or implement schema-log replication?
- **Scope**: same-process only (fastest) vs cross-process (more general, more painful).

MVP recommendation (smallest honest promise):

- same-process only
- eventual consistency
- DDL forbidden (explicit migration window)
- provider mode as separate opt-in
