# 23-notion-wasm-sqlite-multitab-technique

## What this report is

A focused research report on Notion’s “SharedWorker-powered” WASM SQLite deployment (July 2024) and the underlying technique first sketched by Roy Hashimoto in `wa-sqlite` discussion #81 (Apr 2023).

This technique is primarily about **making OPFS-backed SQLite usable across multiple browser tabs without corruption**, by ensuring that **only one SQLite connection owns the OPFS file handles**, while all tabs can still execute queries.

Sources:
- Notion blog post: “How we sped up Notion in the browser with WASM SQLite” (2024-07-10)
- `wa-sqlite` discussion: “Using a shared Worker (instead of SharedWorker)” #81
- SQLite wasm persistence docs: OPFS + `opfs-sahpool` VFS

---

## Inventory

### Browser APIs in play

- **Dedicated Web Worker**: only context which can use OPFS `FileSystemSyncAccessHandle` (`createSyncAccessHandle()` is not available in SharedWorker).
- **SharedWorker** (or **Service Worker** fallback): coordination / routing layer.
- **Web Locks API** (`navigator.locks`): leader election and liveness detection.
- **BroadcastChannel**: discovery + migration coordination.
- **MessageChannel / MessagePort**: high-throughput RPC between contexts.

### SQLite wasm components

- **OPFS `sqlite3_vfs`** ("opfs" VFS)
  - Requires SharedArrayBuffer → requires **COOP/COEP (cross-origin isolation)**.
  - Better concurrency story *in theory*.
  - In practice: Notion saw corruption with multiple tabs/Workers writing.

- **OPFS SyncAccessHandle Pool VFS** ("opfs-sahpool")
  - No COOP/COEP requirement.
  - **Highest OPFS performance** among official options.
  - **No multi-connection / multi-tab support** out of the box (one active instance per origin+directory).
  - Explicitly calls out app-level concurrency (links to `wa-sqlite` discussion #81/#84).

---

## Runtime role (what the technique does)

The technique builds a **single logical database service** per origin/database, even though the UI may be open in multiple tabs:

- Exactly one “provider tab” owns the SQLite connection + OPFS backing file handles.
- All other tabs (clients) send SQL/RPC requests to the provider.
- Provider tab can change (migration) when the active provider closes/reloads.

Net effect:
- You get OPFS durability + performance.
- You avoid multi-writer/multi-connection corruption.
- You keep “all tabs benefit from caching” semantics.

---

## Why Notion needed it (constraints + failures)

### 1) Cross-origin isolation is operationally expensive
Notion wanted to ship across all modern browsers without forcing COOP/COEP constraints, because:
- it breaks or complicates third-party scripts/iframes
- it requires coordinating headers across *all* loaded cross-origin resources

This removed the “opfs” VFS option (which needs SharedArrayBuffer → COOP/COEP) for general rollout.

### 2) Naive multi-tab OPFS access caused corruption
Notion initially tried: “one dedicated worker per tab, each opens the OPFS DB”.

Observed failure mode:
- OPFS concurrency isn’t desktop-grade.
- Multiple workers/contexts writing frequently led to corrupt DB files.

The Notion team’s mitigation attempts (Web Locks, in-focus-only writes) reduced but didn’t eliminate corruption.

### 3) `opfs-sahpool` VFS is single-tab by design
`opfs-sahpool` avoids the concurrency/corruption issues, but it throws if a second tab tries to open the same DB.

So: safer but incompatible with “multiple tabs benefit from caching”.

---

## The “SharedWorker-powered” architecture (Notion)

Notion’s shipped design:

- Each tab has a **dedicated Worker** which is capable of opening OPFS and talking to SQLite.
- A **SharedWorker** designates one tab as the **active tab**.
- All tabs send SQL requests to the SharedWorker.
- SharedWorker routes each request to the **active tab’s dedicated Worker**.
- When the active tab closes, SharedWorker selects a new one.

Liveness detection detail:
- Each tab holds an “infinitely open” **Web Lock**.
- If that lock is released, the tab must have closed.

Important: SharedWorker does *not* touch OPFS. It only routes requests.

---

## Hashimoto’s original “migrating service” design (wa-sqlite #81)

The discussion proposes a generalized pattern:

- A **database/service lives in a dedicated Worker owned by one tab** (because OPFS sync handles are DedicatedWorker-only).
- A small **SharedWorker exists only to pass MessagePorts between tabs**, not to do DB work.
- **Web Locks** detect death of clients and trigger migration.
- **BroadcastChannel** is used to announce and coordinate migrations.

Two key subtleties called out in the thread:

### A) Migration can happen mid-call
If the provider tab dies mid-request:
- the caller cannot know if the transaction committed or not.
- blind retry can be incorrect.

Mitigation sketch: add an idempotency marker table (`LastTx`) and reject duplicates inside the transaction.

### B) Connection state is not preserved
Only DB file state survives migration. Anything connection-scoped must be re-established:
- TEMP tables
- ATTACH-ed DBs
- PRAGMAs

In practice this means: the service must treat provider changes as a “cold restart”.

---

## Performance implications (why it’s fast)

### 1) Single connection enables `locking_mode=exclusive`
Hashimoto notes that sharing a single connection can be faster because:
- SQLite avoids per-transaction VFS locking calls
- SQLite can keep its page cache valid longer

This is especially relevant for web where VFS roundtrips are expensive.

### 2) Avoid Asyncify and SharedArrayBuffer
The AccessHandle-pool approach (and the official `opfs-sahpool` VFS) is synchronous:
- avoids async bridging overhead
- works without cross-origin isolation headers

### 3) Notion mitigated "slow initial page load" regressions
Notion’s key product insight:
- loading sqlite wasm synchronously hurts TTI
- they loaded it fully async and accepted that the very first page might not hit cache

They also “raced” cache reads vs network fetch on slow devices.

---

## Porting implications for CR-SQLite (how it maps)

This technique is not SQLite-specific; it’s an **application-level concurrency and ownership strategy**. It maps well to CR-SQLite because:

- CR-SQLite already assumes a single logical writer per connection (hooks, triggers, vtab apply path).
- OPFS corruption from concurrent writers is *worse* for CR-SQLite: corrupt clock/change tables can break convergence.
- CR-SQLite workloads are write-heavy (local capture + merge apply), so it benefits from:
  - single connection
  - stable SQLite cache
  - no lock churn

The main additional CR-SQLite concern is **correctness under provider migration**:
- we must ensure that "apply changes" operations are safe to retry or have an external commit marker.

---

## Risks / unknowns

- SharedWorker support is historically spotty on Android Chrome (but Chromium is adding it; timing varies).
- Service Worker fallback is plausible but adds operational complexity.
- Unclear if we can rely on `opfs-sahpool` pause/unpause APIs across all target browsers/versions.
- Provider migration correctness requires transaction idempotency or verification.

---

## MVP cut (minimum viable adoption)

- Treat the DB service as a black box: every call is a **single SQL batch transaction**.
- Route *all* calls through the provider to keep a single connection.
- Accept that migration is equivalent to process restart: reconnect + replay setup PRAGMAs.
- Add a single "tx id" idempotency mechanism only for write calls.
