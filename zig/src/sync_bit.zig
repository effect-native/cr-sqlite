//! crsql_internal_sync_bit() UDF for trigger gating
//!
//! This module provides a connection-scoped sync bit that distinguishes between
//! local writes (which should be captured by triggers) and merge writes from
//! the crsql_changes virtual table (which should NOT be captured).
//!
//! Usage:
//!   SELECT crsql_internal_sync_bit();  -- Returns 0 (local) or 1 (merge)
//!
//! The sync bit is:
//! - 0 during normal local writes → triggers fire and capture changes
//! - 1 during merge operations (xUpdate in changes_vtab) → triggers are gated off
//!
//! This prevents infinite loops where merge writes would trigger clock updates,
//! which would then appear as new changes to sync.

const std = @import("std");
const api = @import("ffi/api.zig");

/// Global sync bit state (MVP: single connection)
/// Thread-safety note: This is a simple global for MVP. For multi-connection
/// scenarios, this would need to be per-connection state (stored in extension aux data).
var sync_bit: i64 = 0;

/// Get the current sync bit value
/// Returns 0 for local writes, 1 for merge operations
pub fn get() i64 {
    return sync_bit;
}

/// Set the sync bit value
/// - 0 = local writes (triggers should fire)
/// - 1 = merge operation (triggers should be gated)
pub fn set(value: i64) void {
    sync_bit = value;
}

/// RAII guard for setting sync bit during merge operations
/// Ensures the sync bit is reset even if an error occurs
pub const SyncBitGuard = struct {
    /// Create a guard that sets sync_bit to 1 and resets on deinit
    pub fn init() SyncBitGuard {
        sync_bit = 1;
        return .{};
    }

    /// Reset sync_bit to 0
    pub fn deinit(self: SyncBitGuard) void {
        _ = self;
        sync_bit = 0;
    }
};

/// Implementation of crsql_internal_sync_bit() SQL function
/// Returns the current sync bit value (0 or 1)
fn syncBitFunc(
    pCtx: ?*api.sqlite3_context,
    _: c_int, // argc - unused, this function takes no arguments
    _: [*c]?*api.sqlite3_value, // argv - unused
) callconv(.c) void {
    api.result_int64(pCtx, sync_bit);
}

/// Register the crsql_internal_sync_bit() UDF with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    // SQLITE_INNOCUOUS marks the function as safe for use in untrusted contexts
    // like triggers. Without this flag, SQLite's trusted_schema mechanism would
    // reject the function call inside our trigger WHEN clauses.
    return api.create_function_v2(
        db,
        "crsql_internal_sync_bit",
        0, // no arguments
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

test "sync_bit defaults to 0" {
    // Reset for test isolation
    sync_bit = 0;
    try std.testing.expectEqual(@as(i64, 0), get());
}

test "set changes sync_bit value" {
    sync_bit = 0;

    set(1);
    try std.testing.expectEqual(@as(i64, 1), get());

    set(0);
    try std.testing.expectEqual(@as(i64, 0), get());
}

test "SyncBitGuard sets and resets sync_bit" {
    sync_bit = 0;
    try std.testing.expectEqual(@as(i64, 0), get());

    {
        const guard = SyncBitGuard.init();
        try std.testing.expectEqual(@as(i64, 1), get());
        guard.deinit();
    }

    try std.testing.expectEqual(@as(i64, 0), get());
}

test "SyncBitGuard resets even when used with defer" {
    sync_bit = 0;

    // Simulate merge operation with defer pattern
    {
        const guard = SyncBitGuard.init();
        defer guard.deinit();

        try std.testing.expectEqual(@as(i64, 1), get());
        // Simulating work here...
    }

    // After scope exit, should be reset
    try std.testing.expectEqual(@as(i64, 0), get());
}
