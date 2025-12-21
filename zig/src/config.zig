//! Configuration API for CR-SQLite
//!
//! Provides:
//! - crsql_config_get(setting_name) - retrieves current config value
//! - crsql_config_set(setting_name, value) - sets config value, persists to DB
//!
//! Known settings:
//!   - 'merge-equal-values': Controls whether merging identical values advances the clock
//!     - 0 (default): Merging same value is a no-op (clock not advanced)
//!     - 1: Merging same value with higher col_version advances db_version
//!
//! Reference: core/rs/core/src/config.rs

const std = @import("std");
const api = @import("ffi/api.zig");

/// Config key for merge-equal-values setting
pub const MERGE_EQUAL_VALUES: []const u8 = "merge-equal-values";

/// Default value for merge-equal-values (0 = disabled, matches Rust/C oracle)
pub const DEFAULT_MERGE_EQUAL_VALUES: i64 = 0;

/// Per-connection config storage.
/// Uses the sqlite3* pointer as a key to store per-connection state.
/// This ensures each connection has its own isolated config values.
const ConnectionConfigMap = struct {
    const MAX_CONNECTIONS = 64;

    entries: [MAX_CONNECTIONS]Entry = [_]Entry{Entry{}} ** MAX_CONNECTIONS,
    count: usize = 0,

    const Entry = struct {
        db: ?*api.sqlite3 = null,
        merge_equal_values: i64 = DEFAULT_MERGE_EQUAL_VALUES,
        initialized: bool = false,
    };

    /// Get merge_equal_values for a connection (returns default if not found)
    fn getMergeEqualValues(self: *ConnectionConfigMap, db: ?*api.sqlite3) i64 {
        if (db == null) return DEFAULT_MERGE_EQUAL_VALUES;
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                return entry.merge_equal_values;
            }
        }
        return DEFAULT_MERGE_EQUAL_VALUES;
    }

    /// Set merge_equal_values for a connection (creates entry if needed)
    fn setMergeEqualValues(self: *ConnectionConfigMap, db: ?*api.sqlite3, value: i64) void {
        if (db == null) return;

        // First, try to find existing entry
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                entry.merge_equal_values = value;
                entry.initialized = true;
                return;
            }
        }

        // Not found, create new entry in first empty slot
        for (&self.entries) |*entry| {
            if (entry.db == null) {
                entry.db = db;
                entry.merge_equal_values = value;
                entry.initialized = true;
                self.count += 1;
                return;
            }
        }

        // Map is full - shouldn't happen in practice
    }

    /// Check if a connection has been initialized with a value
    fn isInitialized(self: *ConnectionConfigMap, db: ?*api.sqlite3) bool {
        if (db == null) return false;
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                return entry.initialized;
            }
        }
        return false;
    }

    /// Remove entry for a connection (called on disconnect)
    fn remove(self: *ConnectionConfigMap, db: ?*api.sqlite3) void {
        if (db == null) return;
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                entry.db = null;
                entry.merge_equal_values = DEFAULT_MERGE_EQUAL_VALUES;
                entry.initialized = false;
                if (self.count > 0) self.count -= 1;
                return;
            }
        }
    }
};

/// Global map of per-connection config values.
var connection_config = ConnectionConfigMap{};

/// Get the current merge_equal_values setting for a specific connection
pub fn getMergeEqualValues(db: ?*api.sqlite3) i64 {
    return connection_config.getMergeEqualValues(db);
}

/// Set the merge_equal_values setting for a specific connection
pub fn setMergeEqualValues(db: ?*api.sqlite3, value: i64) void {
    connection_config.setMergeEqualValues(db, value);
}

/// Clean up connection config state (called when extension unloads from a connection)
pub fn cleanupConnection(db: ?*api.sqlite3) void {
    connection_config.remove(db);
}

/// Load config from database's crsql_master table.
/// Returns null if not found.
fn loadConfigFromDb(db: ?*api.sqlite3, key: []const u8) ?i64 {
    if (db == null) return null;

    var buf: [256]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT value FROM crsql_master WHERE key = 'config.{s}'", .{key}) catch return null;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return null;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return null;
}

/// Save config to database's crsql_master table.
/// Returns true on success.
fn saveConfigToDb(db: ?*api.sqlite3, key: []const u8, value: i64) bool {
    if (db == null) return false;

    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "INSERT OR REPLACE INTO crsql_master (key, value) VALUES ('config.{s}', ?)", .{key}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, value);

    return api.step(stmt) == api.SQLITE_DONE;
}

