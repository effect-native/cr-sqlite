//! C bindings for SQLite loadable extension API.
//!
//! This module uses @cImport to include the SQLite header files,
//! providing properly typed access to all SQLite types and structures.
//! This approach ensures ABI compatibility with the actual SQLite library.
//!
//! Reference: `.refs/zig-sqlite/c/loadable_extension.zig`

pub const c = @cImport({
    @cInclude("loadable-ext-sqlite3ext.h");
    @cInclude("workaround.h");
});

/// The global API pointer - set during extension initialization.
/// All SQLite API calls in a loadable extension go through this pointer table.
pub var sqlite3_api: [*c]c.sqlite3_api_routines = null;

// Re-export common C types for convenience
pub const sqlite3 = c.sqlite3;
pub const sqlite3_context = c.sqlite3_context;
pub const sqlite3_value = c.sqlite3_value;
pub const sqlite3_stmt = c.sqlite3_stmt;
pub const sqlite3_module = c.sqlite3_module;
pub const sqlite3_vtab = c.sqlite3_vtab;
pub const sqlite3_vtab_cursor = c.sqlite3_vtab_cursor;
pub const sqlite3_index_info = c.sqlite3_index_info;
pub const sqlite3_int64 = c.sqlite3_int64;
pub const sqlite3_uint64 = c.sqlite3_uint64;
pub const sqlite3_api_routines = c.sqlite3_api_routines;

// Compile-time errors for functions that can't be implemented in Zig
pub const sqlite3_transfer_bindings = @compileError("sqlite3_transfer_bindings is deprecated");
pub const sqlite3_global_recover = @compileError("sqlite3_global_recover is deprecated");
pub const sqlite3_expired = @compileError("sqlite3_expired is deprecated");
pub const sqlite3_mprintf = @compileError("sqlite3_mprintf can't be implemented in Zig");
pub const sqlite3_snprintf = @compileError("sqlite3_snprintf can't be implemented in Zig");
pub const sqlite3_vmprintf = @compileError("sqlite3_vmprintf can't be implemented in Zig");
pub const sqlite3_vsnprintf = @compileError("sqlite3_vsnprintf can't be implemented in Zig");
pub const sqlite3_test_control = @compileError("sqlite3_test_control can't be implemented in Zig");
pub const sqlite3_db_config = @compileError("sqlite3_db_config can't be implemented in Zig");
pub const sqlite3_log = @compileError("sqlite3_log can't be implemented in Zig");
pub const sqlite3_vtab_config = @compileError("sqlite3_vtab_config can't be implemented in Zig");
pub const sqlite3_uri_vsnprintf = @compileError("sqlite3_uri_vsnprintf can't be implemented in Zig");
pub const sqlite3_str_appendf = @compileError("sqlite3_str_appendf can't be implemented in Zig");
pub const sqlite3_str_vappendf = @compileError("sqlite3_str_vappendf can't be implemented in Zig");
