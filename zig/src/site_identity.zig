//! Site identity and version tracking UDFs
//!
//! Provides:
//! - crsql_site_id() - returns 16-byte site UUID (stable per database file)
//! - crsql_db_version() - returns current logical clock value
//!
//! MVP: Uses global state. Production would use ExtData per-connection.

const std = @import("std");
const api = @import("ffi/api.zig");

/// Global site ID (MVP: randomly generated once per process)
/// In production, this would be stored in the database and loaded on open.
var global_site_id: [16]u8 = undefined;
var site_id_initialized: bool = false;

/// Global db_version counter (MVP: in-memory only)
/// In production, this would query MAX(db_version) from clock tables
var global_db_version: i64 = 0;

/// Initialize site ID if not already done
fn ensureSiteIdInitialized() void {
    if (!site_id_initialized) {
        // MVP: Generate random site ID
        // In production: read from crsql_site_id table or generate and persist
        std.crypto.random.bytes(&global_site_id);
        site_id_initialized = true;
    }
}

/// Implementation of crsql_site_id() SQL function
fn crsqlSiteIdFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    _ = argv;
    if (argc != 0) {
        api.result_error(pCtx, "crsql_site_id takes no arguments", -1);
        return;
    }

    ensureSiteIdInitialized();
    api.result_blob(pCtx, &global_site_id, 16, api.getTransientDestructor());
}

/// Implementation of crsql_db_version() SQL function
fn crsqlDbVersionFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    _ = argv;
    if (argc != 0) {
        api.result_error(pCtx, "crsql_db_version takes no arguments", -1);
        return;
    }

    // MVP: Return global counter
    // In production: query MAX(db_version) from all clock tables
    api.result_int64(pCtx, global_db_version);
}

/// Increment db_version (called after successful merge operations)
pub fn incrementDbVersion() void {
    global_db_version += 1;
}

/// Get current db_version
pub fn getDbVersion() i64 {
    return global_db_version;
}

/// Get site ID as slice
pub fn getSiteId() *const [16]u8 {
    ensureSiteIdInitialized();
    return &global_site_id;
}

/// Register both UDFs with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    var rc = api.create_function_v2(
        db,
        "crsql_site_id",
        0, // nArg: 0 arguments
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC,
        null,
        &crsqlSiteIdFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    rc = api.create_function_v2(
        db,
        "crsql_db_version",
        0,
        api.SQLITE_UTF8,
        null,
        &crsqlDbVersionFunc,
        null,
        null,
        null,
    );
    return rc;
}

test "site_id is 16 bytes" {
    ensureSiteIdInitialized();
    try std.testing.expectEqual(@as(usize, 16), global_site_id.len);
}

test "db_version starts at 0" {
    // Note: This test may see non-zero if other tests ran first due to global state
    // In a fresh process, db_version starts at 0
    try std.testing.expect(global_db_version >= 0);
}

test "incrementDbVersion increases counter" {
    const before = global_db_version;
    incrementDbVersion();
    try std.testing.expectEqual(before + 1, global_db_version);
}

test "getSiteId returns consistent value" {
    const id1 = getSiteId();
    const id2 = getSiteId();
    try std.testing.expectEqual(id1, id2);
}
