# @effect-native/libcrsql

[![npm version](https://badge.fury.io/js/%40effect-native%2Flibcrsql.svg)](https://badge.fury.io/js/%40effect-native%2Flibcrsql)

Pure-Nix CR-SQLite extension for conflict-free replicated databases. Just Works™ everywhere - Mac, Linux, Pi, Docker, Vercel, etc.

## What is CR-SQLite?

CR-SQLite is a run-time loadable extension for SQLite that enables Conflict-free Replicated Data Types (CRDTs). It allows you to create tables that can be replicated across multiple devices/servers and automatically merge changes without conflicts.

This package provides pre-built CR-SQLite extensions via Nix, eliminating the need to build from source.

## Installation

```bash
npm install @effect-native/libcrsql
```

## Quick Start

```javascript
import { pathToCRSQLite } from '@effect-native/libcrsql';
import Database from 'better-sqlite3';

const db = new Database(':memory:');
db.loadExtension(pathToCRSQLite);

// Convert table to conflict-free replicated relation
db.exec(`
  CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
  SELECT crsql_as_crr('users');
`);

// Insert data - changes are automatically tracked
db.exec(`INSERT INTO users (name) VALUES ('Alice')`);

// Get changes for synchronization
const changes = db.prepare(`SELECT * FROM crsql_changes`).all();
console.log('Changes to sync:', changes);
```

## API

### `pathToCRSQLite`

Path to the CR-SQLite extension file. Use this with your SQLite library's `loadExtension()` method.

```javascript
import { pathToCRSQLite } from '@effect-native/libcrsql';
console.log(pathToCRSQLite); // /path/to/crsqlite-darwin-aarch64.dylib
```

### `getExtensionPath()`

Function that returns the path to the CR-SQLite extension.

```javascript
import { getExtensionPath } from '@effect-native/libcrsql';
const extensionPath = getExtensionPath();
```

## CLI Usage

```bash
npx libcrsql-extension-path
# /path/to/crsqlite-darwin-aarch64.dylib
```

## Supported Platforms

- ✅ **macOS** (Intel & Apple Silicon)
- ✅ **Linux** (x86_64 & ARM64)  
- ✅ **Docker** containers
- ✅ **Vercel**, Netlify, Railway
- ✅ **Raspberry Pi** 4+
- ✅ **AWS Lambda** (with custom runtime)

## Database Libraries

Works with any SQLite library that supports loading extensions:

### better-sqlite3
```javascript
import Database from 'better-sqlite3';
import { pathToCRSQLite } from '@effect-native/libcrsql';

const db = new Database('my-app.db');
db.loadExtension(pathToCRSQLite);
```

### sqlite3  
```javascript
import sqlite3 from 'sqlite3';
import { pathToCRSQLite } from '@effect-native/libcrsql';

const db = new sqlite3.Database('my-app.db');
db.loadExtension(pathToCRSQLite);
```

### Bun SQLite
```javascript
import { Database } from 'bun:sqlite';
import { pathToCRSQLite } from '@effect-native/libcrsql';

const db = new Database('my-app.db');
db.loadExtension(pathToCRSQLite);
```

## React Native

This package is for **Node.js/Bun server environments only**. For React Native, use:

- [@op-engineering/op-sqlite](https://www.npmjs.com/package/@op-engineering/op-sqlite)
- [expo-sqlite](https://docs.expo.dev/versions/latest/sdk/sqlite/)

## CR-SQLite Functions

Once loaded, CR-SQLite provides these functions:

- `crsql_as_crr(table_name)` - Convert table to conflict-free replicated relation
- `crsql_version()` - Get CR-SQLite version
- `crsql_changes` - Virtual table containing changes for sync
- `crsql_begin_alter(table_name)` - Begin schema changes
- `crsql_commit_alter(table_name)` - Commit schema changes

See [CR-SQLite Documentation](https://vlcn.io/docs/cr-sqlite/intro) for complete API reference.

## Development

### Prerequisites
- [Nix](https://nixos.org/download.html) package manager
- Node.js 16+

### Building

```bash
# Build CR-SQLite extensions for all platforms
npm run bundle-lib

# Build production package
npm run build-production

# Run tests
npm test
npm run test:docker
```

## Troubleshooting

### "Extension not found" Error

```bash
# Check what platforms are available
npm list @effect-native/libcrsql
ls node_modules/@effect-native/libcrsql/lib/

# Get extension path for debugging  
npx libcrsql-extension-path
```

## Contributing

1. Fork the repository
2. Create your feature branch: `git checkout -b my-feature`
3. Make your changes and run tests: `npm test`
4. Submit a pull request

## License

MIT

## Related

- [CR-SQLite](https://github.com/vlcn-io/cr-sqlite) - The upstream CR-SQLite project
- [@effect-native/libsqlite](https://github.com/effect-native/libsqlite) - Nix-built SQLite library
- [vlcn.io](https://vlcn.io) - CR-SQLite documentation and tools