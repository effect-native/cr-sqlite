# 102-proposal-crsqlite-global-mesh

## Goal

A “virtually local” SQLite database that is actually a **global peer-to-peer mesh**:

- runs across:
  - multiple React Native apps on multiple devices
  - multiple tabs in multiple browsers
  - multiple Node/Bun/Deno processes across containers and servers
  - multiple native processes with multiple threads
  - Raspberry Pis and assorted weird edge devices
- **zero single points of failure** (no required special nodes)
- every peer is fully functional **offline + local-first**
- the full mesh is **eventually consistent**
- enables “realtime multiplayer” product experiences by optimizing for **edge responsiveness**

Auth and permissions are fully out of scope.

This proposal builds directly on the earlier designs:

- Native per-thread replica concept (same-host): [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md)
- Node/Bun/Deno multi-process mesh: [`100-proposal-node-multiprocess-crsqlite-mesh.md`](./100-proposal-node-multiprocess-crsqlite-mesh.md)
- Universal JS packaging concept: [`101-proposal-universal-crsqlite-mt-js.md`](./101-proposal-universal-crsqlite-mt-js.md)
- Browser multi-tab mesh: [`97-proposal-multitab-crsqlite-mesh.md`](./97-proposal-multitab-crsqlite-mesh.md)
- Browser provider option (reference for “single-provider” fallback): [`96-proposal-multitab-wasm-sqlite-crsqlite.md`](./96-proposal-multitab-wasm-sqlite-crsqlite.md)

---

## One sentence

Every peer has its own SQLite+CR-SQLite replica; peers opportunistically exchange `crsql_changes` using any available transport; convergence is achieved by continuous anti-entropy.

---

## Non-goals (say the quiet part loud)

- Not linearizable “one database” semantics.
- Not global uniqueness/constraints unless the app models those invariants explicitly.
- Not a single query fabric (you query your local replica).
- Not a membership authority, PKI, or identity system.

If you need strict global invariants, you need a different architecture (or you build those invariants at a higher layer).

---

## Core principle: replicas are the unit

The only stable way to get “ludicrous speed at the edge” and “offline-first everywhere” is:

- every actor interacts with a local SQLite connection
- writes commit locally immediately
- synchronization is decoupled from UX

This is the exact spirit of the internet’s original architecture: **end-to-end, no required central coordinator**.

---

## Data model: CR-SQLite is the convergence engine

We lean on the existing CR-SQLite replication surface:

- Outgoing: pull ordered change rows from `crsql_changes`
- Incoming: apply by inserting those rows into `crsql_changes`

This is the same contract used in:

- [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md)
- [`97-proposal-multitab-crsqlite-mesh.md`](./97-proposal-multitab-crsqlite-mesh.md)
- [`100-proposal-node-multiprocess-crsqlite-mesh.md`](./100-proposal-node-multiprocess-crsqlite-mesh.md)

The CR merge semantics are deterministic in CR-SQLite (see: `research/zig-cr/05-conflict-resolution-semantics.md`).

---

## System architecture

### Each peer runs

- **Replica DB**: SQLite database file (or OPFS DB in browser)
- **Sync engine**: background task that talks to transports
- **Transport adapters**: “send/receive bytes” plugins

There are no “special nodes”. Some peers may *temporarily* act as relays, but nothing is required.

### The only hard interface: transport

Transports can be anything:

- cross-thread queues
- IPC (unix domain sockets, named pipes)
- LAN (UDP multicast, mDNS discovery + TCP)
- WebRTC data channels
- WebSockets
- QUIC
- Bluetooth / Multipeer Connectivity

The sync engine only needs:

- `send(peer, bytes)`
- `broadcast(bytes)` (optional)
- `onMessage(handler)`

Everything else is “policy”. Keep policy shallow.

---

## Anti-entropy protocol (the real heart)

Naively broadcasting “all changes since 0” works for demos and small meshes, but global mesh needs a real anti-entropy loop.

### 1) Summary exchange: version vectors (per site)

Each replica already has stable causal-ish identifiers:

- `site_id`
- `db_version`
- `seq`

So each peer can maintain a summary map:

- `knownMaxDbVersionBySiteId: Map<site_id, max_db_version_seen>`

A peer periodically sends a `summary` message:

- `{ siteId: <self>, known: { siteA: 10, siteB: 92, ... } }`

### 2) Diff request: “send me what I’m missing”

On receiving a summary, peer computes missing ranges and requests:

- `{ type: "want", siteId: <requestedSite>, sinceDbVersion: N }`

Then the other peer responds with:

- `SELECT * FROM crsql_changes WHERE site_id = ? AND db_version > ? ORDER BY db_version, seq`

This is bandwidth-bounded and works even with flaky connectivity.

### 3) Apply: idempotent, transactional

Incoming batches are applied transactionally:

- `BEGIN;` insert rows into `crsql_changes` `COMMIT;`

Duplicates are expected. Correctness must tolerate them.

This is the same idempotency motivation as in provider migration discussion: [`96-proposal-multitab-wasm-sqlite-crsqlite.md`](./96-proposal-multitab-wasm-sqlite-crsqlite.md).

---

## Bootstrapping a new peer (snapshots)

In a global mesh, a peer joining from empty state can’t always replay “all time”.

We need a snapshot path that still honors “no special nodes”:

- any peer can provide a snapshot
- snapshots are optional optimizations, not required for correctness

### Snapshot idea

- Provider sends an SQLite database snapshot (file bytes or equivalent export)
- plus a tail of `crsql_changes` newer than the snapshot’s `db_version`

