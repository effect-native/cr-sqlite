//! SQLite API wrappers for loadable extensions.
//!
//! This module provides Zig wrappers around the SQLite C API for use in
//! loadable extensions. It uses @cImport via sqlite_c.zig to ensure proper
//! struct layout compatibility with the actual SQLite library.
//!
//! Reference: `.refs/zig-sqlite/c/loadable_extension.zig`

const std = @import("std");
const sqlite_c = @import("sqlite_c.zig");

pub const c = sqlite_c.c;

/// Get the global API pointer (for direct access by other modules)
/// Returns null if not initialized, otherwise the pointer to the API routines.
pub fn getApi() ?*c.sqlite3_api_routines {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    return api;
}

// Re-export common types from sqlite_c
pub const sqlite3 = sqlite_c.sqlite3;
pub const sqlite3_context = sqlite_c.sqlite3_context;
pub const sqlite3_value = sqlite_c.sqlite3_value;
pub const sqlite3_stmt = sqlite_c.sqlite3_stmt;
pub const sqlite3_module = sqlite_c.sqlite3_module;
pub const sqlite3_vtab = sqlite_c.sqlite3_vtab;
pub const sqlite3_vtab_cursor = sqlite_c.sqlite3_vtab_cursor;
pub const sqlite3_index_info = sqlite_c.sqlite3_index_info;
pub const sqlite3_int64 = sqlite_c.sqlite3_int64;
pub const sqlite3_uint64 = sqlite_c.sqlite3_uint64;
pub const sqlite3_api_routines = sqlite_c.sqlite3_api_routines;

/// SQLite result codes
pub const SQLITE_OK = c.SQLITE_OK;
pub const SQLITE_ERROR = c.SQLITE_ERROR;
pub const SQLITE_MISUSE = c.SQLITE_MISUSE;
pub const SQLITE_NOMEM = c.SQLITE_NOMEM;
pub const SQLITE_BUSY = c.SQLITE_BUSY;
pub const SQLITE_CONSTRAINT = c.SQLITE_CONSTRAINT;
pub const SQLITE_ABORT = c.SQLITE_ABORT;
pub const SQLITE_DONE = c.SQLITE_DONE;
pub const SQLITE_ROW = c.SQLITE_ROW;

/// Text encoding flags for create_function
pub const SQLITE_UTF8 = c.SQLITE_UTF8;
pub const SQLITE_DETERMINISTIC = c.SQLITE_DETERMINISTIC;
pub const SQLITE_INNOCUOUS = c.SQLITE_INNOCUOUS;
pub const SQLITE_DIRECTONLY = c.SQLITE_DIRECTONLY;

/// SQLite value type codes (returned by sqlite3_value_type)
pub const SQLITE_INTEGER = c.SQLITE_INTEGER;
pub const SQLITE_FLOAT = c.SQLITE_FLOAT;
pub const SQLITE_TEXT = c.SQLITE_TEXT;
pub const SQLITE_BLOB = c.SQLITE_BLOB;
pub const SQLITE_NULL = c.SQLITE_NULL;

/// Destructor type compatible with SQLite's C API.
pub const DestructorFn = ?*const fn (?*anyopaque) callconv(.c) void;

/// SQLITE_STATIC - tells SQLite the data is static/const and won't be freed
pub const SQLITE_STATIC: DestructorFn = null;

/// SQLITE_TRANSIENT as a constant - tells SQLite to make a copy of the data.
/// This is the value ((void(*)(void *))-1) from SQLite's headers.
/// We use @ptrFromInt to create this special sentinel value.
pub const SQLITE_TRANSIENT: DestructorFn = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

/// Platform-specific implementation for getting SQLITE_TRANSIENT.
/// On native platforms with C interop, we use the C workaround function.
/// On WASM/freestanding, we use the pure Zig constant.
const builtin = @import("builtin");

