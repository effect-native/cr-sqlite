//! Statement cache for CR-SQLite
//!
//! Provides caching of frequently-used prepared statements to improve performance.
//! Statements are prepared once and reused, avoiding repeated parsing and compilation.
//!
//! Key concepts:
//! - Global statements: Site ordinal lookups, clock table queries
//! - Per-table statements: Managed separately via TableInfo (future)
//! - Version tracking: Schema/data version for cache invalidation
//!
//! Based on Rust impl: `core/rs/core/src/stmt_cache.rs`

const std = @import("std");
const api = @import("ffi/api.zig");

/// Statement cache for managing frequently-used prepared statements.
/// Caches statements at the database connection level for reuse.
pub const StmtCache = struct {
    /// Database connection handle
    db: ?*api.sqlite3,

    // =========================================================================
    // Global cached statements
    // =========================================================================

    /// PRAGMA schema_version - for detecting schema changes
    pragma_schema_version: ?*api.sqlite3_stmt = null,

    /// PRAGMA data_version - for detecting data changes
    pragma_data_version: ?*api.sqlite3_stmt = null,

    /// SELECT ordinal FROM crsql_site_id WHERE site_id = ?
    select_site_ordinal: ?*api.sqlite3_stmt = null,

    /// INSERT INTO crsql_site_id (site_id) VALUES (?) RETURNING ordinal
    insert_site_ordinal: ?*api.sqlite3_stmt = null,

    /// SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%__crsql_clock'
    select_clock_tables: ?*api.sqlite3_stmt = null,

    // =========================================================================
    // Version tracking for cache invalidation
    // =========================================================================

    /// Last known schema version (from PRAGMA schema_version)
    schema_version: i64 = -1,

    /// Last known data version (from PRAGMA data_version)
    data_version: i64 = -1,

    /// Create a new statement cache for a database connection.
    /// Caller is responsible for calling deinit() when done.
    pub fn init(db: ?*api.sqlite3) !*StmtCache {
        const ptr = api.malloc(@sizeOf(StmtCache));
        if (ptr == null) return error.OutOfMemory;

        const self: *StmtCache = @ptrCast(@alignCast(ptr));
        self.* = StmtCache{
            .db = db,
            .pragma_schema_version = null,
            .pragma_data_version = null,
            .select_site_ordinal = null,
            .insert_site_ordinal = null,
            .select_clock_tables = null,
            .schema_version = -1,
            .data_version = -1,
        };
        return self;
    }

    /// Release all cached statements and free the cache.
    pub fn deinit(self: *StmtCache) void {
        // Finalize all cached statements
        if (self.pragma_schema_version) |stmt| _ = api.finalize(stmt);
        if (self.pragma_data_version) |stmt| _ = api.finalize(stmt);
        if (self.select_site_ordinal) |stmt| _ = api.finalize(stmt);
        if (self.insert_site_ordinal) |stmt| _ = api.finalize(stmt);
        if (self.select_clock_tables) |stmt| _ = api.finalize(stmt);

        // Clear pointers (not strictly necessary, but good hygiene)
        self.pragma_schema_version = null;
        self.pragma_data_version = null;
        self.select_site_ordinal = null;
        self.insert_site_ordinal = null;
        self.select_clock_tables = null;

        // Free the cache struct itself
        api.free(self);
    }

    /// Check if schema version has changed since last check.
    /// Returns true if schema changed (cache should be invalidated).
    pub fn checkSchemaVersion(self: *StmtCache) !bool {
        const stmt = try self.getOrPrepare(
            &self.pragma_schema_version,
            "PRAGMA schema_version",
        );

        const rc = api.step(stmt);
        if (rc != api.SQLITE_ROW) {
            resetStmt(stmt);
            return error.QueryFailed;
        }

        const current = api.column_int64(stmt, 0);
        resetStmt(stmt);

        if (current != self.schema_version) {
            self.schema_version = current;
            return true;
        }
        return false;
    }

    /// Check if data version has changed since last check.
    /// Returns true if data changed.
    pub fn checkDataVersion(self: *StmtCache) !bool {
        const stmt = try self.getOrPrepare(
            &self.pragma_data_version,
            "PRAGMA data_version",
        );

        const rc = api.step(stmt);
        if (rc != api.SQLITE_ROW) {
            resetStmt(stmt);
            return error.QueryFailed;
        }

        const current = api.column_int64(stmt, 0);
        resetStmt(stmt);

        if (current != self.data_version) {
            self.data_version = current;
            return true;
        }
        return false;
    }

    /// Get or prepare a statement, storing it in the cache slot.
    fn getOrPrepare(
        self: *StmtCache,
        slot: *?*api.sqlite3_stmt,
        sql: [*:0]const u8,
    ) !*api.sqlite3_stmt {
        if (slot.*) |existing| {
            return existing;
        }

        var stmt: ?*api.sqlite3_stmt = null;
        const rc = api.prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != api.SQLITE_OK) {
            return error.PrepareFailed;
        }

        slot.* = stmt;
        return stmt.?;
    }

    /// Clear all cached statements (for schema change invalidation).
    /// Does NOT free the StmtCache itself.
    pub fn clearStatements(self: *StmtCache) void {
        if (self.pragma_schema_version) |stmt| _ = api.finalize(stmt);
        if (self.pragma_data_version) |stmt| _ = api.finalize(stmt);
        if (self.select_site_ordinal) |stmt| _ = api.finalize(stmt);
        if (self.insert_site_ordinal) |stmt| _ = api.finalize(stmt);
        if (self.select_clock_tables) |stmt| _ = api.finalize(stmt);

        self.pragma_schema_version = null;
        self.pragma_data_version = null;
        self.select_site_ordinal = null;
        self.insert_site_ordinal = null;
        self.select_clock_tables = null;
    }
};

