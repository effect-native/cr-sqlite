# 97-proposal-multitab-crsqlite-mesh

## Summary

An alternative to the "single-provider, multi-client" architecture: instead, adopt a **true peer-to-peer, multi-writer, multi-tab design** where:

- Each tab runs its own **SQLite+crsqlite instance** with its own OPFS storage file.
- Tabs **replicate with each other via changesets** (pulled from `crsql_changes`, applied via `INSERT INTO crsql_changes`).
- CR-SQLite's merge semantics handle conflict resolution.
- No cross-tab file locking, no leader election, no bottleneck.

This gives **real multi-writer concurrency** while remaining true to the CR-SQLite model: local write commits are instant, and replication is eventual-consistency via CR rules.

---

## Motivation

### Why not just the single-provider design (Proposal 96)?
The single-provider design (Proposal 96) is pragmatic and works well for read-heavy workloads. But it trades:
- **write latency**: every write goes through the provider worker RPC → enqueued → executed.
- **provider as a bottleneck**: writes must contend in a queue; stress-test scenarios can show degradation.
- **migration brittleness**: provider death mid-transaction requires idempotency guards and retry logic.

### Why CR-SQLite's mesh?
CR-SQLite's entire purpose is to make **multi-writer convergence safe and deterministic**. If we're embedding it in the browser, we should leverage that fully:
- local commits are instant (no RPC)
- writes don't queue
- replication is asynchronous and decoupled
- conflicts are resolved by the same merge rules used in any CR system

This is closer to how CR-SQLite is actually *meant* to be used: peer databases syncing changes, not a shared single-writer DB accessed through a proxy.

---

## Architecture

### Per-tab components

**Tab Main Thread**
- UI layer
- uses `MeshDbClient` proxy that:
  - executes reads/writes against local Worker DB
  - subscribes to remote peer changes

**Dedicated Worker** (per tab)
- loads bundled `sqlite+crsqlite.wasm`
- owns a single SQLite connection to **a unique OPFS file per tab** (or per replica ID)
- exposes methods:
  - `execSql(sql, binds)` → rows
  - `pullLocalChanges(sinceDbVersion)` → change rows
  - `applyRemoteChanges(changeRows)` → applied count
  - `getDbVersion()` → dbVersion

**Transport layer** (shared infrastructure)
- `BroadcastChannel("crsqlite:<workspaceId>")` for same-origin cross-tab comms
  - OR optionally a `SharedWorker` hub (for better ordering + backpressure, but not required)

---

## Storage layout (no OPFS contention)

Each tab has its own replica. Pick one of these strategies:

### Strategy A: One DB file per tab session
- `OPFS path: /crsqlite/<workspaceId>/tab-<sessionId>.sqlite`
- Simplest, but creates many files if users open many tabs.
- sessionId = random UUID per page load.

### Strategy B: Replica ID persisted in sessionStorage
- `replicaId` persisted in `sessionStorage` (survives reload, not new tab).
- `OPFS path: /crsqlite/<workspaceId>/replica-<replicaId>.sqlite`
- Cleaner; same tab reloads use same replica.

### Strategy C: Fixed pool of N replicas (advanced)
- Maintain a registry of "active replicas" in IndexedDB.
- New tab picks LRU replica or creates new one (cap at N).
- Trade: increased complexity for bounded storage.

**Recommendation for MVP**: Strategy B. Simple, clear ownership, good user mental model.

---

## Sync protocol (same-origin)

All messages on `BroadcastChannel`:

### Message types

#### `hello` (on first load)
```json
{
  "type": "hello",
  "peerId": "<unique-peer-id>",
  "workspaceId": "<workspace-id>",
  "replicaId": "<replica-id>",
  "wantSnapshot": false
}
```
Purpose: announce presence to peers.