/// Get SQLITE_TRANSIENT for passing to SQLite result functions.
/// Tells SQLite to make a copy of the data because it may be deallocated.
pub inline fn getTransientDestructor() DestructorFn {
    if (comptime (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64 or builtin.os.tag == .freestanding)) {
        // Pure Zig implementation for WASM/freestanding
        return SQLITE_TRANSIENT;
    } else {
        // Use C workaround on native platforms for maximum compatibility
        return sqliteTransientAsDestructor();
    }
}

// Import the C workaround function that returns SQLITE_TRANSIENT (-1)
// Only available on native platforms where we link workaround.c
extern fn sqliteTransientAsDestructor() DestructorFn;

/// Initialize the global API pointer. Called once during extension initialization.
/// Equivalent to C's `SQLITE_EXTENSION_INIT2(pApi)` macro.
pub fn initApi(pApi: ?*c.sqlite3_api_routines) c_int {
    if (pApi) |p| {
        sqlite_c.sqlite3_api = p;
        return SQLITE_OK;
    }
    return SQLITE_ERROR;
}

/// Check if the API has been initialized.
pub fn isInitialized() bool {
    return sqlite_c.sqlite3_api != null;
}

// =============================================================================
// Function Registration
// =============================================================================

/// Function pointer type for scalar UDFs
pub const ScalarFn = *const fn (?*c.sqlite3_context, c_int, [*c]?*c.sqlite3_value) callconv(.c) void;

/// Function pointer type for aggregate step function
pub const StepFn = *const fn (?*c.sqlite3_context, c_int, [*c]?*c.sqlite3_value) callconv(.c) void;

/// Function pointer type for aggregate final function
pub const FinalFn = *const fn (?*c.sqlite3_context) callconv(.c) void;

/// Function pointer type for destructor
pub const DestroyFn = *const fn (?*anyopaque) callconv(.c) void;

/// Wrapper for sqlite3_create_function_v2
/// Registers a scalar, aggregate, or window function.
pub fn create_function_v2(
    db: ?*c.sqlite3,
    zFunctionName: [*:0]const u8,
    nArg: c_int,
    eTextRep: c_int,
    pApp: ?*anyopaque,
    xFunc: ?ScalarFn,
    xStep: ?StepFn,
    xFinal: ?FinalFn,
    xDestroy: ?DestroyFn,
) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.create_function_v2 orelse return SQLITE_MISUSE;
    return func(db, zFunctionName, nArg, eTextRep, pApp, xFunc, xStep, xFinal, xDestroy);
}

// =============================================================================
// Virtual Table Registration
// =============================================================================

/// Wrapper for sqlite3_create_module_v2
/// Registers a virtual table implementation.
pub fn create_module_v2(
    db: ?*c.sqlite3,
    zName: [*:0]const u8,
    pModule: ?*const c.sqlite3_module,
    pClientData: ?*anyopaque,
    xDestroy: ?DestroyFn,
) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.create_module_v2 orelse return SQLITE_MISUSE;
    return func(db, zName, pModule, pClientData, xDestroy);
}

/// Wrapper for sqlite3_declare_vtab
/// Declares the schema for a virtual table during xCreate/xConnect.
pub fn declare_vtab(db: ?*c.sqlite3, zSQL: [*:0]const u8) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.declare_vtab orelse return SQLITE_MISUSE;
    return func(db, zSQL);
}

// =============================================================================
// Result Functions (for UDF output)
// =============================================================================

/// Wrapper for sqlite3_result_text
/// Sets the result of a function to a text string.
pub fn result_text(
    pCtx: ?*c.sqlite3_context,
    z: [*c]const u8,
    n: c_int,
    xDel: DestructorFn,
) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_text orelse return;
    func(pCtx, z, n, xDel);
}

