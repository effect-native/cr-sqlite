//! SQLite API pointer storage for loadable extensions.
//!
//! This module provides the global `sqlite3_api` pointer that loadable extensions
//! must store on initialization. All SQLite API calls in a loadable extension go
//! through this pointer table (equivalent to C's `SQLITE_EXTENSION_INIT2(pApi)`).
//!
//! Reference: `.refs/zig-sqlite/c/loadable_extension.zig`

const std = @import("std");

// Opaque pointer types for SQLite structures.
// These are intentionally opaque - the actual struct layouts are internal to SQLite.
pub const sqlite3 = opaque {};
pub const sqlite3_context = opaque {};
pub const sqlite3_value = opaque {};
pub const sqlite3_stmt = opaque {};

/// SQLite API routines table passed to loadable extensions.
/// This is an opaque type since we access it through function pointers.
pub const sqlite3_api_routines = opaque {};

/// Global API pointer - initialized by `initApi()` during extension load.
/// All SQLite API calls in the extension go through this pointer.
///
/// This is the Zig equivalent of C's:
/// ```c
/// static sqlite3_api_routines *sqlite3_api = 0;
/// SQLITE_EXTENSION_INIT2(pApi);  // sets sqlite3_api = pApi
/// ```
pub var sqlite3_api: ?*sqlite3_api_routines = null;

/// SQLite result codes
pub const SQLITE_OK = 0;
pub const SQLITE_ERROR = 1;
pub const SQLITE_MISUSE = 21;

/// Text encoding flags for create_function
pub const SQLITE_UTF8 = 1;

/// Special destructor value meaning SQLite should not free the result
pub const SQLITE_STATIC: ?*const fn (?*anyopaque) callconv(.c) void = null;
pub const SQLITE_TRANSIENT: ?*const fn (?*anyopaque) callconv(.c) void = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

/// Initialize the global API pointer. Called once during extension initialization.
///
/// Equivalent to C's `SQLITE_EXTENSION_INIT2(pApi)` macro.
///
/// Returns `SQLITE_OK` on success, `SQLITE_ERROR` if `pApi` is null.
pub fn initApi(pApi: ?*sqlite3_api_routines) c_int {
    if (pApi) |api| {
        sqlite3_api = api;
        return SQLITE_OK;
    }
    return SQLITE_ERROR;
}

/// Check if the API has been initialized.
pub fn isInitialized() bool {
    return sqlite3_api != null;
}

// -----------------------------------------------------------------------------
// SQLite API function wrappers
//
// These access the function pointers in sqlite3_api_routines.
// The routines struct is a large table of optional function pointers.
// We cast it to access specific offsets matching SQLite's ABI.
// -----------------------------------------------------------------------------

/// Function pointer type for scalar UDFs
pub const ScalarFn = *const fn (?*sqlite3_context, c_int, [*c]?*sqlite3_value) callconv(.c) void;

/// Wrapper for sqlite3_create_function_v2
/// Registers a scalar, aggregate, or window function.
pub fn create_function_v2(
    db: ?*sqlite3,
    zFunctionName: [*:0]const u8,
    nArg: c_int,
    eTextRep: c_int,
    pApp: ?*anyopaque,
    xFunc: ?ScalarFn,
    xStep: ?*const fn (?*sqlite3_context, c_int, [*c]?*sqlite3_value) callconv(.c) void,
    xFinal: ?*const fn (?*sqlite3_context) callconv(.c) void,
    xDestroy: ?*const fn (?*anyopaque) callconv(.c) void,
) c_int {
    const api_ptr = sqlite3_api orelse return SQLITE_MISUSE;
    // create_function_v2 is at offset 157 in the routines table (SQLite 3.7+)
    const ApiTable = extern struct {
        padding: [157]?*anyopaque,
        create_function_v2: ?*const fn (
            ?*sqlite3,
            [*:0]const u8,
            c_int,
            c_int,
            ?*anyopaque,
            ?ScalarFn,
            ?*const fn (?*sqlite3_context, c_int, [*c]?*sqlite3_value) callconv(.c) void,
            ?*const fn (?*sqlite3_context) callconv(.c) void,
            ?*const fn (?*anyopaque) callconv(.c) void,
        ) callconv(.c) c_int,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.create_function_v2 orelse return SQLITE_MISUSE;
    return func(db, zFunctionName, nArg, eTextRep, pApp, xFunc, xStep, xFinal, xDestroy);
}

/// Wrapper for sqlite3_result_text
/// Sets the result of a function to a text string.
pub fn result_text(
    pCtx: ?*sqlite3_context,
    z: [*:0]const u8,
    n: c_int,
    xDel: ?*const fn (?*anyopaque) callconv(.c) void,
) void {
    const api_ptr = sqlite3_api orelse return;
    // result_text is at offset 66 in the routines table
    const ApiTable = extern struct {
        padding: [66]?*anyopaque,
        result_text_fn: ?*const fn (
            ?*sqlite3_context,
            [*:0]const u8,
            c_int,
            ?*const fn (?*anyopaque) callconv(.c) void,
        ) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_text_fn orelse return;
    func(pCtx, z, n, xDel);
}

test "initApi stores pointer" {
    // Reset for test isolation
    sqlite3_api = null;

    // Null should fail
    const result_null = initApi(null);
    try std.testing.expectEqual(SQLITE_ERROR, result_null);
    try std.testing.expect(!isInitialized());

    // Non-null should succeed (using a dummy pointer for testing)
    var dummy: u8 = 0;
    const dummy_api: *sqlite3_api_routines = @ptrCast(&dummy);
    const result_ok = initApi(dummy_api);
    try std.testing.expectEqual(SQLITE_OK, result_ok);
    try std.testing.expect(isInitialized());

    // Cleanup
    sqlite3_api = null;
}
