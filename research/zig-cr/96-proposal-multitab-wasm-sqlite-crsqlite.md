# 96-proposal-multitab-wasm-sqlite-crsqlite

## Summary

Adopt a generalized version of Notion’s / `wa-sqlite` #81 approach to make **a single OPFS-backed SQLite+CR-SQLite database usable from many tabs** without OPFS corruption, without requiring COOP/COEP.

Concretely:
- Ship a **single bundled wasm build**: `sqlite + cr-sqlite` (no dynamic extension loading).
- Run that wasm build in a **single provider tab’s dedicated Worker**.
- Use a **SharedWorker (preferred) or Service Worker (fallback)** to:
  - elect the provider tab
  - route RPC calls from all tabs to the provider

This creates a reusable “browser database daemon” pattern:
- “One DB connection, many clients.”

This proposal is written to integrate cleanly with the existing web-first strategy in `research/zig-cr/93-phased-execution-proposal.md` and the long-term split described in `research/zig-cr/94-long-term-solution.md`.

---

## Goals

- **No OPFS corruption** under multi-tab use.
- **No COOP/COEP requirement** (avoid cross-origin isolation).
- **All tabs benefit** from a warm cache and CR sync state.
- Preserve the CR-SQLite SQL surface (the behavioral contract is `core/src/*.test.c`).

Non-goals (for MVP):
- True concurrent multi-connection reads.
- Running DB service in SharedWorker itself (blocked by lack of sync OPFS handles).

---

## Architecture

### Processes / threads

- **Tab Main Thread**
  - UI code
  - uses a `DbClient` proxy

- **Coordinator** (SharedWorker preferred)
  - picks a provider tab per logical DB name
  - holds MessagePorts for each connected client tab
  - routes each request to provider
  - detects provider death and triggers migration

- **Provider Tab Dedicated Worker**
  - loads bundled `sqlite+crsqlite` wasm
  - opens OPFS database using `opfs-sahpool` (or alternative)
  - executes requests sequentially
  - streams notifications

Notably:
- Only the provider worker ever touches OPFS.

### Data flow

`Tab A UI -> Coordinator -> Provider Worker -> Coordinator -> Tab A UI`

All clients (Tab A/B/C…) can issue queries concurrently; the provider serializes execution.

---

## Storage choice

### Recommended: official SQLite wasm `opfs-sahpool`
Rationale:
- Highest OPFS performance among official options.
- No SharedArrayBuffer requirement → no COOP/COEP.
- Works across major browsers released since ~Mar 2023.

Known limitation:
- Only one active instance per origin+directory.

Our architecture makes that limitation a feature.

### Optional future: OPFSCoopSyncVFS / OPFSAdaptiveVFS (wa-sqlite)
As newer OPFS VFSes mature, we can evaluate whether they:
- reduce need for leader election
- reduce mid-call migration hazards

But the provider model remains useful even if multi-connection becomes feasible.

---

## Provider election + liveness

### Election primitive
Use **Web Locks** (exclusive lock) for provider election:
- lock name: `crsqlite:provider:<dbName>`
- first tab to acquire lock becomes provider

### Liveness detection
Each client tab holds a lock:
- lock name: `crsqlite:client:<clientId>`

Provider can request that lock in shared mode to detect if it disappears and then:
- drop per-client subscriptions
- release ports

For provider liveness, coordinator monitors provider port; if disconnected, it triggers re-election.

---

## RPC interface

### Core calls (MVP)

All calls are framed as:
- `requestId: string`
- `type: 'exec' | 'query' | 'open' | 'close' | 'subscribe' | 'unsubscribe' | 'ping'`
- `payload`

Recommended to keep the API narrow and hard to misuse:

- `open({ dbName, vfs, flags })`
- `exec({ sql, bind?, tx?: 'none'|'immediate'|'deferred', txId? })`
- `query({ sql, bind? }) -> rows`

CR-specific convenience calls (optional but useful):
- `crsqlOpenOrInit()` (runs extension init + bootstrap tables)
- `crsqlPullChanges({ sinceDbVersion }) -> changes[]`
- `crsqlApplyChanges({ changes, txId }) -> { rowsImpacted, newDbVersion }`