/// Implementation of crsql_config_get(setting_name) SQL function.
/// Returns the current config value for the given setting name.
/// Returns an error for unknown setting names.
fn configGetFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    if (argc != 1) {
        api.result_error(pCtx, "crsql_config_get requires 1 argument", -1);
        return;
    }

    const db = api.context_db_handle(pCtx);

    // Get the setting name
    const name_ptr = api.value_text(argv[0]);
    if (name_ptr == null) {
        api.result_error(pCtx, "crsql_config_get: setting name must be text", -1);
        return;
    }
    const name: []const u8 = std.mem.span(name_ptr.?);

    // Check for known settings
    if (std.mem.eql(u8, name, MERGE_EQUAL_VALUES)) {
        // Check if we have a cached value for this connection
        if (!connection_config.isInitialized(db)) {
            // Try to load from database
            if (loadConfigFromDb(db, MERGE_EQUAL_VALUES)) |db_value| {
                connection_config.setMergeEqualValues(db, db_value);
            } else {
                // Use default
                connection_config.setMergeEqualValues(db, DEFAULT_MERGE_EQUAL_VALUES);
            }
        }

        api.result_int64(pCtx, connection_config.getMergeEqualValues(db));
        return;
    }

    // Unknown setting name
    api.result_error(pCtx, "Unknown setting name", -1);
}

/// Implementation of crsql_config_set(setting_name, value) SQL function.
/// Sets the config value and persists to database.
/// Returns the value that was set, or an error for unknown setting names.
fn configSetFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    if (argc != 2) {
        api.result_error(pCtx, "crsql_config_set requires 2 arguments", -1);
        return;
    }

    const db = api.context_db_handle(pCtx);

    // Get the setting name
    const name_ptr = api.value_text(argv[0]);
    if (name_ptr == null) {
        api.result_error(pCtx, "crsql_config_set: setting name must be text", -1);
        return;
    }
    const name: []const u8 = std.mem.span(name_ptr.?);

    // Get the value
    const value = api.value_int64(argv[1]);

    // Check for known settings
    if (std.mem.eql(u8, name, MERGE_EQUAL_VALUES)) {
        // Update in-memory cache
        connection_config.setMergeEqualValues(db, value);

        // Persist to database
        if (!saveConfigToDb(db, MERGE_EQUAL_VALUES, value)) {
            api.result_error(pCtx, "Failed to persist config to database", -1);
            return;
        }

        // Return the value that was set
        api.result_int64(pCtx, value);
        return;
    }

    // Unknown setting name
    api.result_error(pCtx, "Unknown setting name", -1);
}

/// Register the config functions with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    // Register crsql_config_get with 1 argument
    var rc = api.create_function_v2(
        db,
        "crsql_config_get",
        1, // 1 argument
        api.SQLITE_UTF8,
        null,
        &configGetFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_config_set with 2 arguments
    rc = api.create_function_v2(
        db,
        "crsql_config_set",
        2, // 2 arguments
        api.SQLITE_UTF8,
        null,
        &configSetFunc,
        null,
        null,
        null,
    );
    return rc;
}

// =============================================================================
// Tests
// =============================================================================

test "default merge_equal_values is 0 (matches Rust/C oracle)" {
    try std.testing.expectEqual(@as(i64, 0), DEFAULT_MERGE_EQUAL_VALUES);
}

test "getMergeEqualValues returns default for null db" {
    try std.testing.expectEqual(DEFAULT_MERGE_EQUAL_VALUES, getMergeEqualValues(null));
}

test "setMergeEqualValues and getMergeEqualValues work correctly" {
    // Use fake db pointers for testing
    const fake_db1: *api.sqlite3 = @ptrFromInt(0x1000);
    const fake_db2: *api.sqlite3 = @ptrFromInt(0x2000);

    // Reset state
    connection_config = ConnectionConfigMap{};

    // Default is 1
    try std.testing.expectEqual(DEFAULT_MERGE_EQUAL_VALUES, getMergeEqualValues(fake_db1));
    try std.testing.expectEqual(DEFAULT_MERGE_EQUAL_VALUES, getMergeEqualValues(fake_db2));

    // Set db1 to 0
    setMergeEqualValues(fake_db1, 0);
    try std.testing.expectEqual(@as(i64, 0), getMergeEqualValues(fake_db1));
    try std.testing.expectEqual(DEFAULT_MERGE_EQUAL_VALUES, getMergeEqualValues(fake_db2)); // db2 unaffected

    // Set db2 to 0
    setMergeEqualValues(fake_db2, 0);
    try std.testing.expectEqual(@as(i64, 0), getMergeEqualValues(fake_db1));
    try std.testing.expectEqual(@as(i64, 0), getMergeEqualValues(fake_db2));

    // Reset db1 to 1
    setMergeEqualValues(fake_db1, 1);
    try std.testing.expectEqual(@as(i64, 1), getMergeEqualValues(fake_db1));
    try std.testing.expectEqual(@as(i64, 0), getMergeEqualValues(fake_db2)); // db2 still 0
}

test "cleanupConnection removes entry" {
    const fake_db: *api.sqlite3 = @ptrFromInt(0x6000);

    // Reset state
    connection_config = ConnectionConfigMap{};

    setMergeEqualValues(fake_db, 0);
    try std.testing.expectEqual(@as(i64, 0), getMergeEqualValues(fake_db));

    cleanupConnection(fake_db);
    try std.testing.expectEqual(DEFAULT_MERGE_EQUAL_VALUES, getMergeEqualValues(fake_db)); // Back to default
}
