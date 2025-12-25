# Tom blocker: Implementation-agnostic CR-SQLite spec suite

## The idea
Stop comparing multiple implementations (Zig vs Rust/C) forever by defining a **single executable behavior spec suite** that can run against any CR-SQLite implementation.

Instead of “parity tests” (A == B), aim for “spec tests” (A satisfies Spec S).

### Initial sketch (prototype)
- Create a **data-driven spec format** (initially proposed YAML) that describes:
  - setup SQL
  - a sequence of steps
  - expected observations (rows / errors)
- Implement a small **runner** that:
  - loads a given CR-SQLite implementation
  - runs the specs

A very convenient prototype runner would be **Python + sqlite3**, because it can load a `.so/.dylib` and execute SQL.

## Why this is tempting
- The current suite is fragmented:
  - `zig/harness/*.sh` (bash + sqlite CLI)
  - `core/src/*.test.c` (C)
  - `core/rs/integration_check` (Rust)
  - `py/correctness/tests` (Python)
- Zig harness scripts have already hit brittleness issues (shell quoting, platform assumptions).
- A single spec corpus would reduce “N implementations × N tests” growth.

## How to try to invalidate it (failure modes)

### 1) “Implementation agnostic” isn’t true if the runner can’t talk to all implementations
Python can load extensions into CPython’s `sqlite3` driver.
That covers:
- C extension (`core/dist/crsqlite.*`)
- Zig extension (`zig/zig-out/lib/libcrsqlite.*`)

It **does not** cover:
- WASM builds (run inside JS VM)
- iOS/Android packaging where extensions may be compiled in or loaded differently
- any environment without `load_extension()`

If “any CR-SQLite implementation” includes WASM/mobile, a Python runner is not universal.

Mitigation: treat Python as **one runner**, not *the* runner. The spec format must be runner-neutral.

### 2) YAML is a risky interchange format
YAML is human-friendly but costly across runtimes:
- Zig has no YAML stdlib parser
- YAML adds dependency surface and edge cases

Mitigation: choose a minimal, widely supported format (JSON / TOML / a tiny DSL).

### 3) Many CR-SQLite invariants require multi-actor modeling
A big part of correctness is not “single connection executes SQL” but:
- multi-connection behavior
- file-backed DB reopen
- WAL concurrency
- sync protocol via `crsql_changes` copy-and-apply between DBs

A naive spec shape like `{ setup, tests: [{sql, expect}] }` collapses under these.

Mitigation: the spec language must model:
- multiple named connections (actors)
- file DB handles and reopen/close
- sync steps (copy changes since version)

### 4) Output normalization turns the runner into the real oracle
If the runner performs canonicalization (sorting, type coercion, float formatting, blob encoding, error text matching), the runner behavior becomes the “spec”, reintroducing long-term drift.

Mitigation: push canonicalization into SQL itself using `quote()`, `typeof()`, `hex()`, `json_group_array(...)`, etc. Runner should do minimal comparison.

## A more robust direction (likely to survive invalidation)

### Two contracts
1) **Spec format contract (data)**: describes scenarios + expected observations.
2) **Runner/driver contract (mechanism)**: minimal interface for executing SQL, querying rows, and managing connections.

Then multiple runners can exist:
- Python runner for loadable extensions (fast dev loop)
- Node/Bun runner for WASM builds
- “in-app runner” for mobile builds

All consuming the same spec corpus.

### Spec language shape (actor-based)
Instead of “just SQL”, include explicit step types:
- `exec`: run SQL on connection
- `query`: run SQL and assert rows
- `sync`: copy/apply `crsql_changes` from one conn to another
- `close`, `reopen`
- explicit `pragma` / db config steps

Also allow a `requires:` section for capability-based skipping (e.g. WAL, automigrate).

## Cheap falsification test (recommended)
Try expressing the two hardest current tests as specs *without* embedding runner-specific special cases:
1) `zig/harness/test-wal-concurrency.sh`
2) `zig/harness/test-realistic-sync.sh` (or similar multi-db convergence)

If either one forces bespoke runner code (“special-case this test”), the approach is suspect.

## Questions Tom needs to decide
Deferred until after first public release `0.16.300-preview`.

## Pointers
- Zig harness runner: `zig/harness/test-parity.sh`
- Python correctness driver (loads core extension): `py/correctness/src/crsql_correctness/__init__.py`
- Current overall test coverage tracking: `research/zig-cr/92-gap-backlog.md`

## Added
- 2025-12-20