/// Reset a statement for reuse (clear bindings and reset state).
/// Safe to call with null.
pub fn resetStmt(stmt: ?*api.sqlite3_stmt) void {
    if (stmt == null) return;
    _ = api.reset(stmt);
    // Note: SQLite's sqlite3_clear_bindings is not exposed in the API wrapper yet
    // For now, reset() is sufficient as new bindings will overwrite old ones
}

/// Prepare a statement if it doesn't exist, otherwise return existing.
/// This is the standalone helper function for one-off cached statements.
pub fn prepareOnce(
    db: ?*api.sqlite3,
    sql: [*:0]const u8,
    stmt_ptr: *?*api.sqlite3_stmt,
) !*api.sqlite3_stmt {
    if (stmt_ptr.*) |existing| {
        return existing;
    }

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) {
        return error.PrepareFailed;
    }

    stmt_ptr.* = stmt;
    return stmt.?;
}

/// Finalize a cached statement and clear its pointer.
/// Safe to call with null pointer.
pub fn finalizeStmt(stmt_ptr: *?*api.sqlite3_stmt) void {
    if (stmt_ptr.*) |stmt| {
        _ = api.finalize(stmt);
        stmt_ptr.* = null;
    }
}

// =============================================================================
// Tests
// =============================================================================

test "StmtCache struct has expected fields" {
    // Verify the struct layout matches what we designed
    const cache = StmtCache{
        .db = null,
    };
    try std.testing.expectEqual(@as(?*api.sqlite3, null), cache.db);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), cache.pragma_schema_version);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), cache.pragma_data_version);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), cache.select_site_ordinal);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), cache.insert_site_ordinal);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), cache.select_clock_tables);
    try std.testing.expectEqual(@as(i64, -1), cache.schema_version);
    try std.testing.expectEqual(@as(i64, -1), cache.data_version);
}

test "resetStmt handles null safely" {
    // Should not crash with null
    resetStmt(null);
}

test "finalizeStmt handles null pointer safely" {
    var stmt_ptr: ?*api.sqlite3_stmt = null;
    // Should not crash
    finalizeStmt(&stmt_ptr);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), stmt_ptr);
}
