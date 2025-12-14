# 09-storage-serialization

## Inventory

Primary encoding/decoding:
- Packed column blob UDF: `core/rs/core/src/pack_columns.rs`
- Unpack vtab: `core/rs/core/src/unpack_columns_vtab.rs`
- Integration test documenting packed blob bytes: `core/rs/integration_check/src/t/pack_columns.rs`

Where packed blobs are used:
- PK blob in `crsql_changes`: `core/rs/core/src/changes_vtab_read.rs` (produces) and `changes_vtab.rs` / `changes_vtab_write.rs` (consumes)

Other serialization-ish areas:
- `crsql_sha` returns build SHA (not part of replication wire format): `core/rs/core/src/sha.rs`

## Runtime Role

CR-SQLite uses a custom packed binary format to represent a tuple of SQLite values. This blob format is used as the replication-facing primary key representation (`crsql_changes.pk`).

Because replication reads `pk` from `crsql_changes` and writes it back into another DB’s `crsql_changes`, this is effectively a wire format and must remain stable.

## SQLite API Requirements

- Must read and write blobs/text/ints/floats from SQLite values (UDF arguments and vtab columns).
- Must return BLOB results for packed values.

## Porting Implications (Zig)

### Packed-column blob format (as implemented)
- Starts with `num_columns: u8`.
- Then for each column:
  - `type_byte: u8` where:
    - low 3 bits = column type tag (matches `sqlite_nostd::ColumnType` numeric values)
    - high 5 bits = `intlen` (# bytes used for integer payload or length)
  - Payload depends on type:
    - NULL: none
    - FLOAT: 8 bytes f64
    - INTEGER: `intlen` bytes signed int, big-endian
    - TEXT/BLOB: `intlen` bytes length (signed int interpreted as usize) then payload bytes

### Stability constraints
- ColumnType numeric values are baked into the format (`Integer=1, Float=2, Text=3, Blob=4, Null=5`).
- Integer and length encoding is big-endian.
- No version/checksum byte exists; evolution requires a new format.
- TEXT decoding in Rust uses `from_utf8_unchecked`; Zig should decide whether to validate UTF-8 or match permissive behavior.

## Risks / Unknowns

- Any mismatch in blob encoding breaks replication between implementations.
- `.refs/zig-sqlite` currently decodes blobs via `sqlite3_value_text` in its helper, which would corrupt binary payloads; a Zig CR-SQLite implementation must use `sqlite3_value_blob` for blob arguments.

## MVP Cut

- Implement `crsql_pack_columns` and `unpack_columns` first; they are exercised by C tests and are core to replication.
- Defer unrelated introspection UDFs (`crsql_sha`) and any additional serialization until replication works.
