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

/// Destructor function type for sqlite3_result_* functions.
/// Using align(1) to allow the special sentinel value SQLITE_TRANSIENT (-1).
pub const DestructorFn = ?*align(1) const fn (?*anyopaque) callconv(.c) void;

/// Special destructor value meaning SQLite should not free the result.
/// SQLITE_STATIC is null - tells SQLite the data is static/const.
pub const SQLITE_STATIC: DestructorFn = null;

/// SQLITE_TRANSIENT tells SQLite to make a copy of the data.
/// In SQLite's C API, SQLITE_TRANSIENT is ((void(*)(void*))-1).
/// We use align(1) on DestructorFn to allow this misaligned sentinel.
pub const SQLITE_TRANSIENT: DestructorFn = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

/// Get SQLITE_TRANSIENT - provided for API consistency with older code
pub inline fn getTransientDestructor() DestructorFn {
    return SQLITE_TRANSIENT;
}

/// SQLite value type codes (returned by sqlite3_value_type)
pub const SQLITE_INTEGER = 1;
pub const SQLITE_FLOAT = 2;
pub const SQLITE_TEXT = 3;
pub const SQLITE_BLOB = 4;
pub const SQLITE_NULL = 5;

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
    // create_function_v2 is at offset 173 in the routines table (SQLite 3.50.x)
    const ApiTable = extern struct {
        padding: [173]?*anyopaque,
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
    xDel: DestructorFn,
) void {
    const api_ptr = sqlite3_api orelse return;
    // result_text is at offset 93 in the routines table
    const ApiTable = extern struct {
        padding: [93]?*anyopaque,
        result_text_fn: ?*const fn (
            ?*sqlite3_context,
            [*:0]const u8,
            c_int,
            DestructorFn,
        ) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_text_fn orelse return;
    func(pCtx, z, n, xDel);
}

// -----------------------------------------------------------------------------
// Virtual Table Registration
// -----------------------------------------------------------------------------

/// Virtual table module structure (opaque - actual layout defined by SQLite)
pub const sqlite3_module = opaque {};

/// Wrapper for sqlite3_create_module_v2
/// Registers a virtual table implementation.
pub fn create_module_v2(
    db: ?*sqlite3,
    zName: [*:0]const u8,
    pModule: ?*const sqlite3_module,
    pClientData: ?*anyopaque,
    xDestroy: ?*const fn (?*anyopaque) callconv(.c) void,
) c_int {
    const api_ptr = sqlite3_api orelse return SQLITE_MISUSE;
    // create_module_v2 is at offset 127 in the routines table
    const ApiTable = extern struct {
        padding: [127]?*anyopaque,
        create_module_v2_fn: ?*const fn (
            ?*sqlite3,
            [*:0]const u8,
            ?*const sqlite3_module,
            ?*anyopaque,
            ?*const fn (?*anyopaque) callconv(.c) void,
        ) callconv(.c) c_int,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.create_module_v2_fn orelse return SQLITE_MISUSE;
    return func(db, zName, pModule, pClientData, xDestroy);
}

/// Wrapper for sqlite3_declare_vtab
/// Declares the schema for a virtual table during xCreate/xConnect.
pub fn declare_vtab(db: ?*sqlite3, zSQL: [*:0]const u8) c_int {
    const api_ptr = sqlite3_api orelse return SQLITE_MISUSE;
    // declare_vtab is at offset 58 in the routines table
    const ApiTable = extern struct {
        padding: [58]?*anyopaque,
        declare_vtab_fn: ?*const fn (?*sqlite3, [*:0]const u8) callconv(.c) c_int,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.declare_vtab_fn orelse return SQLITE_MISUSE;
    return func(db, zSQL);
}

// -----------------------------------------------------------------------------
// Hooks
// -----------------------------------------------------------------------------

/// Callback type for commit hook
pub const CommitHookFn = *const fn (?*anyopaque) callconv(.c) c_int;

/// Callback type for rollback hook
pub const RollbackHookFn = *const fn (?*anyopaque) callconv(.c) void;

/// Wrapper for sqlite3_commit_hook
/// Registers a callback invoked when a transaction is committed.
/// Returns the previous callback (or null).
pub fn commit_hook(
    db: ?*sqlite3,
    callback: ?CommitHookFn,
    pArg: ?*anyopaque,
) ?CommitHookFn {
    const api_ptr = sqlite3_api orelse return null;
    // commit_hook is at offset 40 in the routines table
    const ApiTable = extern struct {
        padding: [40]?*anyopaque,
        commit_hook_fn: ?*const fn (?*sqlite3, ?CommitHookFn, ?*anyopaque) callconv(.c) ?CommitHookFn,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.commit_hook_fn orelse return null;
    return func(db, callback, pArg);
}

/// Wrapper for sqlite3_rollback_hook
/// Registers a callback invoked when a transaction is rolled back.
/// Returns the previous callback (or null).
pub fn rollback_hook(
    db: ?*sqlite3,
    callback: ?RollbackHookFn,
    pArg: ?*anyopaque,
) ?RollbackHookFn {
    const api_ptr = sqlite3_api orelse return null;
    // rollback_hook is at offset 98 in the routines table
    const ApiTable = extern struct {
        padding: [98]?*anyopaque,
        rollback_hook_fn: ?*const fn (?*sqlite3, ?RollbackHookFn, ?*anyopaque) callconv(.c) ?RollbackHookFn,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.rollback_hook_fn orelse return null;
    return func(db, callback, pArg);
}

// -----------------------------------------------------------------------------
// Memory Management
// -----------------------------------------------------------------------------

/// Wrapper for sqlite3_malloc
/// Allocates memory using SQLite's allocator.
pub fn malloc(n: c_int) ?*anyopaque {
    const api_ptr = sqlite3_api orelse return null;
    // malloc is at offset 76 in the routines table
    const ApiTable = extern struct {
        padding: [76]?*anyopaque,
        malloc_fn: ?*const fn (c_int) callconv(.c) ?*anyopaque,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.malloc_fn orelse return null;
    return func(n);
}

/// Wrapper for sqlite3_free
/// Frees memory allocated by sqlite3_malloc.
pub fn free(p: ?*anyopaque) void {
    const api_ptr = sqlite3_api orelse return;
    // free is at offset 66 in the routines table
    const ApiTable = extern struct {
        padding: [66]?*anyopaque,
        free_fn: ?*const fn (?*anyopaque) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.free_fn orelse return;
    func(p);
}

// -----------------------------------------------------------------------------
// Additional Result APIs (for vtab column output)
// -----------------------------------------------------------------------------

/// Wrapper for sqlite3_result_int64
/// Sets the result of a function to a 64-bit integer.
pub fn result_int64(pCtx: ?*sqlite3_context, val: i64) void {
    const api_ptr = sqlite3_api orelse return;
    // result_int64 is at offset 91 in the routines table
    const ApiTable = extern struct {
        padding: [91]?*anyopaque,
        result_int64_fn: ?*const fn (?*sqlite3_context, i64) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_int64_fn orelse return;
    func(pCtx, val);
}

/// Wrapper for sqlite3_result_double
/// Sets the result of a function to a floating-point number.
pub fn result_double(pCtx: ?*sqlite3_context, val: f64) void {
    const api_ptr = sqlite3_api orelse return;
    // result_double is at offset 87 in the routines table
    const ApiTable = extern struct {
        padding: [87]?*anyopaque,
        result_double_fn: ?*const fn (?*sqlite3_context, f64) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_double_fn orelse return;
    func(pCtx, val);
}

/// Wrapper for sqlite3_result_blob
/// Sets the result of a function to a blob.
pub fn result_blob(
    pCtx: ?*sqlite3_context,
    ptr: ?*const anyopaque,
    n: c_int,
    xDel: DestructorFn,
) void {
    const api_ptr = sqlite3_api orelse return;
    // result_blob is at offset 86 in the routines table
    const ApiTable = extern struct {
        padding: [86]?*anyopaque,
        result_blob_fn: ?*const fn (
            ?*sqlite3_context,
            ?*const anyopaque,
            c_int,
            DestructorFn,
        ) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_blob_fn orelse return;
    func(pCtx, ptr, n, xDel);
}

/// Wrapper for sqlite3_result_null
/// Sets the result of a function to NULL.
pub fn result_null(pCtx: ?*sqlite3_context) void {
    const api_ptr = sqlite3_api orelse return;
    // result_null is at offset 92 in the routines table
    const ApiTable = extern struct {
        padding: [92]?*anyopaque,
        result_null_fn: ?*const fn (?*sqlite3_context) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_null_fn orelse return;
    func(pCtx);
}

/// Wrapper for sqlite3_result_error
/// Sets the result of a function to an error.
pub fn result_error(pCtx: ?*sqlite3_context, zMsg: [*:0]const u8, n: c_int) void {
    const api_ptr = sqlite3_api orelse return;
    // result_error is at offset 88 in the routines table
    const ApiTable = extern struct {
        padding: [88]?*anyopaque,
        result_error_fn: ?*const fn (?*sqlite3_context, [*:0]const u8, c_int) callconv(.c) void,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.result_error_fn orelse return;
    func(pCtx, zMsg, n);
}

// -----------------------------------------------------------------------------
// Value Extraction APIs (for vtab xUpdate args)
// -----------------------------------------------------------------------------

/// Wrapper for sqlite3_value_type
/// Returns the datatype code for the value.
pub fn value_type(pVal: ?*sqlite3_value) c_int {
    const api_ptr = sqlite3_api orelse return SQLITE_NULL;
    // value_type is at offset 121 in the routines table
    const ApiTable = extern struct {
        padding: [121]?*anyopaque,
        value_type_fn: ?*const fn (?*sqlite3_value) callconv(.c) c_int,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.value_type_fn orelse return SQLITE_NULL;
    return func(pVal);
}

/// Wrapper for sqlite3_value_int64
/// Returns the value as a 64-bit integer.
pub fn value_int64(pVal: ?*sqlite3_value) i64 {
    const api_ptr = sqlite3_api orelse return 0;
    // value_int64 is at offset 115 in the routines table
    const ApiTable = extern struct {
        padding: [115]?*anyopaque,
        value_int64_fn: ?*const fn (?*sqlite3_value) callconv(.c) i64,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.value_int64_fn orelse return 0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_double
/// Returns the value as a floating-point number.
pub fn value_double(pVal: ?*sqlite3_value) f64 {
    const api_ptr = sqlite3_api orelse return 0.0;
    // value_double is at offset 113 in the routines table
    const ApiTable = extern struct {
        padding: [113]?*anyopaque,
        value_double_fn: ?*const fn (?*sqlite3_value) callconv(.c) f64,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.value_double_fn orelse return 0.0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_blob
/// Returns the value as a pointer to blob data.
pub fn value_blob(pVal: ?*sqlite3_value) ?*const anyopaque {
    const api_ptr = sqlite3_api orelse return null;
    // value_blob is at offset 110 in the routines table
    const ApiTable = extern struct {
        padding: [110]?*anyopaque,
        value_blob_fn: ?*const fn (?*sqlite3_value) callconv(.c) ?*const anyopaque,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.value_blob_fn orelse return null;
    return func(pVal);
}

/// Wrapper for sqlite3_value_bytes
/// Returns the number of bytes in a blob or text value.
pub fn value_bytes(pVal: ?*sqlite3_value) c_int {
    const api_ptr = sqlite3_api orelse return 0;
    // value_bytes is at offset 111 in the routines table
    const ApiTable = extern struct {
        padding: [111]?*anyopaque,
        value_bytes_fn: ?*const fn (?*sqlite3_value) callconv(.c) c_int,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.value_bytes_fn orelse return 0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_text
/// Returns the value as a null-terminated UTF-8 string.
pub fn value_text(pVal: ?*sqlite3_value) ?[*:0]const u8 {
    const api_ptr = sqlite3_api orelse return null;
    // value_text is at offset 117 in the routines table
    const ApiTable = extern struct {
        padding: [117]?*anyopaque,
        value_text_fn: ?*const fn (?*sqlite3_value) callconv(.c) ?[*:0]const u8,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.value_text_fn orelse return null;
    return func(pVal);
}

// -----------------------------------------------------------------------------
// Context and Execution APIs
// -----------------------------------------------------------------------------

/// Wrapper for sqlite3_context_db_handle
/// Returns the database handle associated with a function context.
pub fn context_db_handle(pCtx: ?*sqlite3_context) ?*sqlite3 {
    const api_ptr = sqlite3_api orelse return null;
    // context_db_handle is at offset 160 in the routines table
    const ApiTable = extern struct {
        padding: [160]?*anyopaque,
        context_db_handle_fn: ?*const fn (?*sqlite3_context) callconv(.c) ?*sqlite3,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.context_db_handle_fn orelse return null;
    return func(pCtx);
}

/// Callback type for sqlite3_exec
pub const ExecCallback = *const fn (?*anyopaque, c_int, [*c]?[*:0]u8, [*c]?[*:0]u8) callconv(.c) c_int;

/// Wrapper for sqlite3_exec
/// Executes one or more SQL statements.
pub fn exec(
    db: ?*sqlite3,
    sql: [*:0]const u8,
    callback: ?ExecCallback,
    arg: ?*anyopaque,
    errmsg: ?*?[*:0]u8,
) c_int {
    const api_ptr = sqlite3_api orelse return SQLITE_MISUSE;
    // exec is at offset 63 in the routines table
    const ApiTable = extern struct {
        padding: [63]?*anyopaque,
        exec_fn: ?*const fn (
            ?*sqlite3,
            [*:0]const u8,
            ?ExecCallback,
            ?*anyopaque,
            ?*?[*:0]u8,
        ) callconv(.c) c_int,
    };
    const tbl: *const ApiTable = @ptrCast(@alignCast(api_ptr));
    const func = tbl.exec_fn orelse return SQLITE_MISUSE;
    return func(db, sql, callback, arg, errmsg);
}

test "initApi stores pointer" {
    // Reset for test isolation
    sqlite3_api = null;

    // Null should fail
    const result_null_code = initApi(null);
    try std.testing.expectEqual(SQLITE_ERROR, result_null_code);
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

test "wrappers return safe defaults when sqlite3_api is null" {
    // Ensure API is not initialized
    sqlite3_api = null;

    // Virtual table registration should return SQLITE_MISUSE
    try std.testing.expectEqual(SQLITE_MISUSE, create_module_v2(null, "test", null, null, null));
    try std.testing.expectEqual(SQLITE_MISUSE, declare_vtab(null, "CREATE TABLE x(a)"));

    // Hooks should return null
    try std.testing.expectEqual(@as(?CommitHookFn, null), commit_hook(null, null, null));
    try std.testing.expectEqual(@as(?RollbackHookFn, null), rollback_hook(null, null, null));

    // Memory functions should return null/noop
    try std.testing.expectEqual(@as(?*anyopaque, null), malloc(100));
    free(null); // Should not crash

    // Result functions should not crash (void return)
    result_int64(null, 42);
    result_double(null, 3.14);
    result_blob(null, null, 0, null);
    result_null(null);
    result_error(null, "error", -1);

    // Value extraction should return safe defaults
    try std.testing.expectEqual(SQLITE_NULL, value_type(null));
    try std.testing.expectEqual(@as(i64, 0), value_int64(null));
    try std.testing.expectEqual(@as(f64, 0.0), value_double(null));
    try std.testing.expectEqual(@as(?*const anyopaque, null), value_blob(null));
    try std.testing.expectEqual(@as(c_int, 0), value_bytes(null));
    try std.testing.expectEqual(@as(?[*:0]const u8, null), value_text(null));
}
