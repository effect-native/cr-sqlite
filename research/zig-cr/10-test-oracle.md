# 10-test-oracle

## Harness Execution Plan

This section documents how to run the existing C test files (`core/src/*.test.c`) against the Zig-built extension to prove behavioral parity.

### Current Test Architecture

The existing C tests are **statically linked** against SQLite + cr-sqlite:

```
tests.c → includes all *.test.c suites
         → links sqlite3-extra.c (SQLite + core_init.c)
         → links Rust bundle (libcrsql_integration_check.a)
         → produces single test binary
```

Key architectural facts:
- Tests use `SQLITE_EXTRA_INIT=core_init` to auto-register the extension
- Tests call `crsql_close(db)` which runs `crsql_finalize()` before `sqlite3_close()`
- Tests use `:memory:` databases throughout (good isolation)
- Tests do NOT use `load_extension()` — the extension is compiled in

### Strategy: Loadable Extension Harness

To test the Zig extension, we create a **separate test harness** that loads the Zig `.so/.dylib` dynamically. This avoids modifying the original C test files.

#### Build Approach

**Option A: Minimal Shim (Recommended for Phase 0)**

Create a thin C shim that:
1. Opens a SQLite connection
2. Loads the Zig extension via `sqlite3_load_extension()`
3. Calls the existing test suite functions

```c
// test-harness.c
#include "sqlite3.h"
#include <stdio.h>

// Forward declare the test suites (from existing test files)
extern void crsqlChangesVtabRowidTestSuite();
extern void crsqlChangesVtabTestSuite();
extern void rowsImpactedTestSuite();
extern void crsqlTestSuite();

// Override crsql_close to NOT call crsql_finalize (loaded extension handles it)
int crsql_close(sqlite3 *db) {
  int rc = sqlite3_exec(db, "SELECT crsql_finalize()", 0, 0, 0);
  rc += sqlite3_close(db);
  return rc;
}

int main(int argc, char *argv[]) {
  sqlite3_enable_load_extension(0, 1); // enable globally
  // Extension auto-loads per-connection via sqlite3_auto_extension if needed
  // OR: each test opens db and does sqlite3_load_extension(db, path, 0, 0)
  
  crsqlChangesVtabRowidTestSuite();
  crsqlChangesVtabTestSuite();
  rowsImpactedTestSuite();
  crsqlTestSuite();
  
  sqlite3_shutdown();
  return 0;
}
```

**Option B: Per-Connection Load (More Isolation)**

Modify each test's `sqlite3_open()` call to immediately load the extension:

```c
static sqlite3 *openWithExtension(const char *path) {
  sqlite3 *db;
  int rc = sqlite3_open(path, &db);
  if (rc != SQLITE_OK) return NULL;
  
  char *errmsg = 0;
  rc = sqlite3_load_extension(db, getenv("ZIG_CRSQLITE_PATH"), 0, &errmsg);
  if (rc != SQLITE_OK) {
    fprintf(stderr, "Extension load failed: %s\n", errmsg);
    sqlite3_free(errmsg);
    sqlite3_close(db);
    return NULL;
  }
  return db;
}
```

### Extension Loading: `sqlite3_load_extension()` vs `sqlite3_auto_extension()`

| Method | Pros | Cons |
|--------|------|------|
| `sqlite3_load_extension()` | Per-connection, explicit | Must call after each `sqlite3_open()` |
| `sqlite3_auto_extension()` | Auto-registers for all connections | Global state, tricky cleanup |

**Recommendation**: Use `sqlite3_load_extension()` per connection. The tests already open fresh `:memory:` databases frequently, so the overhead is negligible and isolation is cleaner.

### Test Isolation

All existing tests already use `:memory:` databases:
- `sqlite3_open(":memory:", &db)` appears in every test
- Each test function is self-contained
- `crsql_close()` is called at the end of each test

This is ideal — no file cleanup needed, no cross-test contamination.

### Execution Command (Nix-based)

```bash
# Build the Zig extension
nix build .#zig-crsqlite-linux

# Build the test harness (links test files + vanilla SQLite)
nix build .#zig-test-harness

# Run tests
ZIG_CRSQLITE_PATH=./result/lib/crsqlite.so ./result/bin/crsql-test
```

Or as a single combined step in `flake.nix`:

```nix
packages.zig-test = pkgs.runCommand "zig-crsqlite-test" {
  buildInputs = [ packages.zig-crsqlite packages.zig-test-harness ];
} ''
  export ZIG_CRSQLITE_PATH=${packages.zig-crsqlite}/lib/crsqlite.so
  ${packages.zig-test-harness}/bin/crsql-test
  touch $out
'';
```

### Phased Test Ordering

Tests are ordered by dependency complexity and feature coverage:

| Phase | Test File | Key Coverage | Dependencies |
|-------|-----------|--------------|--------------|
| **1** | `changes-vtab-rowid.test.c` | Rowid slab allocation, `ROWID_SLAB_SIZE` | `crsql_as_crr`, basic vtab read |
| **2** | `changes-vtab.test.c` | PK blob encoding, filters (`site_id`, `db_version`) | Phase 1 + codec |
| **3** | `ext-data.test.c` | `ExtData` lifecycle, version tracking | Core init |
| **4** | `is-crr.test.c` | CRR detection utilities | Schema introspection |
| **5** | `rows-impacted.test.c` | Merge apply, `crsql_rows_impacted()` | Writable vtab, merge engine |
| **6** | `crsqlite.test.c` | Full e2e sync, alter workflow | All previous |