This mirrors the approach sketched in [`97-proposal-multitab-crsqlite-mesh.md`](./97-proposal-multitab-crsqlite-mesh.md).

### Snapshot correctness constraints

- snapshot must represent a consistent SQLite state
- receiver applies tail changes transactionally

---

## Compaction and bounded storage (hard but unavoidable)

A global mesh needs a way to avoid unbounded growth.

Two viable strategies, both compatible with “no special nodes”:

### Strategy A: time-based retention + opportunistic healing

- keep changes for N days
- assume peers that were offline longer must re-bootstrap via snapshot

This is the simplest and fits real-world product constraints.

### Strategy B: acknowledgment-based garbage collection (higher complexity)

- peers exchange “I have applied up to X for site S” acknowledgments
- a replica can drop history once it is confident enough peers have it

This becomes complicated quickly because “all peers” is not enumerable in an open mesh.

MVP recommendation: Strategy A.

---

## Making it feel realtime

Eventual consistency can still feel realtime if:

- local commits are instant (SQLite)
- outgoing batches are small and frequent (debounced ~10–50ms)
- incoming apply is fast and happens continuously
- UIs react to “db_version advanced” notifications and re-query

This is exactly the “multiplayer feel without central DB latency” promise.

---

## DDL policy (global mesh edition)

Schema drift is betrayal.

MVP policy should mirror [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md):

- DDL only during explicit migration windows
- peers that cannot migrate must re-bootstrap

A future extension is a “schema-log CRR” where migrations are replicated and applied deterministically, but that is a full product in itself.

---

## Local offline sync across multiple apps on the same device (no server, app-store safe)

This is platform-policy constrained. The proposal must be honest about what’s possible.

### What we can do safely

**Same-vendor / same signing team apps** can often share data using OS-sanctioned mechanisms:

- iOS: App Groups shared container (same developer team + configured entitlement)
- Android: shared storage via `ContentProvider` with signature-level permission (same signing key)

These are not “servers”, and they do not violate app store rules when used as intended.

How to apply it here:

- do **not** share a single SQLite file across apps (back to lock fights)
- instead, share a **local transport mailbox**:
  - write change batches to shared container
  - other apps read and apply when they run
  - optional OS notifications to wake (best-effort)

This provides same-device offline sync without any network and without a separately deployed daemon.

### What we cannot promise

**Cross-vendor** apps on iOS/Android cannot arbitrarily exchange local filesystem data due to sandboxing.

Without auth/permissions, you still can’t bypass the OS. So for unrelated apps:

- you need a user-mediated channel (local network permission, Bluetooth pairing, QR code scan, etc.)
- or you accept “same device but different apps” sync is not feasible

The system can support those channels as transports, but it can’t force them to exist.

---

## Stress tests (designed to break the dream)

### 1) Unreliable transport soup

- peers randomly switch transports (WebRTC ↔ WS ↔ UDP)
- frequent packet loss, duplication, and reorder

Pass:

- eventual convergence
- bounded memory / queue growth via backpressure

### 2) Planet-scale partition

- partition the mesh into 3 groups for 24h
- all groups continue writing

Pass:

- convergence after reconnect
- snapshot fallback works for peers missing retention window

### 3) Hot-key conflict storm across 1k peers

- 1k peers update same set of 100 keys

Pass:

- convergence
- deterministic final state
- no pathological O(N^2) fanout collapse (must batch and anti-entropy)

### 4) Migration window failure

- half peers migrate schema, half don’t

Pass:

- clear failure mode (reject sync / force rebootstrap)
- no silent divergence

---

## Deliverable shape (fits the existing “universal” plan)

## Work Tracking

This proposal’s TypeScript follow-through is tracked via spec-first task cards in `.tasks/backlog/`:

- Phase 1 package map: [`.tasks/backlog/TASK-039-spec-global-mesh-package-map.md`](../../.tasks/backlog/TASK-039-spec-global-mesh-package-map.md)
- Protocol package spec: [`.tasks/backlog/TASK-040-spec-crsql-mesh-protocol.md`](../../.tasks/backlog/TASK-040-spec-crsql-mesh-protocol.md)
- Core engine spec: [`.tasks/backlog/TASK-041-spec-crsql-mesh-core.md`](../../.tasks/backlog/TASK-041-spec-crsql-mesh-core.md)
- Transport interface spec: [`.tasks/backlog/TASK-042-spec-crsql-mesh-transport.md`](../../.tasks/backlog/TASK-042-spec-crsql-mesh-transport.md)
- Integration into `@effect-native/crsql`: [`.tasks/backlog/TASK-043-spec-crsql-mesh-integration.md`](../../.tasks/backlog/TASK-043-spec-crsql-mesh-integration.md)
- `@effect-native/libcrsql` changes: [`.tasks/backlog/TASK-044-spec-libcrsql-next.md`](../../.tasks/backlog/TASK-044-spec-libcrsql-next.md)
- Runtime adapter package scoping: [`.tasks/backlog/TASK-045-spec-crsql-mesh-runtime.md`](../../.tasks/backlog/TASK-045-spec-crsql-mesh-runtime.md)

All TS implementation work must happen in `effect-native/` and follow `effect-native/.specs/AGENTS.md`.


This proposal is not a separate product; it’s the “full mesh” target for the universal package from:

- [`101-proposal-universal-crsqlite-mt-js.md`](./101-proposal-universal-crsqlite-mt-js.md)

In practice it decomposes cleanly into:

- core sync engine (anti-entropy + apply)
- transport plugins (many)
- platform-specific persistence (SQLite/native, OPFS/wasm)

Keep the core small. Everything else is optional adapters.
