//! CR-SQLite extension initialization entrypoint.
//!
//! This module exports `sqlite3_crsqlite_init`, the entrypoint called by SQLite
//! when the extension is loaded via `.load` or `sqlite3_load_extension()`.
//!
//! Reference: `core/src/crsqlite.c` (C implementation)

const std = @import("std");
const api = @import("api.zig");
const as_crr = @import("../as_crr.zig");
const changes_vtab = @import("../changes_vtab.zig");
const pack_columns = @import("../pack_columns.zig");
const rows_impacted = @import("../rows_impacted.zig");

/// CR-SQLite Zig implementation version string.
/// This is returned by the `crsql_zig_version()` SQL function.
pub const CRSQL_ZIG_VERSION = "0.0.1-zig-scaffold";

/// Implementation of the `crsql_zig_version()` SQL function.
/// Returns the version string to prove the extension loaded correctly.
fn crsqlZigVersionFunc(
    pCtx: ?*api.sqlite3_context,
    _: c_int, // argc - unused, this function takes no arguments
    _: [*c]?*api.sqlite3_value, // argv - unused
) callconv(.c) void {
    // Return version string with SQLITE_STATIC since it's a constant
    api.result_text(pCtx, CRSQL_ZIG_VERSION, -1, api.SQLITE_STATIC);
}

/// Implementation of `crsql_finalize()` SQL function.
/// Cleanup function called before closing a database connection.
/// For now this is a stub that returns OK - real cleanup will be added
/// when we have per-connection state (ExtData) to clean up.
fn crsqlFinalizeFunc(
    pCtx: ?*api.sqlite3_context,
    _: c_int,
    _: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Stub: return OK (null result means success for this function)
    api.result_null(pCtx);
}

/// Register all CR-SQLite functions with the database connection.
fn registerFunctions(db: ?*api.sqlite3) c_int {
    // Register crsql_zig_version() - a 0-argument scalar function
    var rc = api.create_function_v2(
        db,
        "crsql_zig_version", // function name
        0, // nArg: 0 arguments
        api.SQLITE_UTF8, // text encoding
        null, // pApp: no user data
        &crsqlZigVersionFunc, // xFunc: scalar function
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_as_crr() function
    rc = as_crr.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_changes virtual table
    rc = changes_vtab.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_finalize() - cleanup function
    rc = api.create_function_v2(
        db,
        "crsql_finalize",
        0,
        api.SQLITE_UTF8,
        null,
        &crsqlFinalizeFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_pack_columns() function
    rc = pack_columns.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_rows_impacted() function and commit hook
    rc = rows_impacted.register(db);
    if (rc != api.SQLITE_OK) return rc;

    return api.SQLITE_OK;
}

/// Extension entrypoint called by SQLite when loading the extension.
///
/// This function:
/// 1. Stores the API pointer globally (equivalent to `SQLITE_EXTENSION_INIT2`)
/// 2. Registers CR-SQLite functions and virtual tables
/// 3. Returns SQLITE_OK on success
///
/// Signature matches SQLite's expected extension init function:
/// ```c
/// int sqlite3_crsqlite_init(
///     sqlite3 *db,
///     char **pzErrMsg,
///     const sqlite3_api_routines *pApi
/// );
/// ```
pub export fn sqlite3_crsqlite_init(
    db: ?*api.sqlite3,
    pzErrMsg: ?*[*:0]u8,
    pApi: ?*api.sqlite3_api_routines,
) callconv(.c) c_int {
    _ = pzErrMsg; // TODO: use for detailed error messages

    // Initialize the global API pointer (SQLITE_EXTENSION_INIT2 equivalent)
    const init_rc = api.initApi(pApi);
    if (init_rc != api.SQLITE_OK) {
        return init_rc;
    }

    // Register functions
    const func_rc = registerFunctions(db);
    if (func_rc != api.SQLITE_OK) {
        return func_rc;
    }

    return api.SQLITE_OK;
}

// Also export with the standard naming convention SQLite looks for
comptime {
    // SQLite tries several names when loading an extension.
    // The primary name is derived from the filename, but we also export
    // a generic entry point that SQLite can find.
    @export(&sqlite3_crsqlite_init, .{ .name = "sqlite3_extension_init" });
}

test "sqlite3_crsqlite_init returns error without api" {
    // Calling init with null API should fail
    const rc = sqlite3_crsqlite_init(null, null, null);
    try std.testing.expectEqual(api.SQLITE_ERROR, rc);
}