/// Wrapper for sqlite3_result_int64
/// Sets the result of a function to a 64-bit integer.
/// Falls back to result_int if result_int64 is not available (e.g., WASM builds).
pub fn result_int64(pCtx: ?*c.sqlite3_context, val: c.sqlite3_int64) void {
    const api_ptr = sqlite_c.sqlite3_api;
    if (api_ptr == null) {
        // No API - cannot set result
        return;
    }
    // Dereference once and use local reference
    const api = api_ptr.*;
    if (api.result_int64) |func| {
        func(pCtx, val);
    } else if (api.result_int) |func_int| {
        // Fallback to result_int for WASM builds where result_int64 may not be available
        // This works for values that fit in 32 bits (db_version typically does)
        func_int(pCtx, @intCast(val));
    } else if (api.result_error) |func_err| {
        // Last resort - report error if we can't set a result
        func_err(pCtx, "result_int64 not available", -1);
    }
}

/// Wrapper for sqlite3_result_int
/// Sets the result of a function to a 32-bit integer.
pub fn result_int(pCtx: ?*c.sqlite3_context, val: c_int) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_int orelse return;
    func(pCtx, val);
}

/// Wrapper for sqlite3_result_double
/// Sets the result of a function to a floating-point number.
pub fn result_double(pCtx: ?*c.sqlite3_context, val: f64) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_double orelse return;
    func(pCtx, val);
}

/// Wrapper for sqlite3_result_blob
/// Sets the result of a function to a blob.
pub fn result_blob(
    pCtx: ?*c.sqlite3_context,
    ptr: ?*const anyopaque,
    n: c_int,
    xDel: DestructorFn,
) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_blob orelse return;
    func(pCtx, ptr, n, xDel);
}

/// Wrapper for sqlite3_result_null
/// Sets the result of a function to NULL.
pub fn result_null(pCtx: ?*c.sqlite3_context) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_null orelse return;
    func(pCtx);
}

/// Wrapper for sqlite3_result_error
/// Sets the result of a function to an error.
pub fn result_error(pCtx: ?*c.sqlite3_context, zMsg: [*c]const u8, n: c_int) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_error orelse return;
    func(pCtx, zMsg, n);
}

/// Wrapper for sqlite3_result_error_nomem
/// Sets the result to an out-of-memory error.
pub fn result_error_nomem(pCtx: ?*c.sqlite3_context) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.result_error_nomem orelse return;
    func(pCtx);
}

// =============================================================================
// Value Extraction Functions (for UDF input)
// =============================================================================

/// Wrapper for sqlite3_value_type
/// Returns the datatype code for the value.
pub fn value_type(pVal: ?*c.sqlite3_value) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_NULL;
    const func = api.*.value_type orelse return SQLITE_NULL;
    return func(pVal);
}

/// Wrapper for sqlite3_value_int64
/// Returns the value as a 64-bit integer.
pub fn value_int64(pVal: ?*c.sqlite3_value) c.sqlite3_int64 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.value_int64 orelse return 0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_int
/// Returns the value as a 32-bit integer.
pub fn value_int(pVal: ?*c.sqlite3_value) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.value_int orelse return 0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_double
/// Returns the value as a floating-point number.
pub fn value_double(pVal: ?*c.sqlite3_value) f64 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0.0;
    const func = api.*.value_double orelse return 0.0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_blob
/// Returns the value as a pointer to blob data.
pub fn value_blob(pVal: ?*c.sqlite3_value) ?*const anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.value_blob orelse return null;
    return func(pVal);
}

/// Wrapper for sqlite3_value_bytes
/// Returns the number of bytes in a blob or text value.
pub fn value_bytes(pVal: ?*c.sqlite3_value) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.value_bytes orelse return 0;
    return func(pVal);
}

/// Wrapper for sqlite3_value_text
/// Returns the value as a null-terminated UTF-8 string.
pub fn value_text(pVal: ?*c.sqlite3_value) ?[*:0]const u8 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.value_text orelse return null;
    // The C function returns `const unsigned char*` which Zig sees as `[*c]const u8`
    // We need to cast it to the sentinel-terminated type
    const result = func(pVal);
    if (result == null) return null;
    return @ptrCast(result);
}

