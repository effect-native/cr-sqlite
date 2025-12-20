//! crsql_internal_sync_bit() UDF for trigger gating
//!
//! This module provides a connection-scoped sync bit that distinguishes between
//! local writes (which should be captured by triggers) and merge writes from
//! the crsql_changes virtual table (which should NOT be captured).
//!
//! Usage:
//!   SELECT crsql_internal_sync_bit();     -- Returns 0 (local) or 1 (merge)
//!   SELECT crsql_internal_sync_bit(1);    -- Sets sync bit to 1, returns 1
//!   SELECT crsql_internal_sync_bit(0);    -- Sets sync bit to 0, returns 0
//!
//! The sync bit is:
//! - 0 during normal local writes → triggers fire and capture changes
//! - 1 during merge operations (xUpdate in changes_vtab) → triggers are gated off
//!
//! This prevents infinite loops where merge writes would trigger clock updates,
//! which would then appear as new changes to sync.
//!
//! IMPORTANT: The sync bit is PER-CONNECTION, not global. This is critical for
//! multi-connection scenarios (connection pools, concurrent operations) where
//! one connection's merge should not suppress change capture on another.

const std = @import("std");
const api = @import("ffi/api.zig");

/// Per-connection sync bit storage.
/// Uses the sqlite3* pointer as a key to store per-connection state.
/// This ensures Connection A's sync_bit=1 doesn't affect Connection B.
const ConnectionSyncBitMap = struct {
    /// Simple fixed-size map of db pointer -> sync_bit value
    /// Using a fixed array avoids heap allocation complexity in the extension.
    /// 64 slots should be more than enough for typical use cases.
    const MAX_CONNECTIONS = 64;

    entries: [MAX_CONNECTIONS]Entry = [_]Entry{Entry{}} ** MAX_CONNECTIONS,
    count: usize = 0,

    const Entry = struct {
        db: ?*api.sqlite3 = null,
        sync_bit: i64 = 0,
    };

    /// Get sync_bit for a connection (returns 0 if not found/registered)
    fn get(self: *ConnectionSyncBitMap, db: ?*api.sqlite3) i64 {
        if (db == null) return 0;
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                return entry.sync_bit;
            }
        }
        return 0; // Default: local writes mode
    }

    /// Set sync_bit for a connection (creates entry if needed)
    fn set(self: *ConnectionSyncBitMap, db: ?*api.sqlite3, value: i64) void {
        if (db == null) return;

        // First, try to find existing entry
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                entry.sync_bit = value;
                return;
            }
        }

        // Not found, create new entry in first empty slot
        for (&self.entries) |*entry| {
            if (entry.db == null) {
                entry.db = db;
                entry.sync_bit = value;
                self.count += 1;
                return;
            }
        }

        // Map is full - this shouldn't happen in practice
        // Fall through silently (conservative: allows writes to proceed)
    }

    /// Remove entry for a connection (called on disconnect)
    fn remove(self: *ConnectionSyncBitMap, db: ?*api.sqlite3) void {
        if (db == null) return;
        for (&self.entries) |*entry| {
            if (entry.db == db) {
                entry.db = null;
                entry.sync_bit = 0;
                if (self.count > 0) self.count -= 1;
                return;
            }
        }
    }
};

/// Global map of per-connection sync bits.
/// Note: This is still global memory, but keyed by connection pointer,
/// so each connection gets its own isolated sync_bit value.
var connection_map = ConnectionSyncBitMap{};

/// Get the current sync bit value for a specific connection
/// Returns 0 for local writes, 1 for merge operations
pub fn getForDb(db: ?*api.sqlite3) i64 {
    return connection_map.get(db);
}

/// Set the sync bit value for a specific connection
/// - 0 = local writes (triggers should fire)
/// - 1 = merge operation (triggers should be gated)
pub fn setForDb(db: ?*api.sqlite3, value: i64) void {
    connection_map.set(db, value);
}

/// Clean up connection state (called when extension unloads from a connection)
pub fn cleanupConnection(db: ?*api.sqlite3) void {
    connection_map.remove(db);
}

/// RAII guard for setting sync bit during merge operations.
/// Ensures the sync bit is reset even if an error occurs.
/// Now stores the connection pointer for per-connection state.
pub const SyncBitGuard = struct {
    db: ?*api.sqlite3,

    /// Create a guard that sets sync_bit to 1 for this connection
    pub fn init(db: ?*api.sqlite3) SyncBitGuard {
        setForDb(db, 1);
        return .{ .db = db };
    }

    /// Reset sync_bit to 0 for this connection
    pub fn deinit(self: SyncBitGuard) void {
        setForDb(self.db, 0);
    }
};

