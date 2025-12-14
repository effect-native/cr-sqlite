//! crsql_rows_impacted() UDF and commit hook
//!
//! Provides a counter that tracks how many rows were impacted by sync operations
//! via the crsql_changes virtual table. The counter resets to 0 on COMMIT.
//!
//! Usage:
//!   SELECT crsql_rows_impacted();  -- Returns count of rows impacted since last commit
//!
//! The counter is incremented by changes_vtab.xUpdate when a row is actually modified.

const std = @import("std");
const api = @import("ffi/api.zig");
const site_identity = @import("site_identity.zig");

/// Global counter for rows impacted (MVP: single connection)
/// Thread-safety note: This is a simple global for MVP. For multi-connection
/// scenarios, this would need to be per-connection state.
var rows_impacted_counter: i64 = 0;

/// Increment the counter (called by xUpdate when a row is actually changed)
pub fn incrementRowsImpacted() void {
    rows_impacted_counter += 1;
}

/// Get current count
pub fn getRowsImpacted() i64 {
    return rows_impacted_counter;
}

/// Reset the counter (called on commit)
fn resetCounter() void {
    rows_impacted_counter = 0;
}

/// Implementation of crsql_rows_impacted() SQL function
fn rowsImpactedFunc(
    pCtx: ?*api.sqlite3_context,
    _: c_int,
    _: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    api.result_int64(pCtx, rows_impacted_counter);
}

/// Commit hook callback - resets the counter and commits db_version
fn commitHookCallback(pArg: ?*anyopaque) callconv(.c) c_int {
    _ = pArg;
    // Always commit db_version on commit - pending_db_version being higher
    // than global_db_version indicates local changes occurred (via triggers
    // calling crsql_next_db_version()). The rows_impacted counter only tracks
    // changes via the crsql_changes vtab, but local INSERTs also need tracking.
    site_identity.commitDbVersion();
    resetCounter();
    return 0; // 0 = allow commit to proceed
}

/// Rollback hook callback - resets the counter and pending db_version
fn rollbackHookCallback(pArg: ?*anyopaque) callconv(.c) void {
    _ = pArg;
    site_identity.rollbackDbVersion();
    resetCounter();
}

/// Register the UDF and commit hook
pub fn register(db: ?*api.sqlite3) c_int {
    // Register the function
    const rc = api.create_function_v2(
        db,
        "crsql_rows_impacted",
        0, // no arguments
        api.SQLITE_UTF8,
        null,
        &rowsImpactedFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Install commit hook to reset counter and commit db_version
    _ = api.commit_hook(db, &commitHookCallback, null);

    // Install rollback hook to reset counter and pending db_version
    _ = api.rollback_hook(db, &rollbackHookCallback, null);

    return api.SQLITE_OK;
}

// =============================================================================
// Tests
// =============================================================================

test "incrementRowsImpacted increments counter" {
    // Reset for test isolation
    rows_impacted_counter = 0;

    try std.testing.expectEqual(@as(i64, 0), getRowsImpacted());

    incrementRowsImpacted();
    try std.testing.expectEqual(@as(i64, 1), getRowsImpacted());

    incrementRowsImpacted();
    incrementRowsImpacted();
    try std.testing.expectEqual(@as(i64, 3), getRowsImpacted());
}

test "resetCounter resets to zero" {
    rows_impacted_counter = 42;
    try std.testing.expectEqual(@as(i64, 42), getRowsImpacted());

    resetCounter();
    try std.testing.expectEqual(@as(i64, 0), getRowsImpacted());
}

test "commitHookCallback resets counter and returns 0" {
    rows_impacted_counter = 10;

    const result = commitHookCallback(null);

    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expectEqual(@as(i64, 0), getRowsImpacted());
}