Even if we expose generic SQL, it’s valuable to have CR-shaped helpers for replication.

### Serial execution
Provider processes requests on a single queue:
- avoids overlapping transactions
- avoids reentrancy bugs
- simplifies idempotency

---

## Migration safety (the hard part)

When provider dies mid-call, the caller cannot know whether a write committed.

We need explicit semantics. Options:

### Option A (recommended): write calls require `txId`
For any call which mutates state:
- client supplies a unique `txId`
- provider wraps the transaction with an idempotency guard table

Sketch (based on wa-sqlite #81):

- Create table once:
  - `crsqlite_web_last_tx(tabId TEXT PRIMARY KEY, txId TEXT)`
- Write transaction structure:
  - `BEGIN IMMEDIATE;`
  - `INSERT ... ON CONFLICT DO UPDATE` for `(tabId, txId)`
  - a trigger rejects duplicate txId for same tabId
  - run application SQL (or `INSERT INTO crsql_changes ...`)
  - `COMMIT;`

Semantics:
- retrying the same `txId` is safe: it either succeeds (if previous attempt failed) or rolls back with a known error (if it already committed).

### Option B: verify by reading a commit marker
If CR-SQLite apply path is provably idempotent, we can skip the table and instead:
- retry and accept “no net change”

This is tempting but needs proof in the oracle suite (don’t rely on it without tests).

---

## Notifications / subscriptions

A common reason multi-tab local DBs exist: “tab B must update when tab A writes.”

Provide an event channel:
- provider publishes “db_version advanced” messages
- clients can resubscribe queries or refresh UI

Minimal mechanism:
- provider executes `SELECT crsql_db_version()` after each write
- if changed, it broadcasts `{ dbName, dbVersion }` through coordinator

Optional upgrade:
- “observable query” subscriptions (like `observable-worker` mentioned in #81)
- but keep MVP minimal: event + client-side re-query

---

## Integration with our zig-cr roadmap

This proposal fits the existing plan:

- `research/zig-cr/93-phased-execution-proposal.md` already prioritizes Web (WASM) and warns about wasm feature gates.
- `research/zig-cr/94-long-term-solution.md` already expects **static embedding** for web.

The missing glue is **multi-tab orchestration**.

Where it lives:
- JS/TS package (web runtime): `zig/browser-test/` is already a natural home for experiments.
- Zig core remains SQLite-agnostic; the orchestrator is purely a web integration layer.

---

## Concrete deliverables

### 1) A portable web package
- `@libcrsql/web` (or similar)
  - exports `createDbClient({ dbName })`
  - internally starts coordinator + provider worker

### 2) Provider worker
- loads `sqlite+crsqlite` wasm bundle
- owns single SQLite connection
- uses OPFS VFS (likely `opfs-sahpool`)

### 3) Coordinator implementation
- SharedWorker primary
- Service Worker fallback for environments without SharedWorker
  - only used for port bridging; no OPFS access

### 4) Browser test coverage
- Extend `zig/browser-test/tests/crsql-wasm.spec.ts` to include multi-tab scenarios:
  - two pages open
  - both read/write through proxy
  - close provider tab mid-stream; ensure re-election

---

## Acceptance criteria

For a single `dbName` on a same-origin site:

- Opening 3 tabs concurrently:
  - all can execute `SELECT sqlite_version()` successfully.
  - all can execute `SELECT crsql_version()` successfully.
  - one tab is elected provider.

- Writes from tab A are visible in tab B within one notification round.

- Closing the provider tab:
  - a new provider is elected
  - clients reconnect automatically
  - subsequent reads work

- During stress (repeated writes in multiple tabs):
  - no DB corruption
  - no “second tab cannot open db” hard failures

---

## Risks

- SharedWorker availability on Android historically limited; service worker fallback is required for broad coverage.
- OPFS availability differs in private browsing; must degrade gracefully.
- Idempotency guard table adds minor overhead; but it’s localized to writes.

---

## MVP plan (sequenced)

1. Implement coordinator + provider wiring using MessagePorts and Web Locks.
2. Run a trivial SQLite-only query service through it.
3. Switch provider to `sqlite+crsqlite` wasm and validate `crsql_version()`.
4. Add write + notification path.
5. Add provider-migration test and idempotent write guard.
