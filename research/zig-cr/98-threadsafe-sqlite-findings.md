# 98-threadsafe-sqlite-findings

## What “threadsafe SQLite” really means

SQLite has multiple *build-time* threading modes, but the most important practical rule remains: **a single `sqlite3*` connection is not safe to use concurrently from multiple threads without external coordination** (or without running SQLite in fully-serialized mode, which still doesn’t make cross-thread use a pit-of-success in most host language bindings).

So the problem statement here is stronger than “compile SQLite with mutexes”. It’s:

- Every application thread gets **its own fully dedicated SQLite connection**.
- Threads can write without coordinating with each other.
- The system “just works” for apps that would normally point every thread at the same DB file.
- It remains fast under heavy write concurrency.

That pushes us toward an architecture where **each thread writes to its own local database state** and we **synchronize via CRDT semantics**, rather than having all threads compete for the same SQLite file locks.

## What CR-SQLite already gives us that matters

From the existing CR-SQLite design (as summarized in `research/zig-cr/*`):

### 1) A replication-friendly change stream
- `crsql_changes` is a virtual table which can be read as an ordered “what changed” feed.
- Incoming changes are applied by writing into `crsql_changes` (INSERT-only contract) and letting the merge engine decide what wins.

This is exactly the interface you want for “many replicas that converge”.

### 2) Deterministic conflict resolution (merge semantics)
The merge winner selection is hierarchical:

- `cl` dominates (causal length / tombstone-resurrection semantics)
- then per-column `col_version`
- then deterministic value ordering
- optional site-id ordering (config gated)

The big implication for multi-thread replication is: **convergence is deterministic even with races and duplicates**, as long as all replicas implement the same merge rules.

### 3) A usable logical clock model
CR-SQLite’s `db_version` + `seq` is a Lamport-ish clock per replica:

- `pendingDbVersion` is chosen at first local write in a transaction.
- all writes inside the transaction share `db_version`.
- `seq` orders multiple changes within the transaction.
- commit/rollback hooks reset/promote that state.

For multi-thread replication this gives:

- a simple “pull changes since version X” loop
- stable ordering for local batches
- a way to detect “I have advanced” for notifications

### 4) A stable primary-key wire format
`crsql_changes.pk` uses the packed-columns blob format described in `research/zig-cr/09-storage-serialization.md`.

That means replicas can exchange primary keys without re-deriving schema-specific encodings.

### 5) The performance profile and its likely failure modes
From `research/zig-cr/11-performance-hotspots.md`:

- Hot paths include `PRAGMA data_version` checks and dynamic UNION query generation for `crsql_changes` across many CRR tables.

A multi-replica, multi-thread design multiplies these costs unless we:

- avoid polling (prefer push / notification)
- batch changes aggressively
- keep “changes scanning” incremental per replica (persist last-seen version)

## Existing “multi-client SQLite” patterns we can adapt

`research/zig-cr/23-notion-wasm-sqlite-multitab-technique.md` (and proposals 96/97) are browser-tab centric, but the patterns transfer directly to threads:

### Pattern A: single provider / many clients
- One SQLite instance owns the DB.
- Everyone else uses RPC.

This yields strong consistency and one physical DB, but becomes a bottleneck and violates the “each thread has dedicated SQLite” goal.

### Pattern B: mesh of replicas (true CR model)
- Each tab/thread has its own SQLite instance and storage.
- They replicate via `crsql_changes` / `INSERT INTO crsql_changes`.

This matches the goal precisely: no lock contention, local commits are fast, and correctness is “eventual convergence” rather than strict serialization.

## Core tension: “pit of success” vs “SQLite semantics”

If we try to make an app think it is using **one linearizable database** while actually using **many replicas**, we must accept (and clearly document) that:

- reads across threads can observe divergence until sync happens
- uniqueness and constraint enforcement is only *local* at write time
- “global invariants” (e.g. unique username) become “conflict resolution rules”

CR-SQLite already has deterministic resolution, but that deterministic winner may not match an app’s intent unless the app models the data as CRDT-friendly.

So: a threadsafe-by-default SQLite drop-in is possible, but only by trading strict transactional semantics for **eventual consistency**.

## What would invalidate the idea outright

These are the “if these are unacceptable, the whole approach collapses” observations:

- If the app requires cross-thread linearizability (every thread sees every committed write immediately), then multi-replica is the wrong tool.
- If the app relies on constraints as *global* guards (unique constraints as a distributed lock), multi-replica will violate expectations unless higher-level CR-friendly strategies are adopted.
- If schema changes (DDL) must be safely concurrent with ongoing writes, we likely need a separate, explicit schema-sync protocol; otherwise replicas will diverge structurally.

The rest of this work (see the proposal doc) is about engineering a system that makes the tradeoffs explicit, defaults safe, and keeps performance excellent under concurrency.
