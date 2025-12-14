# 07-fractindex-rust

## Inventory

Main files:
- Fractional key algorithm: `core/rs/fractindex-core/src/fractindex.rs`
- Install ordering machinery: `core/rs/fractindex-core/src/as_ordered.rs`
- View + INSTEAD OF triggers: `core/rs/fractindex-core/src/fractindex_view.rs`
- SQL helpers: `core/rs/fractindex-core/src/util.rs`
- SQLite init / exported UDFs: `core/rs/fractindex-core/src/lib.rs`

Exported SQL functions:
- `crsql_fract_key_between(left, right)`
- `crsql_fract_as_ordered(table, order_col, collection_cols...)`
- `crsql_fract_fix_conflict_return_old_key(...)`

## Runtime Role

`fractindex-core` provides “fractional indexing” ordering keys (lexicographic order encodes list position). It also installs a SQLite-side UX layer:
- triggers that rewrite `-1` / `1` sentinel inserts into computed keys (prepend/append)
- a `"<table>_fractindex"` view with INSTEAD OF triggers that support “insert after” semantics and collision repair

This is adjacent to CR-SQLite replication but not strictly required for CRR functionality; it’s a higher-level ordering tool.

## SQLite API Requirements

- UDF registration and returning TEXT/NULL.
- Trigger/view DDL creation with correct quoting/escaping.
- Uses modern SQLite features:
  - `RETURNING` inside collision-fix function.

## Porting Implications (Zig)

- The core algorithm is byte-oriented over a fixed printable ASCII alphabet. A Zig port should treat keys as bytes (not Unicode codepoints) and preserve:
  - integer-part length encoding based on head char
  - “fractional part must not end with space” constraint
  - midpoint/increment/decrement behavior
- The SQLite integration is the harder part:
  - string-safe SQL generation (ident vs literal escaping)
  - varargs argument parsing convention in `crsql_fract_fix_conflict_return_old_key`
  - deterministic behavior (Rust uses floating midpoint selection; Zig should match exactly or rewrite with equivalent integer logic)

## Risks / Unknowns

- Compatibility risk if midpoint rounding differs.
- Keys rely on ASCII indexing; invalid UTF-8 inputs are assumed not to happen (Rust uses `from_utf8_unchecked`).

## MVP Cut

- If you want a replication-first Zig port: defer fractindex entirely.
- If you want parity with current SQL surface: port `crsql_fract_key_between` first (pure function), then the DDL-installing functions.