#### `changes` (after local write)
```json
{
  "type": "changes",
  "fromPeerId": "<peer-id>",
  "workspaceId": "<workspace-id>",
  "batchId": "<batch-uuid>",
  "sinceDbVersion": 0,
  "maxDbVersion": 42,
  "changes": [
    {
      "table": "my_table",
      "pk": "<packed-blob-hex>",
      "cid": "col1",
      "val": "new_value",
      "col_version": 5,
      "db_version": 42,
      "site_id": "<site-uuid-hex>",
      "seq": 1
    },
    ...
  ]
}
```
Purpose: broadcast local changes since `sinceDbVersion`.

#### `snapshotRequest` (on join, if `wantSnapshot=true`)
```json
{
  "type": "snapshotRequest",
  "fromPeerId": "<new-peer-id>",
  "workspaceId": "<workspace-id>"
}
```

#### `snapshot` (response to `snapshotRequest`)
```json
{
  "type": "snapshot",
  "fromPeerId": "<existing-peer-id>",
  "workspaceId": "<workspace-id>",
  "snapshotDbVersion": 100,
  "sqliteBytes": "<base64-or-byte-array>",
  "tailChanges": [
    // changes since snapshot version
  ]
}
```

---

## Sync algorithm (per tab)

### Outgoing loop
```
while true:
  sleep(debounce_delay)  // e.g., 100–250ms
  newMaxVersion = db.getDbVersion()
  if newMaxVersion > lastSentVersion:
    changes = db.pullLocalChanges(lastSentVersion + 1)
    broadcast({ type: "changes", changes, sinceDbVersion: lastSentVersion + 1, maxDbVersion: newMaxVersion })
    lastSentVersion = newMaxVersion
```

Why debounce? Avoids broadcasting every single-row insert separately; batch them.

### Incoming loop
```
on BroadcastChannel message:
  if message.fromPeerId == selfPeerId:
    ignore (echo)
  elif message.type == "changes":
    if message.fromPeerId not in seenBatches[message.batchId]:
      seenBatches[message.batchId].add(message.fromPeerId)
      db.applyRemoteChanges(message.changes)  // wrapped in txn
      notify UI of convergence
  elif message.type == "snapshotRequest" and we have fresh state:
    send snapshot
```

### Bootstrap (new tab joining)
- Option 1 (MVP): just send `hello` and let others send you all changes from dbVersion 0.
- Option 2 (better): send `snapshotRequest`, wait for a peer to send snapshot + tail.

For Option 2:
```
on init:
  db.open("/crsqlite/<workspaceId>/replica-<myReplicaId>.sqlite")
  broadcast({ type: "hello", wantSnapshot: true })
  
  on snapshot message:
    db.importBytes(message.sqliteBytes)
    db.applyRemoteChanges(message.tailChanges)
    // now we're caught up; proceed with normal sync loop
```

---

## CR-SQLite correctness guarantees

This design leans on CR-SQLite's core promise:
- **Causality**: `db_version` and `seq` encode causal order within a replica.
- **Deterministic merge**: given any set of changes + conflict resolution rules, any two replicas converge to the same state.
- **Idempotent apply**: applying the same change row multiple times has the same effect as applying once.

Therefore:
- Tabs can apply changes in any order (even out-of-order arrivals).
- Duplicates (same `batchId` seen from same peer) are safely ignored.
- Eventual consistency is guaranteed across all replicas.

**Key requirement for MVP correctness**:
- Each `applyRemoteChanges()` call is a single transaction.
- If it fails partway, the entire transaction rolls back.
- Retrying is safe because CR apply is idempotent.

---

## Perf + resource tradeoffs

### Cost
- Storage: N tabs = N OPFS DB files (one per replica).
  - For typical workloads, this is ~few MB per replica.
  - Not a blocker for most use cases.
- Memory: N page caches per SQLite instance (not deduplicated across tabs).
- CPU: periodic merge overhead proportional to change velocity.

### Benefit
- **Write latency**: local commits complete immediately (no RPC queue).
- **Throughput**: parallel writes in different tabs don't contend.
- **Resilience**: tab crash doesn't prevent other tabs from working.
- **Simplicity**: no leader election, no provider migration logic.