// =============================================================================
// Memory Management
// =============================================================================

/// Wrapper for sqlite3_malloc
/// Allocates memory using SQLite's allocator.
pub fn malloc(n: c_int) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.malloc orelse return null;
    return func(n);
}

/// Wrapper for sqlite3_malloc64
/// Allocates memory using SQLite's allocator (64-bit size).
pub fn malloc64(n: c.sqlite3_uint64) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.malloc64 orelse return null;
    return func(n);
}

/// Wrapper for sqlite3_free
/// Frees memory allocated by sqlite3_malloc.
pub fn free(p: ?*anyopaque) void {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return;
    const func = api.*.free orelse return;
    func(p);
}

/// Wrapper for sqlite3_realloc
/// Reallocates memory using SQLite's allocator.
pub fn realloc(pOld: ?*anyopaque, n: c_int) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.realloc orelse return null;
    return func(pOld, n);
}

// =============================================================================
// Context and Database Access
// =============================================================================

/// Wrapper for sqlite3_context_db_handle
/// Returns the database handle associated with a function context.
pub fn context_db_handle(pCtx: ?*c.sqlite3_context) ?*c.sqlite3 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.context_db_handle orelse return null;
    return func(pCtx);
}

/// Wrapper for sqlite3_user_data
/// Returns the user data pointer associated with a function.
pub fn user_data(pCtx: ?*c.sqlite3_context) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.user_data orelse return null;
    return func(pCtx);
}

/// Wrapper for sqlite3_aggregate_context
/// Returns memory for storing aggregate state.
pub fn aggregate_context(pCtx: ?*c.sqlite3_context, nBytes: c_int) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.aggregate_context orelse return null;
    return func(pCtx, nBytes);
}

// =============================================================================
// SQL Execution
// =============================================================================

/// Callback type for sqlite3_exec
pub const ExecCallback = *const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int;

/// Wrapper for sqlite3_exec
/// Executes one or more SQL statements.
pub fn exec(
    db: ?*c.sqlite3,
    sql: [*:0]const u8,
    callback: ?ExecCallback,
    arg: ?*anyopaque,
    pzErrMsg: ?*[*c]u8,
) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.exec orelse return SQLITE_MISUSE;
    return func(db, sql, callback, arg, pzErrMsg);
}

/// Wrapper for sqlite3_errmsg
/// Returns the error message for the most recent error.
pub fn errmsg(db: ?*c.sqlite3) [*c]const u8 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return "API not initialized";
    const func = api.*.errmsg orelse return "errmsg not available";
    return func(db);
}

/// Wrapper for sqlite3_errcode
/// Returns the error code for the most recent error.
pub fn errcode(db: ?*c.sqlite3) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.errcode orelse return SQLITE_MISUSE;
    return func(db);
}

// =============================================================================
// Prepared Statements
// =============================================================================

/// Wrapper for sqlite3_prepare_v2
/// Prepares a SQL statement for execution.
pub fn prepare_v2(
    db: ?*c.sqlite3,
    zSql: [*c]const u8,
    nByte: c_int,
    ppStmt: *?*c.sqlite3_stmt,
    pzTail: ?*[*c]const u8,
) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.prepare_v2 orelse return SQLITE_MISUSE;
    return func(db, zSql, nByte, ppStmt, pzTail);
}

/// Wrapper for sqlite3_step
/// Executes one step of a prepared statement.
pub fn step(pStmt: ?*c.sqlite3_stmt) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.step orelse return SQLITE_MISUSE;
    return func(pStmt);
}

/// Wrapper for sqlite3_finalize
/// Destroys a prepared statement.
pub fn finalize(pStmt: ?*c.sqlite3_stmt) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.finalize orelse return SQLITE_MISUSE;
    return func(pStmt);
}

