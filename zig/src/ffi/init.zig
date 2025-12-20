//! CR-SQLite extension initialization entrypoint.
//!
//! This module exports `sqlite3_crsqlite_init`, the entrypoint called by SQLite
//! when the extension is loaded via `.load` or `sqlite3_load_extension()`.
//!
//! Reference: `core/src/crsqlite.c` (C implementation)

const std = @import("std");
const api = @import("api.zig");
const as_crr = @import("../as_crr.zig");
const automigrate = @import("../automigrate.zig");
const changes_vtab = @import("../changes_vtab.zig");
const clset_vtab = @import("../clset_vtab.zig");
const config = @import("../config.zig");
const finalize = @import("../finalize.zig");
const unpack_columns_vtab = @import("../unpack_columns_vtab.zig");
const fract_index = @import("../fract_index.zig");
const is_crr = @import("../is_crr.zig");
const pack_columns = @import("../pack_columns.zig");
const rows_impacted = @import("../rows_impacted.zig");
const schema_alter = @import("../schema_alter.zig");
const site_identity = @import("../site_identity.zig");
const sync_bit = @import("../sync_bit.zig");

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

    // Register crsql_version() - standard version function (same implementation)
    rc = api.create_function_v2(
        db,
        "crsql_version", // function name
        0, // nArg: 0 arguments
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC, // text encoding + deterministic
        null, // pApp: no user data
        &crsqlZigVersionFunc, // xFunc: scalar function (reuse same impl)
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_as_crr() function
    rc = as_crr.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_is_crr() function
    rc = is_crr.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_changes virtual table
    rc = changes_vtab.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_finalize() - cleanup function
    rc = finalize.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_pack_columns() function
    rc = pack_columns.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_rows_impacted() function and commit hook
    rc = rows_impacted.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_site_id() and crsql_db_version() functions
    rc = site_identity.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_internal_sync_bit() function
    rc = sync_bit.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_begin_alter() and crsql_commit_alter() functions
    rc = schema_alter.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_fract_key_between() function
    rc = fract_index.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_automigrate() function
    rc = automigrate.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register clset virtual table module
    rc = clset_vtab.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_unpack_columns virtual table module
    rc = unpack_columns_vtab.register(db);
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_config_get() and crsql_config_set() functions
    rc = config.register(db);
    if (rc != api.SQLITE_OK) return rc;

    return api.SQLITE_OK;
}

/// Extension entrypoint called by SQLite when loading the extension.
///
/// This function:
/// 1. Stores the API pointer globally (equivalent to `SQLITE_EXTENSION_INIT2`)
/// 2. Initializes site_id (loads from db or creates new)
/// 3. Initializes db_version from existing clock tables
/// 4. Registers CR-SQLite functions and virtual tables
/// 5. Returns SQLITE_OK on success
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

    // Enable trusted_schema so our INNOCUOUS functions can be called from triggers.
    // Without this, SQLite 3.31.0+ rejects functions in triggers by default.
    // This is safe because our functions are marked SQLITE_INNOCUOUS.
    _ = api.exec(db, "PRAGMA trusted_schema = ON", null, null, null);

    // Create crsql_master table for storing metadata (version, pre_compact_dbversion, etc.)
    // Reference: core/rs/core/src/bootstrap.rs crsql_create_schema_table_if_not_exists
    const create_master_rc = api.exec(
        db,
        "CREATE TABLE IF NOT EXISTS \"crsql_master\" (\"key\" TEXT PRIMARY KEY, \"value\" ANY);",
        null,
        null,
        null,
    );
    if (create_master_rc != api.SQLITE_OK) {
        return create_master_rc;
    }

    // Initialize site_id (creates table if needed, loads or generates site_id)
    if (!site_identity.initSiteId(db)) {
        return api.SQLITE_ERROR;
    }

    // Initialize db_version from existing clock tables
    site_identity.initDbVersionFromDb(db);

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
