# 101-proposal-universal-crsqlite-mt-js

## Goal

Ship a single “pit-of-success” TypeScript package that provides the *same user-facing mental model* across:

- Node.js / Bun / Deno (multi-process)
- Browser (multi-tab)
- React Native (multi-threaded native host + JS)

The mental model is the one from the native proposal:

- **local, dedicated SQLite** (no connection sharing)
- **no lock fights** on a shared DB file
- **eventual convergence** via CR-SQLite

See native baseline: [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md)

See browser references:

- provider approach: [`96-proposal-multitab-wasm-sqlite-crsqlite.md`](./96-proposal-multitab-wasm-sqlite-crsqlite.md)
- mesh approach: [`97-proposal-multitab-crsqlite-mesh.md`](./97-proposal-multitab-crsqlite-mesh.md)

See node multi-process proposal:

- [`100-proposal-node-multiprocess-crsqlite-mesh.md`](./100-proposal-node-multiprocess-crsqlite-mesh.md)

See global mesh target:

- [`102-proposal-crsqlite-global-mesh.md`](./102-proposal-crsqlite-global-mesh.md)

---

## Proposal: `@libcrsql/crsqlite-mt` (universal JS package)

### One sentence

A universal wrapper that opens a local replica and starts sync automatically, picking the best backend per platform.

### Why this is worth doing

Most apps don’t want to think about “replicas” at all. They want:

- “open db”
- “run queries”
- “my other workers/tabs converge eventually”

This package makes the right architecture the default without forcing users to learn three different systems.

---

## What the package exports (tiny surface)

```ts
export type CrsqliteMtOptions = {
  name: string
  storage: "durable" | "memory"
  transport?: Transport
  mode?: "mesh" | "provider"
}

export function openCrsqliteMt(options: CrsqliteMtOptions): Promise<CrsqliteMtDb>
```

`CrsqliteMtDb` is intentionally small:

- `exec(sql, bind?)`
- `query(sql, bind?)`
- `close()`
- `on("advanced", handler)` (db_version advanced)

Anything fancier becomes pressure toward chaos and control-freak knobs.

---

## Platform strategy (pick defaults, avoid knobs)

### Node/Bun/Deno

Default: **mesh replication** as described in [`100-proposal-node-multiprocess-crsqlite-mesh.md`](./100-proposal-node-multiprocess-crsqlite-mesh.md).

- each process has its own DB file
- sync via transport (WebSocket relay recommended)

### Browser

Default: **mesh per-tab replicas** as described in [`97-proposal-multitab-crsqlite-mesh.md`](./97-proposal-multitab-crsqlite-mesh.md).

Why default mesh instead of provider:

- matches the “dedicated SQLite per thread/tab” promise
- avoids provider migration correctness complexity

Provider mode remains available for read-heavy apps and “single file” preference:

- [`96-proposal-multitab-wasm-sqlite-crsqlite.md`](./96-proposal-multitab-wasm-sqlite-crsqlite.md)

### React Native

Default: mesh replication across “replicas” inside the app.

Implementation depends on what SQLite substrate is available:

- If a RN SQLite library can load extensions: use CR-SQLite extension.
- If not: the package must ship a platform-native SQLite build with CR-SQLite embedded, exposed via a thin native module.

This doc does not pretend RN is free. It’s a packaging problem, not a CRDT problem.

---

## Transport unification

The universal package uses the same minimal `Transport` interface everywhere:

- in browser: `BroadcastChannel` (same-origin)
- in node: WebSocket relay / Redis / unix socket

The transport is not “optional glue”. It is the system. Keep it explicit.

---

## DDL and migration policy (universal)

Reuse the same policy everywhere:

- DDL must run in a migration window
- library exposes `pauseSyncForMigration()`

This crosslinks back to the native doc’s honesty about schema drift:

- [`99-threadsafe-sqlite-proposals.md`](./99-threadsafe-sqlite-proposals.md)

---

## Stress tests (universal suite)

Design one suite that can be run in each platform harness.

### 1) Convergence under churn

- start N replicas (tabs / threads / processes)
- random writes
- randomly kill and restart replicas

Pass criteria:

- convergence after quiescence
- bounded backlog

### 2) Partition tolerance

- block transport for 60s
- write on both sides

Pass criteria:

- convergence after reconnect

### 3) “Betrayal detector”: global uniqueness illusion

- two replicas insert different rows with same unique key

Pass criteria:

- outcome is explicitly documented and consistent (reject vs merge winner)

If the package can’t explain this, it’s setting users up to get burned.

---

## Deliverables (smallest honest MVP)

- `@libcrsql/crsqlite-mt` (core wrapper + platform selection)
- `@libcrsql/crsqlite-mt-transport-ws` (node/bun/deno)
- `@libcrsql/crsqlite-mt-transport-broadcastchannel` (browser)

Everything else is optional layering.
