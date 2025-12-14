//! crsql_finalize() - Extension cleanup UDF
//!
//! Must be called before sqlite3_close() to properly clean up extension state.
//! This matches the C/Rust implementation's crsql_finalize() behavior.

const std = @import("std");
const api = @import("ffi/api.zig");

/// Implementation of crsql_finalize() SQL function
fn crsqlFinalizeFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    _ = argv;
    if (argc != 0) {
        api.result_error(pCtx, "crsql_finalize takes no arguments", -1);
        return;
    }

    // MVP: No cleanup needed yet
    // In production: finalize cached statements, cleanup ExtData, etc.

    api.result_null(pCtx);
}

/// Register the crsql_finalize function with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_function_v2(
        db,
        "crsql_finalize",
        0, // nArg
        api.SQLITE_UTF8,
        null,
        &crsqlFinalizeFunc,
        null,
        null,
        null,
    );
}
