# 22-bun-best-practices

## Inventory

Representative files:
- MySQL protocol parsing:
  - `.refs/bun/src/sql/mysql/protocol/NewReader.zig`
  - `.refs/bun/src/sql/mysql/protocol/StackReader.zig`
  - `.refs/bun/src/sql/mysql/protocol/NewWriter.zig`
  - `.refs/bun/src/sql/mysql/protocol/HandshakeV10.zig`
  - `.refs/bun/src/sql/mysql/protocol/ResultSet.zig`
- Postgres protocol parsing:
  - `.refs/bun/src/sql/postgres/protocol/NewReader.zig`
  - `.refs/bun/src/sql/postgres/protocol/NewWriter.zig`
  - `.refs/bun/src/sql/postgres/protocol/Authentication.zig`
  - `.refs/bun/src/sql/postgres/protocol/ErrorResponse.zig`
- Ownership model for bytes:
  - `.refs/bun/src/sql/shared/Data.zig`

## Runtime Role

Bun’s SQL protocol implementations demonstrate scalable Zig patterns for:
- framing and parsing binary protocols
- explicit ownership of bytes (borrowed vs owned vs inline)
- error mapping and cleanup

## SQLite API Requirements

None (this is Zig best-practices reference).

## Porting Implications (Zig)

Patterns to reuse for CR-SQLite:
- “decodeInternal + wrapper reader” pattern: keep parsing logic pure and transport-adapter separate.
- Use length-accounting invariants and explicit validation rather than ad-hoc parsing.
- Writer pattern: reserve header space then patch length (useful for building binary replication messages if you later add a network protocol).
- Use `Data`-style borrowed/owned/inlined buffers to reduce allocations.
- Use `errdefer` heavily when building complex objects incrementally.

Testing discipline:
- Bun’s core runner does leak detection; emulate this approach for CR-SQLite Zig tests when you start exercising alloc-heavy paths.

## Risks / Unknowns

- Bun’s protocol code is optimized for network IO; CR-SQLite is largely in-process SQLite extension work, but the allocator/ownership patterns transfer well.

## MVP Cut

- Adopt the ownership + `errdefer` patterns immediately.
- Defer the protocol framing patterns until you introduce a standalone sync transport.
