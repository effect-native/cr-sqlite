//! CR-SQLite Zig implementation
//!
//! This is a port of CR-SQLite from C/Rust to Zig.
//! See `research/zig-cr/` for design documents.

pub const codec = @import("codec.zig");

test "oracles compile" {
    // Ensure the oracle modules are discovered and compiled under `zig build test`.
    _ = @import("golden_vectors");
    _ = @import("merge_oracle");
    try @import("std").testing.expect(true);
}
