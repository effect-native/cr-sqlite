# browser-scratchpad

CR-SQLite browser demo with multi-tab sync using SharedWorker coordination.

## Run

```bash
bun --hot scratch/browser-scratchpad/src/index.ts
```

Then open **two browser tabs** to `http://localhost:3000` to test cross-tab sync.

## What it demonstrates

1. Loading CR-SQLite WASM in the browser
2. SharedWorker-based multi-tab coordination (one tab becomes the "provider")
3. Cross-tab database visibility (changes in one tab appear in others)
4. CRR (conflict-free replicated relation) table operations
5. Real-time `crsql_db_version()` tracking

## Architecture

```
┌─────────────┐     ┌─────────────┐
│   Tab 1     │     │   Tab 2     │
│  (Provider) │     │  (Client)   │
└──────┬──────┘     └──────┬──────┘
       │                   │
       └───────────────────┘
              │
       ┌──────┴──────┐
       │ SharedWorker │  ← coordinator.js
       │  (Router)    │
       └──────┬──────┘
              │
       ┌──────┴──────┐
       │  Provider   │  ← provider.js
       │  Worker     │
       │  (SQLite)   │
       └─────────────┘
```

- The first tab that opens becomes the **provider** and owns the database
- Other tabs are **clients** that proxy requests through the SharedWorker
- If the provider tab closes, another tab automatically takes over (failover)

## Files served

- `/crsql-multitab.js` - DbClient API for the main thread
- `/coordinator.js` - SharedWorker for routing messages between tabs
- `/provider.js` - Dedicated Worker that runs SQLite WASM
- `/sql-wasm.js` + `/sql-wasm.wasm` - CR-SQLite WASM build