/// Wrapper for sqlite3_reset
/// Resets a prepared statement for re-execution.
pub fn reset(pStmt: ?*c.sqlite3_stmt) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.reset orelse return SQLITE_MISUSE;
    return func(pStmt);
}

/// Wrapper for sqlite3_column_count
/// Returns the number of columns in the result set.
pub fn column_count(pStmt: ?*c.sqlite3_stmt) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.column_count orelse return 0;
    return func(pStmt);
}

/// Wrapper for sqlite3_column_type
/// Returns the type of a column in the current row.
pub fn column_type(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_NULL;
    const func = api.*.column_type orelse return SQLITE_NULL;
    return func(pStmt, iCol);
}

/// Wrapper for sqlite3_column_int64
/// Returns a column value as a 64-bit integer.
pub fn column_int64(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c.sqlite3_int64 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.column_int64 orelse return 0;
    return func(pStmt, iCol);
}

/// Wrapper for sqlite3_column_double
/// Returns a column value as a floating-point number.
pub fn column_double(pStmt: ?*c.sqlite3_stmt, iCol: c_int) f64 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0.0;
    const func = api.*.column_double orelse return 0.0;
    return func(pStmt, iCol);
}

/// Wrapper for sqlite3_column_text
/// Returns a column value as UTF-8 text.
pub fn column_text(pStmt: ?*c.sqlite3_stmt, iCol: c_int) ?[*:0]const u8 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.column_text orelse return null;
    const result = func(pStmt, iCol);
    if (result == null) return null;
    return @ptrCast(result);
}

/// Wrapper for sqlite3_column_blob
/// Returns a column value as a blob.
pub fn column_blob(pStmt: ?*c.sqlite3_stmt, iCol: c_int) ?*const anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.column_blob orelse return null;
    return func(pStmt, iCol);
}

/// Wrapper for sqlite3_column_bytes
/// Returns the size of a column value in bytes.
pub fn column_bytes(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.column_bytes orelse return 0;
    return func(pStmt, iCol);
}

/// Wrapper for sqlite3_column_value
/// Returns the column value as an unprotected sqlite3_value object.
/// The returned value is valid only until the next sqlite3_step() or finalize().
pub fn column_value(pStmt: ?*c.sqlite3_stmt, iCol: c_int) ?*c.sqlite3_value {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.column_value orelse return null;
    return func(pStmt, iCol);
}

// =============================================================================
// Bind Functions (for prepared statements)
// =============================================================================

/// Wrapper for sqlite3_bind_int64
/// Binds a 64-bit integer to a prepared statement parameter.
pub fn bind_int64(pStmt: ?*c.sqlite3_stmt, i: c_int, val: c.sqlite3_int64) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.bind_int64 orelse return SQLITE_MISUSE;
    return func(pStmt, i, val);
}

/// Wrapper for sqlite3_bind_text
/// Binds a text value to a prepared statement parameter.
pub fn bind_text(pStmt: ?*c.sqlite3_stmt, i: c_int, z: [*c]const u8, n: c_int, xDel: DestructorFn) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.bind_text orelse return SQLITE_MISUSE;
    return func(pStmt, i, z, n, xDel);
}

/// Wrapper for sqlite3_bind_blob
/// Binds a blob value to a prepared statement parameter.
pub fn bind_blob(pStmt: ?*c.sqlite3_stmt, i: c_int, z: ?*const anyopaque, n: c_int, xDel: DestructorFn) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.bind_blob orelse return SQLITE_MISUSE;
    return func(pStmt, i, z, n, xDel);
}

/// Wrapper for sqlite3_bind_null
/// Binds NULL to a prepared statement parameter.
pub fn bind_null(pStmt: ?*c.sqlite3_stmt, i: c_int) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.bind_null orelse return SQLITE_MISUSE;
    return func(pStmt, i);
}

