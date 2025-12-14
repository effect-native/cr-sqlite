# CR-SQLite Zig Implementation

A pure Zig port of [CR-SQLite](https://github.com/vlcn-io/cr-sqlite), providing conflict-free replicated database functionality as a SQLite extension.

## Status

**MVP COMPLETE** — 154/154 tests passing (100%)

| Feature | Status | Notes |
|---------|--------|-------|
| Core replication | ✅ Complete | 52 parity tests pass |
| Browser WASM | ✅ Complete | 18 tests pass via Playwright |
| Multi-tab web | ✅ Complete | SharedWorker + OPFS + re-election |
| Fractional indexing | ✅ Complete | All UDFs implemented |
| C oracle tests | ✅ Complete | 20/20 pass (5 suites) |

**Test Breakdown:**
- Zig unit tests: 64/64
- Shell parity tests: 52/52
- Browser WASM tests: 18/18
- C oracle harness: 20/20

### Implemented Functions

- `crsql_version()` - Extension version
- `crsql_site_id()` - 16-byte unique site identifier
- `crsql_db_version()` - Database version clock
- `crsql_as_crr(table)` - Convert table to CRR
- `crsql_is_crr(table)` - Check if table is a CRR
- `crsql_rows_impacted()` - Rows changed in current transaction
- `crsql_finalize()` - Cleanup before close
- `crsql_begin_alter(table)` / `crsql_commit_alter(table)` - Schema migration workflow
- `crsql_fract_key_between(a, b)` - Fractional index generation
- `crsql_fract_as_ordered(table, order_col, ...)` - Ordered collection view + triggers
- `crsql_fract_fix_conflict_return_old_key(...)` - Collision repair
- `crsql_changes` - Virtual table for sync

### Known Limitations

Post-MVP items not yet implemented:
- Performance: `PRAGMA schema_version` caching, `SQLITE_PREPARE_PERSISTENT`
- Web: Service Worker fallback (for environments without SharedWorker)
- Web: Reactive query subscriptions in RPC interface
- Packaging: Windows `.dll` build, iOS/Android static embedding guides
- Packaging: macOS universal binary (aarch64 + x86_64)

## Build Instructions

### Prerequisites

- [Nix](https://nixos.org/) (recommended) or Zig 0.13+
- For browser tests: Node.js 18+

### Native Build

```bash
cd zig

# Using Nix (recommended)
nix run nixpkgs#zig -- build

# Or with system Zig
zig build
```

Output: `zig-out/lib/libcrsqlite.{dylib,so}`

### WASM Build

```bash
cd zig

# Build WASM static library
nix run nixpkgs#zig -- build wasm
```

Output:
- `zig-out/lib/libcrsqlite.a` - Static library for embedding
- `zig-out/lib/crsqlite.wasm` - Standalone WASM object

## Test Instructions

### Run All Tests

```bash
cd zig
make test
```

Runs unit tests, parity tests, and browser tests concurrently.

### Individual Test Suites

```bash
# Zig unit tests
make test-unit

# Shell parity tests (validates against C test contracts)
make test-parity

# Browser tests (Playwright + sql.js)
make test-browser
```

### C Oracle Tests

```bash
cd zig/harness/c-oracle
make test
```

Runs original C test files against the Zig extension.

## Directory Structure

```
zig/
├── src/                    # Main Zig source code
│   ├── root.zig           # Extension entry point
│   ├── as_crr.zig         # crsql_as_crr implementation
│   ├── changes_vtab.zig   # crsql_changes virtual table
│   ├── merge_insert.zig   # CRDT merge logic
│   ├── codec.zig          # Primary key encoding/decoding
│   ├── fract_index.zig    # Fractional indexing
│   ├── pack_columns.zig   # Column packing for wire format
│   ├── site_identity.zig  # Site ID management
│   ├── stmt_cache.zig     # Prepared statement caching
│   └── ffi/               # SQLite C FFI bindings
│       ├── api.zig        # High-level API
│       └── c/             # C headers and workarounds
├── test/                   # Test utilities
│   ├── golden_vectors.zig # Known-good test vectors
│   ├── merge_oracle.zig   # Merge behavior oracle
│   └── merge_integration.zig
├── harness/                # Integration test harness
│   ├── test-parity.sh     # Main parity test runner
│   ├── test-merge.sh      # Merge semantics tests
│   ├── test-filters.sh    # Filter pushdown tests
│   ├── test-alter.sh      # Schema alter tests
│   ├── test-noops.sh      # No-op stability tests
│   └── c-oracle/          # C test oracle harness
├── browser-test/           # Browser/WASM tests
│   ├── tests/             # Playwright test specs
│   ├── fixtures/          # Test HTML and WASM files
│   └── src/               # Multi-tab coordination code
├── wasm-build/             # WASM build scripts
├── build.zig              # Zig build configuration
└── Makefile               # Unified test runner
```

## Usage

### Loading the Extension

```bash
# Using sqlite3 CLI
sqlite3 :memory: -cmd '.load ./zig-out/lib/libcrsqlite.dylib'

# Or via Nix
nix run nixpkgs#sqlite -- :memory: -cmd '.load ./zig-out/lib/libcrsqlite.dylib'
```

### Basic Usage

```sql
-- Create a table
CREATE TABLE todos (id INTEGER PRIMARY KEY, title TEXT, done INTEGER);

-- Convert to CRR (conflict-free replicated relation)
SELECT crsql_as_crr('todos');

-- Insert data (automatically tracked)
INSERT INTO todos VALUES (1, 'Buy milk', 0);

-- View changes for sync
SELECT * FROM crsql_changes WHERE db_version > 0;

-- Check database version
SELECT crsql_db_version();

-- Get site identifier
SELECT hex(crsql_site_id());
```

### Syncing Between Databases

```sql
-- On Database A: Get changes since version X
SELECT * FROM crsql_changes WHERE db_version > ?;

-- On Database B: Apply changes from A
INSERT INTO crsql_changes (table, pk, cid, val, col_version, db_version, site_id, cl, seq)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
```

## Development

### Running Tests During Development

```bash
# Quick feedback loop
cd zig && nix run nixpkgs#zig -- build test

# Full test suite
cd zig && make test
```

### Adding New Tests

- Unit tests: Add to the relevant `src/*.zig` file
- Parity tests: Add to `harness/test-parity.sh` or create new `test-*.sh`
- Browser tests: Add to `browser-test/tests/*.spec.ts`

## References

- [CR-SQLite Documentation](https://vlcn.io/docs/cr-sqlite/intro)
- [Wire Format Spec](../research/zig-cr/09-storage-serialization.md)
- [Merge Semantics](../research/zig-cr/05-conflict-resolution-semantics.md)
- [Test Oracle Strategy](../research/zig-cr/10-test-oracle.md) - Behavioral contract and acceptance criteria
- [C Test Oracle Source](../core/src/*.test.c) - Authoritative test suite
- [Gap Backlog](../research/zig-cr/92-gap-backlog.md) - Current status and remaining work
