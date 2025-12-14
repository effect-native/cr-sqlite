//! CR-SQLite Zig implementation
//!
//! This is a port of CR-SQLite from C/Rust to Zig.
//! See `research/zig-cr/` for design documents.

pub const codec = @import("codec.zig");
pub const ffi = @import("ffi/root.zig");
pub const changes_vtab = @import("changes_vtab.zig");
pub const pack_columns = @import("pack_columns.zig");
pub const sqlite = struct {
    /// Writable virtual table infrastructure
    pub const vtab = @import("sqlite/vtab.zig");
};

// Re-export the extension entrypoint at the top level for convenience
pub const sqlite3_crsqlite_init = ffi.sqlite3_crsqlite_init;

// Force export of extension entry points for the dynamic library.
// Without this, the linker may eliminate the exported functions.
comptime {
    _ = &ffi.init.sqlite3_crsqlite_init;
}

test "oracles compile" {
    // Ensure the oracle modules are discovered and compiled under `zig build test`.
    _ = @import("golden_vectors");
    _ = @import("merge_oracle");
    try @import("std").testing.expect(true);
}

test {
    // Run all ffi tests
    _ = ffi;
    // Run all sqlite vtab tests
    _ = sqlite.vtab;
    // Run changes_vtab tests
    _ = changes_vtab;
    // Run pack_columns tests
    _ = pack_columns;
}