/// Wrapper for sqlite3_bind_double
/// Binds a floating-point value to a prepared statement parameter.
pub fn bind_double(pStmt: ?*c.sqlite3_stmt, i: c_int, val: f64) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return SQLITE_MISUSE;
    const func = api.*.bind_double orelse return SQLITE_MISUSE;
    return func(pStmt, i, val);
}

// =============================================================================
// Hooks
// =============================================================================

/// Callback type for commit hook
pub const CommitHookFn = *const fn (?*anyopaque) callconv(.c) c_int;

/// Callback type for rollback hook
pub const RollbackHookFn = *const fn (?*anyopaque) callconv(.c) void;

/// Callback type for update hook
pub const UpdateHookFn = *const fn (?*anyopaque, c_int, [*c]const u8, [*c]const u8, c.sqlite3_int64) callconv(.c) void;

/// Wrapper for sqlite3_commit_hook
/// Registers a callback invoked when a transaction is committed.
pub fn commit_hook(
    db: ?*c.sqlite3,
    callback: ?CommitHookFn,
    pArg: ?*anyopaque,
) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.commit_hook orelse return null;
    return func(db, callback, pArg);
}

/// Wrapper for sqlite3_rollback_hook
/// Registers a callback invoked when a transaction is rolled back.
pub fn rollback_hook(
    db: ?*c.sqlite3,
    callback: ?RollbackHookFn,
    pArg: ?*anyopaque,
) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.rollback_hook orelse return null;
    return func(db, callback, pArg);
}

/// Wrapper for sqlite3_update_hook
/// Registers a callback invoked when a row is modified.
pub fn update_hook(
    db: ?*c.sqlite3,
    callback: ?UpdateHookFn,
    pArg: ?*anyopaque,
) ?*anyopaque {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return null;
    const func = api.*.update_hook orelse return null;
    return func(db, callback, pArg);
}

// =============================================================================
// Miscellaneous
// =============================================================================

/// Wrapper for sqlite3_changes
/// Returns the number of rows modified by the last INSERT, UPDATE, or DELETE.
pub fn changes(db: ?*c.sqlite3) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.changes orelse return 0;
    return func(db);
}

/// Wrapper for sqlite3_last_insert_rowid
/// Returns the rowid of the most recent successful INSERT.
pub fn last_insert_rowid(db: ?*c.sqlite3) c.sqlite3_int64 {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.last_insert_rowid orelse return 0;
    return func(db);
}

/// Wrapper for sqlite3_get_autocommit
/// Returns non-zero if auto-commit mode is on.
pub fn get_autocommit(db: ?*c.sqlite3) c_int {
    const api = sqlite_c.sqlite3_api;
    if (api == null) return 0;
    const func = api.*.get_autocommit orelse return 0;
    return func(db);
}

// =============================================================================
// Tests
// =============================================================================

test "initApi and isInitialized" {
    // Reset for test isolation
    sqlite_c.sqlite3_api = null;
    try std.testing.expect(!isInitialized());

    // Null should fail
    const result_null_code = initApi(null);
    try std.testing.expectEqual(SQLITE_ERROR, result_null_code);
    try std.testing.expect(!isInitialized());
}

test "wrappers return safe defaults when sqlite3_api is null" {
    // Ensure API is not initialized
    sqlite_c.sqlite3_api = null;

    // Virtual table registration should return SQLITE_MISUSE
    try std.testing.expectEqual(SQLITE_MISUSE, create_module_v2(null, "test", null, null, null));
    try std.testing.expectEqual(SQLITE_MISUSE, declare_vtab(null, "CREATE TABLE x(a)"));

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
    try std.testing.expectEqual(@as(c.sqlite3_int64, 0), value_int64(null));
    try std.testing.expectEqual(@as(f64, 0.0), value_double(null));
    try std.testing.expectEqual(@as(?*const anyopaque, null), value_blob(null));
    try std.testing.expectEqual(@as(c_int, 0), value_bytes(null));
    try std.testing.expectEqual(@as(?[*:0]const u8, null), value_text(null));
}