**Start with Phase 1** (`changes-vtab-rowid.test.c`):
- Smallest test file (118 lines, 1 active test)
- Tests rowid calculation which is pure logic
- Exercises `crsql_as_crr` and read path
- Uses `ROWID_SLAB_SIZE` constant (must match: `10000000000000`)

### Required Test Modifications

The existing tests have minimal coupling to the Rust implementation:

1. **`crsql_close()` function**: Already a C wrapper, just needs to exist in harness
2. **`#include "rust.h"`**: Only in `crsqlite.test.c` — can be stubbed or removed for Zig builds
3. **`crsql_integration_check()`**: Rust-specific integration test, skip for Zig harness

No other test modifications are required if the Zig extension exports the same SQL surface:
- `crsql_as_crr(table_name)`
- `crsql_site_id()`
- `crsql_db_version()`
- `crsql_rows_impacted()`
- `crsql_finalize()`
- `crsql_pack_columns(...)`
- `crsql_changes` virtual table (read + write)

### Minimal Test Runner (Shell + SQLite CLI)

For early smoke testing before the full harness exists:

```bash
#!/usr/bin/env bash
# smoke-test.sh - Load extension and run basic assertions

SQLITE="nix run github:subtleGradient/sqlite-cr --"
EXT_PATH="${ZIG_CRSQLITE_PATH:-./zig-out/lib/crsqlite.so}"

$SQLITE << 'EOF'
-- Test 1: Extension loads and provides version
SELECT crsql_version();

-- Test 2: Can create a CRR
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b);
SELECT crsql_as_crr('foo');

-- Test 3: Changes vtab exists and is readable
INSERT INTO foo VALUES (1, 2);
SELECT count(*) FROM crsql_changes;

-- Test 4: PK blob encoding matches expected format
SELECT quote(pk) FROM crsql_changes;
-- Expected: X'01090X' pattern

-- Test 5: Cleanup
SELECT crsql_finalize();
EOF
```

### Build Integration Points

The harness needs to compile these existing files:
- `core/src/tests.c` (test runner main, needs modification)
- `core/src/changes-vtab-rowid.test.c`
- `core/src/changes-vtab.test.c`
- `core/src/rows-impacted.test.c`
- `core/src/crsqlite.test.c`
- `core/src/ext-data.test.c`
- `core/src/is-crr.test.c`

Against:
- System SQLite headers (`sqlite3.h`, `sqlite3ext.h`)
- System SQLite library (`-lsqlite3`)

NOT linked:
- `core/src/crsqlite.c` (C implementation — we're testing Zig)
- `core/rs/*` (Rust bundle — replaced by Zig)
- `core/src/sqlite/sqlite3.c` (use system SQLite for loadable extension support)

### Symbol Requirements for Zig Extension

The Zig extension must export the entry point:

```c
// Required for sqlite3_load_extension()
int sqlite3_crsqlite_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
);
```

This function must register:
- All `crsql_*` scalar functions
- The `crsql_changes` virtual table module
- Commit/rollback hooks for clock management

### CI Integration

Add to `.github/workflows/`:

```yaml
zig-oracle-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: cachix/install-nix-action@v27
    - run: nix build .#zig-crsqlite
    - run: nix build .#zig-test-harness
    - run: nix run .#zig-test
```

---

## Inventory

Primary C tests:
- `core/src/crsqlite.test.c` (end-to-end sync and alter)
- `core/src/is-crr.test.c` (CRR detection)
- `core/src/rows-impacted.test.c` (merge telemetry)
- `core/src/changes-vtab.test.c` (filters + pk blob bytes)
- `core/src/changes-vtab-rowid.test.c` (rowid slab semantics)

## Runtime Role

These tests define the behavioral contract the Zig port must match for compatibility:
- replication pull via `SELECT * FROM crsql_changes ...`
- replication apply via `INSERT INTO crsql_changes VALUES (...)`
- correct change filtering (site_id, db_version)
- stable ordering and rowid slab allocation
- correct pk blob encoding
- correct merge semantics (winner selection and delete semantics)
- correct schema-alter workflow via `crsql_begin_alter` / `crsql_commit_alter`

## SQLite API Requirements

- Must support `load_extension` surface and provide `crsql_*` UDFs.
- Must support vtabs including writable vtabs (`crsql_changes`).
- Must support modern SQLite features exercised indirectly:
  - triggers
  - `RETURNING`
  - `STRICT` tables / `WITHOUT ROWID`

## Porting Implications (Zig)

A Zig rewrite should treat these test patterns as acceptance criteria:
- Sync loop pattern:
  - read: `SELECT * FROM crsql_changes WHERE db_version > ? AND site_id IS NOT ?`
  - apply: `INSERT INTO crsql_changes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
- Site-id semantics:
  - local site id from `crsql_site_id()`
  - remote site IDs propagate when changes are relayed (site_id is preserved)
- Filtering semantics:
  - tests prefer `site_id IS crsql_site_id()` / `IS NOT` over `!=` due to NULL semantics
- Rowid slabs:
  - `_rowid_` values must match `ROWID_SLAB_SIZE` offsets exactly
- Rows impacted:
  - `crsql_rows_impacted()` increments only when merge actually modifies base state
  - resets after commit

## Risks / Unknowns

- Some tests include comments acknowledging known vtab constraint quirks; match their chosen SQL forms to avoid false negatives.

## MVP Cut

If you want a staged port:
1) Pass `changes-vtab-rowid.test.c` + `changes-vtab.test.c` first (read path + pk encoding).
2) Then pass `rows-impacted.test.c` (merge write path + telemetry).
3) Finally pass `crsqlite.test.c` (full replication and alter workflow).