/// Implementation of crsql_internal_sync_bit() SQL function.
/// - With 0 args: returns the current sync bit value (0 or 1)
/// - With 1 arg: sets the sync bit to the argument value and returns it
fn syncBitFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Get the connection handle for per-connection state
    const db = api.context_db_handle(pCtx);

    if (argc == 0) {
        // Getter: return current value
        api.result_int64(pCtx, getForDb(db));
    } else if (argc == 1) {
        // Setter: set value and return it
        const new_value = api.value_int64(argv[0]);
        setForDb(db, new_value);
        api.result_int64(pCtx, new_value);
    } else {
        api.result_error(pCtx, "crsql_internal_sync_bit takes 0 or 1 argument", -1);
    }
}

/// Register the crsql_internal_sync_bit() UDF with a database connection.
/// The function accepts 0 or 1 arguments (-1 for variable args).
pub fn register(db: ?*api.sqlite3) c_int {
    // SQLITE_INNOCUOUS marks the function as safe for use in untrusted contexts
    // like triggers. Without this flag, SQLite's trusted_schema mechanism would
    // reject the function call inside our trigger WHEN clauses.
    //
    // nArg=-1 allows 0 or more arguments (we handle 0 and 1).
    return api.create_function_v2(
        db,
        "crsql_internal_sync_bit",
        -1, // variable arguments (0 or 1)
        api.SQLITE_UTF8 | api.SQLITE_INNOCUOUS,
        null,
        &syncBitFunc,
        null,
        null,
        null,
    );
}

// =============================================================================
// Tests
// =============================================================================

test "sync_bit defaults to 0 for new connection" {
    // A null db should return 0
    try std.testing.expectEqual(@as(i64, 0), getForDb(null));
}

test "setForDb and getForDb work correctly" {
    // Use fake db pointers for testing
    const fake_db1: *api.sqlite3 = @ptrFromInt(0x1000);
    const fake_db2: *api.sqlite3 = @ptrFromInt(0x2000);

    // Reset state
    connection_map = ConnectionSyncBitMap{};

    // Default is 0
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db1));
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db2));

    // Set db1 to 1
    setForDb(fake_db1, 1);
    try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db1));
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db2)); // db2 unaffected

    // Set db2 to 1
    setForDb(fake_db2, 1);
    try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db1));
    try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db2));

    // Reset db1 to 0
    setForDb(fake_db1, 0);
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db1));
    try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db2)); // db2 still 1
}

test "SyncBitGuard sets and resets sync_bit for specific connection" {
    const fake_db1: *api.sqlite3 = @ptrFromInt(0x3000);
    const fake_db2: *api.sqlite3 = @ptrFromInt(0x4000);

    // Reset state
    connection_map = ConnectionSyncBitMap{};

    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db1));
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db2));

    {
        const guard = SyncBitGuard.init(fake_db1);
        try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db1));
        try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db2)); // db2 unaffected!
        guard.deinit();
    }

    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db1));
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db2));
}

test "SyncBitGuard with defer pattern" {
    const fake_db: *api.sqlite3 = @ptrFromInt(0x5000);

    // Reset state
    connection_map = ConnectionSyncBitMap{};

    {
        const guard = SyncBitGuard.init(fake_db);
        defer guard.deinit();

        try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db));
    }

    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db));
}

test "cleanupConnection removes entry" {
    const fake_db: *api.sqlite3 = @ptrFromInt(0x6000);

    // Reset state
    connection_map = ConnectionSyncBitMap{};

    setForDb(fake_db, 1);
    try std.testing.expectEqual(@as(i64, 1), getForDb(fake_db));

    cleanupConnection(fake_db);
    try std.testing.expectEqual(@as(i64, 0), getForDb(fake_db)); // Back to default
}

test "multiple connections are isolated" {
    // Reset state
    connection_map = ConnectionSyncBitMap{};

    // Create several fake connections
    var dbs: [10]*api.sqlite3 = undefined;
    for (&dbs, 0..) |*db, i| {
        db.* = @ptrFromInt(0x10000 + i * 0x100);
    }

    // Set odd-indexed connections to 1
    for (dbs, 0..) |db, i| {
        if (i % 2 == 1) {
            setForDb(db, 1);
        }
    }

    // Verify isolation
    for (dbs, 0..) |db, i| {
        const expected: i64 = if (i % 2 == 1) 1 else 0;
        try std.testing.expectEqual(expected, getForDb(db));
    }
}
