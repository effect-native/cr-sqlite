# @effect-native/libcrsql-browser

CR-SQLite for browsers - CRDT-based SQLite replication with multi-tab support.

Part of the [@effect-native/libcrsql](https://github.com/effect-native/cr-sqlite) family. For Node.js/Bun server environments, use `@effect-native/libcrsql` instead.

## Features

- **CRDT Replication**: Conflict-free replicated data types for SQLite
- **Multi-tab Support**: Automatic coordination across browser tabs via SharedWorker
- **WASM SQLite**: Runs entirely in the browser with bundled SQLite + CR-SQLite
- **Zero Config**: Works out of the box with sensible defaults

---

## Hosted ESM Distribution (Proposal)

> **Status**: PROPOSAL — not yet implemented. This section describes what needs to exist for the "just import and go" experience.

### The Dream

```javascript
// That's it. One import. Everything Just Works™
import { DbClient } from 'https://esm.effect-native.io/libcrsql-browser@0.1.0/crsql-multitab.js';

const db = new DbClient({ dbName: 'myapp' });
await db.ready;
await db.exec("CREATE TABLE IF NOT EXISTS todos (id TEXT PRIMARY KEY, title TEXT)");
await db.exec("SELECT crsql_as_crr('todos')");
```

### What Files Need to Be Hosted

The hosted distribution requires these artifacts at a stable CDN URL:

```
https://esm.effect-native.io/libcrsql-browser@{VERSION}/
├── crsql-multitab.js      # Main entry ESM (DbClient + helpers)
├── coordinator.js          # SharedWorker for multi-tab coordination
├── provider.js             # Dedicated Worker that runs SQLite
├── sql-wasm.js             # SQLite+CR-SQLite WASM loader (bundled)
├── sql-wasm.wasm           # SQLite+CR-SQLite WASM binary
└── index.d.ts              # TypeScript declarations
```

**Total payload**: ~1.5MB (wasm) + ~50KB (JS) ≈ **1.5MB compressed**

### Versioning & Cache Busting

| Strategy | URL Pattern | Cache Behavior |
|----------|-------------|----------------|
| **Immutable versions** | `/libcrsql-browser@0.1.0/...` | Forever (immutable) |
| **Latest alias** | `/libcrsql-browser@latest/...` | Short TTL (1hr) |
| **Git SHA** | `/libcrsql-browser@abc1234/...` | Forever (immutable) |

**Recommended**: Use explicit versions in production for reproducibility. Use `@latest` for development/prototyping only.

Worker URLs are resolved relative to the main module. The `crsql-multitab.js` entry point needs to know where to find sibling workers:

```javascript
// Current: relative paths (requires same-origin hosting)
const coordinatorUrl = new URL('./coordinator.js', import.meta.url).href;
const providerWorkerUrl = new URL('./provider.js', import.meta.url).href;
```

### Public API Surface

The hosted distribution exports a minimal, stable API:

```typescript
// Main entry point
export { DbClient, createDbClient } from './crsql-multitab.js';

// Types
export type { DbClientOptions, ExecResult, RunResult, CRSQLiteChange } from './index.d.ts';

// Constants (for advanced use)
export { LOCK_PREFIX, PROVIDER_LOCK, CLIENT_LOCK } from './crsql-multitab.js';
```

**Core API (stable)**:
- `DbClient` class — the only thing most users need
- `createDbClient(options)` — factory function alternative

**Internal exports (may change)**:
- RPC helpers (`createRequest`, `createResultResponse`, `createErrorResponse`)
- Lock name generators

### Minimal Working Example

```html
<!DOCTYPE html>
<html>
<head>
  <title>CR-SQLite Demo</title>
</head>
<body>
  <div id="app">Loading...</div>
  <script type="module">
    // Import from hosted ESM
    import { DbClient } from 'https://esm.effect-native.io/libcrsql-browser@0.1.0/crsql-multitab.js';
    
    async function main() {
      const db = new DbClient({ dbName: 'demo' });
      await db.ready;
      
      // Open the database
      await db.open();
      
      // Create a CRDT-enabled table
      await db.exec(`
        CREATE TABLE IF NOT EXISTS notes (
          id TEXT PRIMARY KEY,
          content TEXT,
          updated_at INTEGER
        )
      `);
      await db.exec("SELECT crsql_as_crr('notes')");
      
      // Insert a note
      const id = crypto.randomUUID();
      await db.exec(
        `INSERT INTO notes (id, content, updated_at) VALUES (?, ?, ?)`,
        [id, 'Hello from CR-SQLite!', Date.now()]
      );
      
      // Query
      const rows = await db.query('SELECT * FROM notes');
      document.getElementById('app').textContent = JSON.stringify(rows, null, 2);
    }
    
    main().catch(console.error);
  </script>
</body>
</html>
```

### Browser Requirements & Constraints

#### Required Browser Features

| Feature | Chrome | Firefox | Safari | Why |
|---------|--------|---------|--------|-----|
| **SharedWorker** | 4+ | 29+ | 16+ | Multi-tab coordination |
| **Web Locks API** | 69+ | 96+ | 15.4+ | Provider election |
| **OPFS** | 86+ | 111+ | 15.2+ | Persistent storage |
| **ES Modules in Workers** | 80+ | 114+ | 15+ | `type: "module"` workers |

**Minimum supported**: Chrome 86+, Firefox 114+, Safari 15.4+

#### No COOP/COEP Required

This implementation does NOT require Cross-Origin headers:
- No `Cross-Origin-Opener-Policy: same-origin`
- No `Cross-Origin-Embedder-Policy: require-corp`

Why? We use `opfs-sahpool` style async VFS (read file → modify in memory → write back) instead of synchronous SharedArrayBuffer-based access.

Trade-off: Slightly lower write performance vs. SharedArrayBuffer approach, but massively better deployment compatibility.

#### Cross-Origin Considerations

Workers loaded from a cross-origin CDN face restrictions:

1. **SharedWorker**: Must be same-origin OR use a blob URL wrapper
2. **Dedicated Worker**: Can load cross-origin with `type: "module"`

**Solution for cross-origin hosted distribution**:

```javascript
// crsql-multitab.js does this internally:
async function createSharedWorkerFromUrl(url) {
  // Fetch and wrap in blob for cross-origin compatibility
  const response = await fetch(url);
  const code = await response.text();
  const blob = new Blob([code], { type: 'application/javascript' });
  const blobUrl = URL.createObjectURL(blob);
  return new SharedWorker(blobUrl, { type: 'module' });
}
```

### Implementation Checklist

What needs to be built for hosted distribution:

- [ ] **Blob URL wrapper for SharedWorker** — cross-origin support
- [ ] **Versioned CDN deployment** — GitHub Actions → CDN publish
- [ ] **Use bundled sql-wasm.js** — currently provider.js loads from cdnjs
- [ ] **WASM URL resolution** — provider must find sibling wasm file
- [ ] **Integrity hashes** — optional SRI support for security
- [ ] **Preload hints** — `<link rel="modulepreload">` for performance

### What's Blocked on TS/Publishing Decisions

These items require Tom's sign-off:

1. **Package name**: `@effect-native/libcrsql-browser` vs alternatives
2. **CDN choice**: Self-hosted vs unpkg vs esm.sh vs skypack
3. **Publishing workflow**: Manual vs automated npm+CDN publish
4. **Version strategy**: semver strict vs date-based vs git-sha

### Architecture Reference

```
┌─────────────────────────────────────────────────────────────────┐
│                        Browser Tab                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  import { DbClient } from 'https://cdn/.../crsql.js'    │   │
│  │                                                          │   │
│  │  const db = new DbClient({ dbName: 'app' })             │   │
│  │  await db.ready                                          │   │
│  │  await db.exec('SELECT * FROM todos')                   │   │
│  └─────────────────┬───────────────────────────────────────┘   │
│                    │ MessagePort                                 │
└────────────────────┼─────────────────────────────────────────────┘
                     │
┌────────────────────┼─────────────────────────────────────────────┐
│  SharedWorker      │  coordinator.js                             │
│  ┌─────────────────┴───────────────────────────────────────┐   │
│  │  - Routes requests to provider tab                       │   │
│  │  - Manages client registry                               │   │
│  │  - Handles provider failover                             │   │
│  └─────────────────┬───────────────────────────────────────┘   │
└────────────────────┼─────────────────────────────────────────────┘
                     │ MessagePort
┌────────────────────┼─────────────────────────────────────────────┐
│  Provider Tab      │  (whichever tab holds Web Lock)             │
│  ┌─────────────────┴───────────────────────────────────────┐   │
│  │  Dedicated Worker: provider.js                           │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │  - Loads sql-wasm.js + sql-wasm.wasm            │    │   │
│  │  │  - Opens OPFS database file                      │    │   │
│  │  │  - Executes SQL, returns results                 │    │   │
│  │  │  - Persists to OPFS after writes                 │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

See `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` for the full multi-tab architecture proposal.

---

## Installation (npm)

If you prefer npm over CDN:

```bash
npm install @effect-native/libcrsql-browser
```

## Quick Start

```typescript
import { DbClient } from '@effect-native/libcrsql-browser';

// Create a database client
const db = new DbClient({ dbName: 'myapp' });

// Wait for connection and provider election
await db.ready;

// Open the database
await db.open();

// Create a CRDT-enabled table
await db.exec(`
  CREATE TABLE IF NOT EXISTS todos (
    id TEXT PRIMARY KEY,
    title TEXT,
    done INTEGER DEFAULT 0
  );
  SELECT crsql_as_crr('todos');
`);

// Insert data
await db.exec(
  'INSERT INTO todos (id, title) VALUES (?, ?)',
  [crypto.randomUUID(), 'Buy groceries']
);

// Query data
const rows = await db.query('SELECT * FROM todos WHERE done = 0');
console.log(rows);
```

## Multi-tab Architecture

This package uses a SharedWorker-based architecture for multi-tab coordination:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Tab 1     │     │   Tab 2     │     │   Tab 3     │
│  DbClient   │     │  DbClient   │     │  DbClient   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                    ┌──────┴──────┐
                    │ Coordinator │  (SharedWorker)
                    │  (Router)   │
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │  Provider   │  (Dedicated Worker)
                    │  (SQLite)   │
                    └─────────────┘
```

- **DbClient**: Main API, runs in each tab
- **Coordinator**: SharedWorker that routes messages and elects the provider
- **Provider**: Dedicated Worker that owns the actual SQLite database

One tab is automatically elected as the "provider" and runs the database.
Other tabs proxy their requests through the coordinator.

## CRDT Operations

### Enable CRDT for a Table

```typescript
// After creating a table, enable CRDT tracking
await db.exec("SELECT crsql_as_crr('my_table')");
```

### Get Changes for Sync

```typescript
// Get all changes since version 0
const changes = await db.getChanges(0n);

// Send to server or peer
await syncToServer(changes);
```

### Apply Changes from Sync

```typescript
// Receive changes from server or peer
const remoteChanges = await fetchFromServer();

// Apply them locally
await db.applyChanges(remoteChanges);
```

### Get Current Version

```typescript
const version = await db.getVersion();
console.log('Current DB version:', version);
```

## Configuration

```typescript
const db = new DbClient({
  // Database name (used for lock coordination)
  dbName: 'myapp',

  // Custom path to coordinator SharedWorker
  coordinatorUrl: '/workers/coordinator.js',

  // Custom path to provider Worker
  providerWorkerUrl: '/workers/provider.js',
});
```

## Hosting the Workers (Self-hosted)

If not using the hosted CDN, you need to serve three files:

- `coordinator.js` - SharedWorker for multi-tab coordination
- `provider.js` - Dedicated Worker for SQLite operations  
- `sql-wasm.wasm` - SQLite WASM binary

### Vite

```typescript
// vite.config.ts
export default {
  optimizeDeps: {
    exclude: ['@effect-native/libcrsql-browser']
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          'crsqlite-workers': ['@effect-native/libcrsql-browser']
        }
      }
    }
  }
}
```

### Copy Files

You may need to copy the worker files to your public directory:

```bash
cp node_modules/@effect-native/libcrsql-browser/coordinator.js public/
cp node_modules/@effect-native/libcrsql-browser/provider.js public/
cp node_modules/@effect-native/libcrsql-browser/sql-wasm.wasm public/
```

## Browser Support

- Chrome/Edge 86+ (SharedWorker + Web Locks API + OPFS)
- Firefox 114+ (SharedWorker + Web Locks API + OPFS + ES Module Workers)
- Safari 15.4+ (SharedWorker + Web Locks API)

## API Reference

### `DbClient`

Main database client class.

#### Constructor

```typescript
new DbClient(options: DbClientOptions)
```

#### Methods

| Method | Description |
|--------|-------------|
| `ready: Promise<void>` | Promise that resolves when client is ready |
| `open(): Promise<void>` | Open the database |
| `exec(sql, params?): Promise<ExecResult>` | Execute SQL |
| `query(sql, params?): Promise<Row[]>` | Query and return rows |
| `getChanges(since): Promise<Change[]>` | Get CRDT changes since version |
| `applyChanges(changes): Promise<void>` | Apply CRDT changes |
| `getVersion(): Promise<bigint>` | Get current database version |
| `close(): Promise<void>` | Close database connection |
| `disconnect(): void` | Disconnect from coordinator |

### Types

```typescript
interface DbClientOptions {
  dbName: string;
  coordinatorUrl?: string;
  providerWorkerUrl?: string;
}

interface ExecResult {
  changes: number;
}
```

## Related Packages

- **[@effect-native/libcrsql](https://www.npmjs.com/package/@effect-native/libcrsql)** - CR-SQLite for Node.js/Bun server environments
- [CR-SQLite](https://github.com/vlcn-io/cr-sqlite) - The upstream CR-SQLite project

## License

MIT
