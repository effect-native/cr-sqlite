//! FFI layer for CR-SQLite loadable extension.
//!
//! This module provides the C ABI interface for SQLite to load CR-SQLite
//! as a dynamic extension (.so/.dylib).

pub const api = @import("api.zig");
pub const init = @import("init.zig");

// Re-export the main entry point for convenience
pub const sqlite3_crsqlite_init = init.sqlite3_crsqlite_init;

test {
    // Run all tests in submodules
    _ = api;
    _ = init;
}
