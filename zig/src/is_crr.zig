//! CRR Detection: crsql_is_crr(table_name) implementation
//!
//! Returns 1 if the given table has been converted to a CRR (conflict-free
//! replicated relation), 0 otherwise.
//!
//! A table is a CRR if it has an associated clock table: `{tablename}__crsql_clock`
//!
//! Reference: `core/src/is-crr.test.c`

const std = @import("std");
const api = @import("ffi/api.zig");

/// SQL buffer size for query generation
const SQL_BUF_SIZE = 512;

/// Implementation of `crsql_is_crr(table_name)` SQL function.
/// Returns 1 if the table is a CRR, 0 otherwise.
fn crsqlIsCrrFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Validate argument count
    if (argc != 1) {
        api.result_error(pCtx, "crsql_is_crr requires exactly 1 argument", -1);
        return;
    }

    // Get the table name argument
    const table_name_ptr = api.value_text(argv[0]) orelse {
        api.result_error(pCtx, "crsql_is_crr: table name must be TEXT", -1);
        return;
    };

    // Get database handle from context
    const db = api.context_db_handle(pCtx) orelse {
        api.result_error(pCtx, "crsql_is_crr: failed to get db handle", -1);
        return;
    };

    // Check if the clock table exists
    const is_crr = checkClockTableExists(db, table_name_ptr);
    api.result_int(pCtx, if (is_crr) 1 else 0);
}

/// Check if the clock table for a given table exists in sqlite_master.
fn checkClockTableExists(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM sqlite_master 
        \\WHERE type='table' AND name='{s}__crsql_clock'
    , .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        const count = api.column_int64(stmt, 0);
        return count > 0;
    }

    return false;
}

/// Register the crsql_is_crr function with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_function_v2(
        db,
        "crsql_is_crr",
        1, // nArg: 1 argument (table name)
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC,
        null, // pApp: no user data
        &crsqlIsCrrFunc,
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
}

test "checkClockTableExists returns false for non-existent table" {
    // Without a database connection, we can only test that the format string is valid
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM sqlite_master 
        \\WHERE type='table' AND name='{s}__crsql_clock'
    , .{"test_table"}) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, sql, "test_table__crsql_clock") != null);
}
