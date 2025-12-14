# 95-one-weird-tricks (80/20 paths to an end-to-end beta)

This report lists credible “one weird trick” approaches to get an end-to-end experimental beta with ~20% of the effort that yields ~80% of the value.

Priority alignment:
- Web (first) → Linux (second)
- Expand later to macOS/Windows/iOS/Android when core is proven.

Each trick includes: **Effort**, **Value**, **Risks**, **What it unlocks**.

## 1) Web sync via Linux authority (Remote-first)
- Effort: Medium
- Value: High
- Risks: server dependency, not true peer-to-peer offline
- Unlocks: a real “it syncs” beta without finishing full wasm extension embedding

Approach:
- Web uses vanilla SQLite wasm for local UX.
- Linux service runs the existing CR-SQLite (current Rust/C) or the Zig port as it matures.
- Web sends mutation bundles; server applies/merges and returns patches.

## 2) Static-link CR into SQLite wasm (no extension loading)
- Effort: Medium–High
- Value: Very high
- Risks: wasm build complexity, binary size, debugging friction
- Unlocks: true web-native CR semantics with the exact SQL surface

Approach:
- Compile SQLite+CR into one wasm module.
- Register the extension via `sqlite3_auto_extension` or explicit init.

## 3) Implement only the “replication surface” first
- Effort: Medium
- Value: High
- Risks: partial semantics, missing advanced APIs
- Unlocks: end-to-end pull/apply changes; most apps just need sync

Scope-limited feature set:
- `crsql_as_crr`, triggers, `crsql_changes` read/apply, `crsql_pack_columns`, `crsql_site_id`, `crsql_db_version`, `crsql_rows_impacted`.
- Defer `fractindex` and `clset`.

## 4) Lease-based conflict avoidance (single-writer-per-record for beta)
- Effort: Low
- Value: Medium–High
- Risks: UX complexity, not “true CRDT”
- Unlocks: fewer merge edge cases while still demonstrating multi-device sync

Approach:
- A lightweight coordinator (linux) grants short-lived leases on logical documents.
- Offline writes queue and apply when lease is held.

## 5) Constrain writes to an “upsert/delete API” (SQL subset)
- Effort: Low–Medium
- Value: High for product teams
- Risks: power users unhappy; migration path needed
- Unlocks: simpler replication protocol, fewer undefined behaviors

Approach:
- For web beta, do not allow arbitrary SQL writes.
- Expose a minimal mutation API that maps cleanly to CR semantics.

## 6) Snapshot + incremental patch shipping (export/import UX)
- Effort: Very low
- Value: Medium
- Risks: not real-time; manual conflict handling
- Unlocks: immediate “data portability” beta story

Approach:
- Export `.sqlite` snapshot + “since snapshot” patch file.
- Import applies patch (server-mediated if needed).

## 7) Compile only the merge engine to wasm
- Effort: Medium
- Value: High
- Risks: semantics drift if SQLite-side capture differs
- Unlocks: offline merge/apply in web without embedding whole extension

Approach:
- Keep vanilla SQLite wasm.
- Use wasm module that consumes changes rows and outputs deterministic SQL updates.

## 8) Linux-first correctness oracle; web piggybacks
- Effort: Medium
- Value: High
- Risks: client/server coupling
- Unlocks: faster iteration and reproducible bug reports

Approach:
- Any web-generated changes are validated/re-written by linux oracle.
- Web applies canonical changes only.

---

## Recommendation (fastest credible beta)

If web is truly first priority:
1) Start with Trick 2 (static-link into sqlite wasm) if you can tolerate build complexity.
2) If not, ship Trick 1 + Trick 8 (server-oracle) to get an end-to-end beta quickly.

Then, once the Zig wasm build is stable, migrate the web client from “oracle server” to true local merge.
