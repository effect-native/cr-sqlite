//! Statement cache for CR-SQLite
//!
//! Provides caching of frequently-used prepared statements to improve performance.
//! Statements are prepared once and reused, avoiding repeated parsing and compilation.
//!
//! Key concepts:
//! - Global statements: Site ordinal lookups, clock table queries
//! - Per-table statements: Managed separately via TableInfo (future)
//! - Version tracking: Schema/data version for cache invalidation
//! - Persistent statements: Uses SQLITE_PREPARE_PERSISTENT for long-lived stmts
//! - Amortized checks: Data version checks amortized per-transaction
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

    /// Flag set when schema version changes - allows callers to detect when
    /// their derived artifacts (union queries, table lists) need rebuilding.
    /// Reset to false after being read via schemaVersionChanged().
    schema_changed_flag: bool = false,

    /// Amortization flag for data_version checks within a transaction.
    /// Set to true after the first data_version check in a transaction.
    /// Reset via resetDataVersionCheck() at transaction boundaries.
    data_version_checked_this_txn: bool = false,

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
            .schema_changed_flag = false,
            .data_version_checked_this_txn = false,
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
    /// Also sets schema_changed_flag for callers to detect invalidation.
    pub fn checkSchemaVersion(self: *StmtCache) !bool {
        const stmt = try self.getOrPreparePersistent(
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
            self.schema_changed_flag = true;
            return true;
        }
        return false;
    }

    /// Check and consume the schema-changed flag.
    /// Returns true if schema changed since last call to this method.
    /// Resets the flag after reading, so subsequent calls return false
    /// until schema changes again.
    pub fn schemaVersionChanged(self: *StmtCache) !bool {
        // First, ensure we've checked the schema version
        _ = try self.checkSchemaVersion();

        // Then consume and return the flag
        const changed = self.schema_changed_flag;
        self.schema_changed_flag = false;
        return changed;
    }

    /// Get the current schema version without checking for changes.
    /// Returns the cached value (may be stale if checkSchemaVersion not called).
    pub fn getSchemaVersion(self: *StmtCache) i64 {
        return self.schema_version;
    }

    /// Check if data version has changed since last check.
    /// Returns true if data changed.
    pub fn checkDataVersion(self: *StmtCache) !bool {
        const stmt = try self.getOrPreparePersistent(
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

    /// Amortized data version check - only performs actual PRAGMA query
    /// once per transaction. Subsequent calls return cached result.
    /// Call resetDataVersionCheck() at transaction boundaries.
    pub fn checkDataVersionAmortized(self: *StmtCache) !bool {
        if (self.data_version_checked_this_txn) {
            // Already checked this transaction, return cached result
            // (data_version field is already up-to-date from prior check)
            return false;
        }

        // First check this transaction - do the actual query
        const changed = try self.checkDataVersion();
        self.data_version_checked_this_txn = true;
        return changed;
    }

    /// Reset the data version check amortization flag.
    /// Call this at transaction boundaries (commit/rollback) to ensure
    /// the next transaction performs a fresh data_version check.
    pub fn resetDataVersionCheck(self: *StmtCache) void {
        self.data_version_checked_this_txn = false;
    }

    /// Get the current data version without checking for changes.
    /// Returns the cached value (may be stale if checkDataVersion not called).
    pub fn getDataVersion(self: *StmtCache) i64 {
        return self.data_version;
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

    /// Get or prepare a persistent statement, storing it in the cache slot.
    /// Uses SQLITE_PREPARE_PERSISTENT flag for long-lived statements.
    /// This is optimal for statements that will be executed many times
    /// as SQLite avoids using lookaside memory for the prepared statement.
    fn getOrPreparePersistent(
        self: *StmtCache,
        slot: *?*api.sqlite3_stmt,
        sql: [*:0]const u8,
    ) !*api.sqlite3_stmt {
        if (slot.*) |existing| {
            return existing;
        }

        var stmt: ?*api.sqlite3_stmt = null;
        const rc = api.prepare_v3(
            self.db,
            sql,
            -1,
            api.SQLITE_PREPARE_PERSISTENT,
            &stmt,
            null,
        );
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

/// Prepare a persistent statement if it doesn't exist, otherwise return existing.
/// Uses SQLITE_PREPARE_PERSISTENT for long-lived cached statements.
pub fn prepareOncePersistent(
    db: ?*api.sqlite3,
    sql: [*:0]const u8,
    stmt_ptr: *?*api.sqlite3_stmt,
) !*api.sqlite3_stmt {
    if (stmt_ptr.*) |existing| {
        return existing;
    }

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = api.prepare_v3(
        db,
        sql,
        -1,
        api.SQLITE_PREPARE_PERSISTENT,
        &stmt,
        null,
    );
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
    try std.testing.expectEqual(false, cache.schema_changed_flag);
    try std.testing.expectEqual(false, cache.data_version_checked_this_txn);
}

test "data version check amortization flag" {
    // Test the amortization flag behavior in isolation
    var cache = StmtCache{
        .db = null,
    };

    // Initially not checked
    try std.testing.expectEqual(false, cache.data_version_checked_this_txn);

    // After reset, still not checked
    cache.resetDataVersionCheck();
    try std.testing.expectEqual(false, cache.data_version_checked_this_txn);

    // Manually set checked flag (simulating what checkDataVersionAmortized does)
    cache.data_version_checked_this_txn = true;
    try std.testing.expectEqual(true, cache.data_version_checked_this_txn);

    // Reset clears the flag
    cache.resetDataVersionCheck();
    try std.testing.expectEqual(false, cache.data_version_checked_this_txn);
}

test "schema changed flag behavior" {
    // Test the schema changed flag behavior in isolation
    var cache = StmtCache{
        .db = null,
    };

    // Initially not changed
    try std.testing.expectEqual(false, cache.schema_changed_flag);

    // Manually set (simulating schema version change detection)
    cache.schema_changed_flag = true;
    try std.testing.expectEqual(true, cache.schema_changed_flag);

    // Reading and clearing happens in schemaVersionChanged() which requires a db
    // For unit test, just verify we can clear it
    cache.schema_changed_flag = false;
    try std.testing.expectEqual(false, cache.schema_changed_flag);
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