### For read-heavy apps?
If your workload is mostly reads, you might prefer Proposal 96 (single provider) to save storage. But this design is **strictly better for multi-writer apps**.

---

## Implementation phases

### Phase 1: MVP (BroadcastChannel + full sync)
- Simple BroadcastChannel transport.
- No snapshot optimization (full replay from dbVersion 0).
- All changes broadcast to all peers (no selective subscriptions).

**Acceptance**: 3 tabs, concurrent writes, converge within 1 second.

### Phase 2: Snapshots + tail
- On first join, ask for a snapshot + tail from a peer.
- Faster bootstrap for existing workspaces.

### Phase 3: SharedWorker hub (optional)
- Upgrade BroadcastChannel to SharedWorker for:
  - ordered message delivery (if needed)
  - backpressure / flow control
  - centralized replica registry
- Still no OPFS access in SharedWorker; each tab's Worker owns its DB.

### Phase 4: Optimizations (if needed)
- Selective subscriptions ("only sync this table").
- Delta compression for large changesets.
- Automatic replica cleanup / compaction.

---

## Comparison to Proposal 96 (single-provider)

| Aspect | Proposal 96 (Single Provider) | Proposal 97 (Mesh) |
|--------|------------------------------|-------------------|
| **Write latency** | RPC + queue | Local, instant |
| **Concurrency** | Serialized (single connection) | True parallel |
| **Storage** | 1 OPFS file + 1 connection | N files + N connections |
| **OPFS contention** | None (single provider owns file) | None (each tab has its own) |
| **Provider migration** | Needed (idempotency guards, retry logic) | N/A (no single provider) |
| **Complexity** | Moderate (SharedWorker routing) | Moderate (change pull/apply loop) |
| **Best for** | Read-heavy, low write freq | Write-heavy, multi-tap local edits |

---

## Acceptance criteria (concrete)

For `workspaceId = "demo"`, open 3 tabs:

1. **Independent writes**: Each tab can write locally without waiting for others. Latency < 10ms for tab-local commits.

2. **Convergence**: After all local writes complete:
   - within 2 seconds, all tabs see the same `SELECT COUNT(*) FROM user_table`.
   - CR merge rules are respected (if two tabs set the same row to different values, the higher `col_version` or tie-breaking rule wins).

3. **Resilience**: Close any tab; remaining tabs continue syncing independently. New tab can rejoin and catch up.

4. **No corruption**: Under stress (50 concurrent writes across 3 tabs), no "database is corrupted" errors. Final state is consistent.

5. **Storage bounded**: Total OPFS usage scales linearly with replica count and data size, not with velocity.

---

## Integration with zig-cr roadmap

This proposal also fits neatly:
- Each tab's Worker loads the same `sqlite+crsqlite` wasm bundle (same build as Proposal 96).
- The difference is **orchestration** (mesh vs. single-provider), not the wasm binary.
- Tests can be reused; just the sync protocol differs.

For teams wanting to ship Proposal 96 first (simpler) and upgrade to Proposal 97 later (better UX):
- the `MeshDbClient` API can be built to match the single-provider `DbClient` API.
- later, swap the transport layer.

---

## Risks / unknowns

- **Snapshot export/import**: depends on the sqlite wasm build exposing those primitives. Mitigation: MVP skips snapshots (full replay).
- **Change broadcast overhead**: if changesets get very large, BroadcastChannel might strain. Mitigation: add backpressure / flow control in Phase 3.
- **Replica divergence during network partition**: N/A (same-origin, never truly partitioned). But worth documenting that this is not a "global" consistency model (which CR-SQLite isn't either).

---

## MVP scope (to ship Phase 1)

- Per-tab wasm + OPFS DB file ✓
- BroadcastChannel sync loop ✓
- `applyRemoteChanges()` transaction wrapper ✓
- Echo suppression + duplicate detection ✓
- 3-tab browser test with concurrent writes ✓

Defer to Phase 2+:
- Snapshots
- SharedWorker hub
- Selective subscriptions
