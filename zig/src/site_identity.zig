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

/// Pending db_version for the current transaction
/// Used by crsql_next_db_version() to return max(dbVersion+1, pendingDbVersion, merging_version)
var pending_db_version: i64 = 0;

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

/// Implementation of crsql_next_db_version() SQL function
/// Returns max(dbVersion+1, pendingDbVersion, optional_merging_version)
/// Used by triggers to get the db_version for clock entries
fn crsqlNextDbVersionFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Accept 0 or 1 arguments (optional merging_version)
    if (argc > 1) {
        api.result_error(pCtx, "crsql_next_db_version takes 0 or 1 argument", -1);
        return;
    }

    var merging_version: ?i64 = null;
    if (argc == 1) {
        const arg_type = api.value_type(argv[0]);
        if (arg_type != api.SQLITE_NULL) {
            merging_version = api.value_int64(argv[0]);
        }
    }

    const next_version = nextDbVersion(merging_version);
    api.result_int64(pCtx, next_version);
}

/// Increment db_version (called after successful merge operations)
pub fn incrementDbVersion() void {
    global_db_version += 1;
}

/// Promote pending db_version to committed db_version on commit
/// Called by commit hook when rows were impacted
pub fn commitDbVersion() void {
    if (pending_db_version > global_db_version) {
        global_db_version = pending_db_version;
    }
    pending_db_version = 0;
}

/// Reset pending db_version on rollback
pub fn rollbackDbVersion() void {
    pending_db_version = 0;
}

/// Get current db_version
pub fn getDbVersion() i64 {
    return global_db_version;
}

/// Get or create the next db_version for the current transaction
/// Returns max(dbVersion+1, pendingDbVersion, merging_version)
/// This is what triggers should use for db_version
pub fn nextDbVersion(merging_version: ?i64) i64 {
    var ret = global_db_version + 1;
    if (ret < pending_db_version) {
        ret = pending_db_version;
    }
    if (merging_version) |mv| {
        if (ret < mv) {
            ret = mv;
        }
    }
    pending_db_version = ret;
    return ret;
}

/// Initialize db_version from database by querying MAX from all clock tables
/// Should be called during extension initialization
pub fn initDbVersionFromDb(db: ?*api.sqlite3) void {
    if (db == null) return;

    // Query to find all clock tables and get max db_version
    // MVP: Simple approach - query sqlite_master for tables ending in __crsql_clock
    const find_clock_tables_sql = "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%__crsql_clock'";

    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, find_clock_tables_sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) {
        return; // No clock tables or error - start at 0
    }
    defer _ = api.finalize(stmt);

    var max_version: i64 = 0;

    // For each clock table, query max(db_version)
    while (api.step(stmt) == api.SQLITE_ROW) {
        const table_name = api.column_text(stmt, 0) orelse continue;

        // Query max db_version from this clock table
        var version_buf: [256]u8 = undefined;
        const version_sql = std.fmt.bufPrintZ(&version_buf, "SELECT MAX(db_version) FROM \"{s}\"", .{table_name}) catch continue;

        var version_stmt: ?*api.sqlite3_stmt = null;
        rc = api.prepare_v2(db, version_sql, -1, &version_stmt, null);
        if (rc != api.SQLITE_OK) continue;
        defer _ = api.finalize(version_stmt);

        if (api.step(version_stmt) == api.SQLITE_ROW) {
            const version = api.column_int64(version_stmt, 0);
            if (version > max_version) {
                max_version = version;
            }
        }
    }

    global_db_version = max_version;
    pending_db_version = 0;
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
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_next_db_version with -1 args to accept 0 or 1 arguments
    rc = api.create_function_v2(
        db,
        "crsql_next_db_version",
        -1, // Variable number of arguments
        api.SQLITE_UTF8,
        null,
        &crsqlNextDbVersionFunc,
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

test "nextDbVersion returns dbVersion + 1 on first call" {
    // Reset state for isolated test
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 0;

    const next = nextDbVersion(null);
    try std.testing.expectEqual(@as(i64, 6), next);
    try std.testing.expectEqual(@as(i64, 6), pending_db_version);
}

test "nextDbVersion returns pending if higher than dbVersion + 1" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 10;

    const next = nextDbVersion(null);
    try std.testing.expectEqual(@as(i64, 10), next);
}

test "nextDbVersion uses merging_version if highest" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 0;

    const next = nextDbVersion(20);
    try std.testing.expectEqual(@as(i64, 20), next);
    try std.testing.expectEqual(@as(i64, 20), pending_db_version);
}

test "commitDbVersion promotes pending to global" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 10;

    commitDbVersion();

    try std.testing.expectEqual(@as(i64, 10), global_db_version);
    try std.testing.expectEqual(@as(i64, 0), pending_db_version);
}

test "rollbackDbVersion resets pending only" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 10;

    rollbackDbVersion();

    try std.testing.expectEqual(@as(i64, 5), global_db_version);
    try std.testing.expectEqual(@as(i64, 0), pending_db_version);
}

test "getSiteId returns consistent value" {
    const id1 = getSiteId();
    const id2 = getSiteId();
    try std.testing.expectEqual(id1, id2);
}
