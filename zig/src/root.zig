//! CR-SQLite Zig implementation
//!
//! This is a port of CR-SQLite from C/Rust to Zig.
//! See `research/zig-cr/` for design documents.

pub const automigrate = @import("automigrate.zig");
pub const codec = @import("codec.zig");
pub const compare_values = @import("compare_values.zig");
pub const ffi = @import("ffi/root.zig");
pub const changes_vtab = @import("changes_vtab.zig");
pub const finalize = @import("finalize.zig");
pub const fract_index = @import("fract_index.zig");
pub const pack_columns = @import("pack_columns.zig");
pub const rows_impacted = @import("rows_impacted.zig");
pub const site_identity = @import("site_identity.zig");
pub const stmt_cache = @import("stmt_cache.zig");
pub const sync_bit = @import("sync_bit.zig");
pub const merge_insert = @import("merge_insert.zig");
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

test "merge_integration tests" {
    // Run merge integration tests (oracle-based, document expected behavior)
    _ = @import("merge_integration");
}

test {
    // Run all ffi tests
    _ = ffi;
    // Run all sqlite vtab tests
    _ = sqlite.vtab;
    // Run changes_vtab tests
    _ = changes_vtab;
    // Run compare_values tests
    _ = compare_values;
    // Run fract_index tests
    _ = fract_index;
    // Run pack_columns tests
    _ = pack_columns;
    // Run rows_impacted tests
    _ = rows_impacted;
    // Run site_identity tests
    _ = site_identity;
    // Run stmt_cache tests
    _ = stmt_cache;
    // Run merge_insert tests
    _ = merge_insert;
    // Run sync_bit tests
    _ = sync_bit;
}
