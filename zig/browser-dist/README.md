# @effect-native/libcrsql-browser

CR-SQLite for browsers - CRDT-based SQLite replication with multi-tab support.

Part of the [@effect-native/libcrsql](https://github.com/effect-native/cr-sqlite) family. For Node.js/Bun server environments, use `@effect-native/libcrsql` instead.

## Features

- **CRDT Replication**: Conflict-free replicated data types for SQLite
- **Multi-tab Support**: Automatic coordination across browser tabs via SharedWorker
- **WASM SQLite**: Runs entirely in the browser with sql.js
- **Zero Config**: Works out of the box with sensible defaults

## Installation

```bash
npm install @effect-native/libcrsql-browser
```

## Quick Start

```typescript
import { DbClient } from '@effect-native/libcrsql-browser';

// Create a database client
const db = new DbClient({ dbName: 'myapp' });

// Wait for connection and provider election
await db.ready();

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
await db.run(
  'INSERT INTO todos (id, title) VALUES (?, ?)',
  [crypto.randomUUID(), 'Buy groceries']
);

// Query data
const result = await db.exec('SELECT * FROM todos WHERE done = 0');
console.log(result.rows);
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

## Hosting the Workers

The package includes three files that need to be served:

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

- Chrome/Edge 89+ (SharedWorker + Web Locks API)
- Firefox 96+ (SharedWorker + Web Locks API)
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
| `ready(): Promise<void>` | Wait for client to be ready |
| `exec(sql, params?): Promise<ExecResult>` | Execute SQL and return results |
| `run(sql, params?): Promise<RunResult>` | Execute SQL without results |
| `getChanges(since): Promise<Change[]>` | Get CRDT changes since version |
| `applyChanges(changes): Promise<void>` | Apply CRDT changes |
| `getVersion(): Promise<bigint>` | Get current database version |
| `close(): Promise<void>` | Close database connection |

### Types

```typescript
interface ExecResult {
  rows: Record<string, unknown>[];
  changes: number;
}

interface RunResult {
  changes: number;
  lastInsertRowId: number;
}
```

## Related Packages

- **[@effect-native/libcrsql](https://www.npmjs.com/package/@effect-native/libcrsql)** - CR-SQLite for Node.js/Bun server environments
- [CR-SQLite](https://github.com/vlcn-io/cr-sqlite) - The upstream CR-SQLite project

## License

MIT
