//! clset Virtual Table Module - Causal Length Set Schema Table
//!
//! The `clset` module creates a virtual table with a `_schema` suffix that:
//! 1. Creates a physical base storage table (name without `_schema` suffix)
//! 2. Converts that base table to a CRR using existing `crsql_as_crr` logic
//! 3. Uses the virtual table interface for CREATE/DROP lifecycle management
//!
//! Usage:
//! ```sql
//! CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
//! -- Creates base table "foo" and makes it a CRR
//! -- Creates foo__crsql_clock and foo__crsql_pks tables
//!
//! INSERT INTO foo VALUES (1, 2);  -- Works on the base table
//!
//! DROP TABLE foo_schema;  -- Cleans up all foo-related tables
//! ```
//!
//! Reference: `core/rs/core/src/create_cl_set_vtab.rs`

const std = @import("std");
const vtab = @import("sqlite/vtab.zig");
const api = @import("ffi/api.zig");
const as_crr = @import("as_crr.zig");

/// SQL buffer size for DDL generation
const SQL_BUF_SIZE = 8192;

/// Maximum length for table names
const MAX_TABLE_NAME_LEN = 1024;

// =============================================================================
// Virtual Table Structure
// =============================================================================

/// clset virtual table instance
/// Embedded `base` as first field allows pointer casting to/from vtab.VTab
const ClsetVTab = extern struct {
    base: vtab.VTab,
    db: ?*vtab.sqlite3,
    // Base table name (without _schema suffix)
    // Stored as pointer for extern struct compatibility
    base_table_name_ptr: ?[*]u8,
    base_table_name_len: usize,
    // Database name (usually "main")
    db_name_ptr: ?[*]u8,
    db_name_len: usize,
};

// =============================================================================
// Cursor Structure (minimal - schema-only vtab)
// =============================================================================

/// clset cursor - minimal since this is a schema-only vtab
const ClsetCursor = extern struct {
    base: vtab.VTabCursor,
};

// =============================================================================
// SQLite API Wrappers
// =============================================================================

/// sqlite3_declare_vtab wrapper
fn declareVtab(db: ?*api.sqlite3, schema: [*:0]const u8) c_int {
    return api.declare_vtab(@ptrCast(db), schema);
}

/// sqlite3_malloc wrapper
fn sqliteMalloc(n: c_int) ?*anyopaque {
    return api.malloc(n);
}

/// sqlite3_free wrapper
fn sqliteFree(ptr: ?*anyopaque) void {
    api.free(ptr);
}

/// Allocate and set an error message
fn setErrorMessage(pzErr: [*c][*c]u8, msg: []const u8) void {
    if (pzErr == null) return;
    const alloc = sqliteMalloc(@intCast(msg.len + 1));
    if (alloc) |ptr| {
        const err_ptr: [*]u8 = @ptrCast(ptr);
        @memcpy(err_ptr[0..msg.len], msg);
        err_ptr[msg.len] = 0;
        pzErr.* = err_ptr;
    }
}

fn toApiDb(db: ?*vtab.sqlite3) ?*api.sqlite3 {
    return @ptrCast(db);
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Check if table name ends with _schema suffix
fn endsWithSchema(name: []const u8) bool {
    const suffix = "_schema";
    if (name.len < suffix.len) return false;
    return std.mem.endsWith(u8, name, suffix);
}

/// Get base table name from virtual table name (strip _schema suffix)
fn getBaseTableName(virtual_name: []const u8) ?[]const u8 {
    const suffix = "_schema";
    if (!endsWithSchema(virtual_name)) return null;
    return virtual_name[0 .. virtual_name.len - suffix.len];
}

/// Check if a table has a PRIMARY KEY
fn tableHasPrimaryKey(db: ?*api.sqlite3, table_name: []const u8) bool {
    // Build PRAGMA table_info query
    var pragma_buf: [512]u8 = undefined;
    const pragma_sql = std.fmt.bufPrintZ(&pragma_buf, "PRAGMA table_info(\"{s}\")", .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, pragma_sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    // PRAGMA table_info returns: cid, name, type, notnull, dflt_value, pk
    // Column 5 is pk (0 = not PK, 1+ = PK index)
    while (api.step(stmt) == api.SQLITE_ROW) {
        const pk_val = api.column_int64(stmt, 5);
        if (pk_val > 0) {
            return true;
        }
    }

    return false;
}

/// Check if a table already exists
fn tableExists(db: ?*api.sqlite3, table_name: []const u8) bool {
    var sql_buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&sql_buf, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='{s}'", .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    return api.step(stmt) == api.SQLITE_ROW;
}

// =============================================================================
// Virtual Table Callbacks
// =============================================================================

/// xCreate - Create the virtual table (called for CREATE VIRTUAL TABLE)
/// This does the real work: creates base table + calls crsql_as_crr
fn clsetCreate(
    db: ?*vtab.sqlite3,
    _: ?*anyopaque, // pAux
    argc: c_int,
    argv: [*c]const [*c]const u8,
    ppVTab: [*c]?*vtab.VTab,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int {
    // argc < 4 means missing required arguments
    // argv[0] = module name
    // argv[1] = database name
    // argv[2] = virtual table name
    // argv[3+] = column definitions
    if (argc < 4) {
        setErrorMessage(pzErr, "clset requires column definitions");
        return vtab.SQLITE_ERROR;
    }

    // Get database name (argv[1])
    const db_name_cstr = argv[1];
    if (db_name_cstr == null) {
        setErrorMessage(pzErr, "clset: missing database name");
        return vtab.SQLITE_ERROR;
    }
    const db_name = std.mem.span(db_name_cstr);

    // Get virtual table name (argv[2])
    const vtab_name_cstr = argv[2];
    if (vtab_name_cstr == null) {
        setErrorMessage(pzErr, "clset: missing table name");
        return vtab.SQLITE_ERROR;
    }
    const vtab_name = std.mem.span(vtab_name_cstr);

    // Check that virtual table name ends with _schema
    if (!endsWithSchema(vtab_name)) {
        // Build error message with table name
        var err_buf: [256]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&err_buf, "{s} MUST end with _schema. E.g., {s}_schema", .{ vtab_name, vtab_name }) catch "Table name must end with _schema";
        setErrorMessage(pzErr, err_msg);
        return vtab.SQLITE_ERROR;
    }

    // Get base table name
    const base_name = getBaseTableName(vtab_name) orelse {
        setErrorMessage(pzErr, "clset: invalid table name");
        return vtab.SQLITE_ERROR;
    };

    // Build column definitions from argv[3..]
    var col_buf: [SQL_BUF_SIZE]u8 = undefined;
    var col_fbs = std.io.fixedBufferStream(&col_buf);
    const col_writer = col_fbs.writer();

    var first = true;
    for (@intCast(3)..@as(usize, @intCast(argc))) |i| {
        const arg = argv[i];
        if (arg != null) {
            if (!first) {
                col_writer.writeAll(", ") catch {
                    setErrorMessage(pzErr, "clset: column definitions too long");
                    return vtab.SQLITE_ERROR;
                };
            }
            col_writer.writeAll(std.mem.span(arg)) catch {
                setErrorMessage(pzErr, "clset: column definitions too long");
                return vtab.SQLITE_ERROR;
            };
            first = false;
        }
    }

    const col_def_len = col_fbs.pos;
    const col_def = col_buf[0..col_def_len];

    // Check if base table already exists (for IF NOT EXISTS support)
    const api_db = toApiDb(db);
    const base_table_exists = tableExists(api_db, base_name);

    if (!base_table_exists) {
        // Create the base storage table
        var create_buf: [SQL_BUF_SIZE]u8 = undefined;
        const create_sql = std.fmt.bufPrintZ(&create_buf, "CREATE TABLE \"{s}\".\"{s}\" ({s})", .{ db_name, base_name, col_def }) catch {
            setErrorMessage(pzErr, "clset: SQL too long");
            return vtab.SQLITE_ERROR;
        };

        var err_msg: ?[*:0]u8 = null;
        const create_rc = api.exec(api_db, create_sql, null, null, @ptrCast(&err_msg));
        if (create_rc != api.SQLITE_OK) {
            if (err_msg) |msg| {
                // Copy the SQLite error message
                setErrorMessage(pzErr, std.mem.span(msg));
                api.free(@ptrCast(@constCast(msg)));
            } else {
                setErrorMessage(pzErr, "clset: failed to create base table");
            }
            return create_rc;
        }

        // Verify the table has a primary key
        if (!tableHasPrimaryKey(api_db, base_name)) {
            // Drop the table we just created
            var drop_buf: [512]u8 = undefined;
            const drop_sql = std.fmt.bufPrintZ(&drop_buf, "DROP TABLE \"{s}\".\"{s}\"", .{ db_name, base_name }) catch "";
            _ = api.exec(api_db, drop_sql, null, null, null);

            setErrorMessage(pzErr, "clset: table must have a primary key");
            return vtab.SQLITE_ERROR;
        }

        // Convert the base table to a CRR using internal function (no savepoint)
        // Note: We can't use savepoints during xCreate as per Rust implementation comment
        as_crr.createCrrInternal(api_db, base_name) catch {
            // Clean up the base table
            var drop_buf: [512]u8 = undefined;
            const drop_sql = std.fmt.bufPrintZ(&drop_buf, "DROP TABLE \"{s}\".\"{s}\"", .{ db_name, base_name }) catch "";
            _ = api.exec(api_db, drop_sql, null, null, null);

            setErrorMessage(pzErr, "clset: failed to create CRR infrastructure");
            return vtab.SQLITE_ERROR;
        };
    }

    // Now set up the virtual table structure
    return clsetConnectShared(db, base_name, db_name, ppVTab, pzErr);
}

/// xConnect - Connect to an existing virtual table
/// This just sets up the vtab structure without creating anything
fn clsetConnect(
    db: ?*vtab.sqlite3,
    _: ?*anyopaque, // pAux
    argc: c_int,
    argv: [*c]const [*c]const u8,
    ppVTab: [*c]?*vtab.VTab,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int {
    if (argc < 3) {
        setErrorMessage(pzErr, "clset: missing arguments");
        return vtab.SQLITE_ERROR;
    }

    // Get database name (argv[1])
    const db_name_cstr = argv[1];
    if (db_name_cstr == null) {
        return vtab.SQLITE_ERROR;
    }
    const db_name = std.mem.span(db_name_cstr);

    // Get virtual table name (argv[2])
    const vtab_name_cstr = argv[2];
    if (vtab_name_cstr == null) {
        return vtab.SQLITE_ERROR;
    }
    const vtab_name = std.mem.span(vtab_name_cstr);

    // Get base table name
    const base_name = getBaseTableName(vtab_name) orelse {
        setErrorMessage(pzErr, "clset: table name must end with _schema");
        return vtab.SQLITE_ERROR;
    };

    return clsetConnectShared(db, base_name, db_name, ppVTab, pzErr);
}

/// Shared setup for xCreate and xConnect
fn clsetConnectShared(
    db: ?*vtab.sqlite3,
    base_name: []const u8,
    db_name: []const u8,
    ppVTab: [*c]?*vtab.VTab,
    pzErr: [*c][*c]u8,
) c_int {
    // Declare the schema - hidden columns for schema management
    // Reference: Rust create_cl_set_vtab.rs connect_create_shared
    const schema = "CREATE TABLE x(alteration TEXT HIDDEN, schema TEXT HIDDEN)";
    const rc = declareVtab(toApiDb(db), schema);
    if (rc != vtab.SQLITE_OK) {
        setErrorMessage(pzErr, "clset: failed to declare vtab schema");
        return rc;
    }

    // Allocate the vtab structure
    const pNew = sqliteMalloc(@sizeOf(ClsetVTab));
    if (pNew == null) {
        return vtab.SQLITE_NOMEM;
    }

    const pVTab: *ClsetVTab = @ptrCast(@alignCast(pNew));
    @memset(std.mem.asBytes(pVTab), 0);
    pVTab.db = db;

    // Allocate and copy base table name
    const base_name_alloc = sqliteMalloc(@intCast(base_name.len));
    if (base_name_alloc == null) {
        sqliteFree(pNew);
        return vtab.SQLITE_NOMEM;
    }
    const base_name_ptr: [*]u8 = @ptrCast(base_name_alloc);
    @memcpy(base_name_ptr[0..base_name.len], base_name);
    pVTab.base_table_name_ptr = base_name_ptr;
    pVTab.base_table_name_len = base_name.len;

    // Allocate and copy db name
    const db_name_alloc = sqliteMalloc(@intCast(db_name.len));
    if (db_name_alloc == null) {
        sqliteFree(base_name_alloc);
        sqliteFree(pNew);
        return vtab.SQLITE_NOMEM;
    }
    const db_name_ptr: [*]u8 = @ptrCast(db_name_alloc);
    @memcpy(db_name_ptr[0..db_name.len], db_name);
    pVTab.db_name_ptr = db_name_ptr;
    pVTab.db_name_len = db_name.len;

    ppVTab.* = &pVTab.base;
    return vtab.SQLITE_OK;
}

/// xDisconnect - Disconnect from the virtual table (does not destroy data)
fn clsetDisconnect(pVTab: ?*vtab.VTab) callconv(.c) c_int {
    if (pVTab) |vt| {
        const pClsetVTab: *ClsetVTab = @ptrCast(@alignCast(vt));

        // Free base table name
        if (pClsetVTab.base_table_name_ptr) |ptr| {
            sqliteFree(ptr);
        }

        // Free db name
        if (pClsetVTab.db_name_ptr) |ptr| {
            sqliteFree(ptr);
        }

        sqliteFree(vt);
    }
    return vtab.SQLITE_OK;
}

/// xDestroy - Drop the virtual table and all related tables
/// Reference: Rust create_cl_set_vtab.rs destroy()
fn clsetDestroy(pVTab: ?*vtab.VTab) callconv(.c) c_int {
    if (pVTab) |vt| {
        const pClsetVTab: *ClsetVTab = @ptrCast(@alignCast(vt));
        const api_db = toApiDb(pClsetVTab.db);

        // Get table and db names
        const base_name = if (pClsetVTab.base_table_name_ptr) |ptr|
            ptr[0..pClsetVTab.base_table_name_len]
        else
            return vtab.SQLITE_ERROR;

        const db_name = if (pClsetVTab.db_name_ptr) |ptr|
            ptr[0..pClsetVTab.db_name_len]
        else
            return vtab.SQLITE_ERROR;

        // First, tear down CRR infrastructure using crsql_as_table
        var as_table_buf: [512]u8 = undefined;
        const as_table_sql = std.fmt.bufPrintZ(&as_table_buf, "SELECT crsql_as_table('{s}')", .{base_name}) catch {
            return vtab.SQLITE_ERROR;
        };
        _ = api.exec(api_db, as_table_sql, null, null, null);

        // Drop the base table
        var drop_buf: [512]u8 = undefined;
        const drop_sql = std.fmt.bufPrintZ(&drop_buf, "DROP TABLE IF EXISTS \"{s}\".\"{s}\"", .{ db_name, base_name }) catch {
            return vtab.SQLITE_ERROR;
        };
        _ = api.exec(api_db, drop_sql, null, null, null);
    }

    // Call disconnect to free the vtab structure
    return clsetDisconnect(pVTab);
}

/// xBestIndex - Query planning (minimal for schema-only vtab)
fn clsetBestIndex(pVTab: ?*vtab.VTab, pIdxInfo: ?*vtab.IndexInfo) callconv(.c) c_int {
    _ = pVTab;
    if (pIdxInfo) |info| {
        info.estimatedCost = 1000000.0;
        info.estimatedRows = 0; // No rows in this virtual table
    }
    return vtab.SQLITE_OK;
}

/// xOpen - Create a cursor (minimal for schema-only vtab)
fn clsetOpen(pVTab: ?*vtab.VTab, ppCursor: [*c]?*vtab.VTabCursor) callconv(.c) c_int {
    _ = pVTab;

    const pCur = sqliteMalloc(@sizeOf(ClsetCursor));
    if (pCur == null) {
        return vtab.SQLITE_NOMEM;
    }

    const cursor: *ClsetCursor = @ptrCast(@alignCast(pCur));
    @memset(std.mem.asBytes(cursor), 0);

    ppCursor.* = &cursor.base;
    return vtab.SQLITE_OK;
}

/// xClose - Close a cursor
fn clsetClose(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    if (pCursor) |cur| {
        sqliteFree(cur);
    }
    return vtab.SQLITE_OK;
}

/// xFilter - Begin a scan (always empty for schema-only vtab)
fn clsetFilter(
    pCursor: ?*vtab.VTabCursor,
    _: c_int, // idxNum
    _: [*c]const u8, // idxStr
    _: c_int, // argc
    _: [*c]?*vtab.sqlite3_value, // argv
) callconv(.c) c_int {
    _ = pCursor;
    return vtab.SQLITE_OK;
}

/// xNext - Advance cursor (no-op for empty vtab)
fn clsetNext(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    _ = pCursor;
    return vtab.SQLITE_OK;
}

/// xEof - Always at EOF (schema-only vtab has no rows)
fn clsetEof(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    _ = pCursor;
    return 1; // Always at EOF
}

/// xColumn - Return column value (no columns to return)
fn clsetColumn(
    pCursor: ?*vtab.VTabCursor,
    pCtx: ?*vtab.sqlite3_context,
    _: c_int, // col
) callconv(.c) c_int {
    _ = pCursor;
    api.result_null(@ptrCast(pCtx));
    return vtab.SQLITE_OK;
}

/// xRowid - Return rowid (no rows, return 0)
fn clsetRowid(pCursor: ?*vtab.VTabCursor, pRowid: *i64) callconv(.c) c_int {
    _ = pCursor;
    pRowid.* = 0;
    return vtab.SQLITE_OK;
}

// =============================================================================
// Module Definition
// =============================================================================

/// The clset module definition
pub const clset_module = vtab.Module{
    .iVersion = 0,
    .xCreate = clsetCreate,
    .xConnect = clsetConnect,
    .xBestIndex = clsetBestIndex,
    .xDisconnect = clsetDisconnect,
    .xDestroy = clsetDestroy,
    .xOpen = clsetOpen,
    .xClose = clsetClose,
    .xFilter = clsetFilter,
    .xNext = clsetNext,
    .xEof = clsetEof,
    .xColumn = clsetColumn,
    .xRowid = clsetRowid,
    .xUpdate = null, // Schema-only vtab, no INSERT/UPDATE/DELETE
    .xBegin = null,
    .xSync = null,
    .xCommit = null,
    .xRollback = null,
    .xFindFunction = null,
    .xRename = null,
    .xSavepoint = null,
    .xRelease = null,
    .xRollbackTo = null,
    .xShadowName = null,
    .xIntegrity = null,
};

/// Register the clset virtual table module with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_module_v2(db, "clset", @ptrCast(&clset_module), null, null);
}

// =============================================================================
// Tests
// =============================================================================

test "endsWithSchema detects suffix correctly" {
    try std.testing.expect(endsWithSchema("foo_schema"));
    try std.testing.expect(endsWithSchema("bar_test_schema"));
    try std.testing.expect(!endsWithSchema("foo"));
    try std.testing.expect(!endsWithSchema("foo_schem"));
    try std.testing.expect(!endsWithSchema("_schema")); // Edge case: just the suffix
}

test "getBaseTableName strips suffix correctly" {
    const result1 = getBaseTableName("foo_schema");
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("foo", result1.?);

    const result2 = getBaseTableName("my_table_schema");
    try std.testing.expect(result2 != null);
    try std.testing.expectEqualStrings("my_table", result2.?);

    // Invalid cases
    try std.testing.expect(getBaseTableName("foo") == null);
    try std.testing.expect(getBaseTableName("_schema") == null);
}

test "module struct is properly configured" {
    try std.testing.expect(clset_module.xCreate != null);
    try std.testing.expect(clset_module.xConnect != null);
    try std.testing.expect(clset_module.xBestIndex != null);
    try std.testing.expect(clset_module.xDisconnect != null);
    try std.testing.expect(clset_module.xDestroy != null);
    try std.testing.expect(clset_module.xOpen != null);
    try std.testing.expect(clset_module.xClose != null);
    try std.testing.expect(clset_module.xFilter != null);
    try std.testing.expect(clset_module.xNext != null);
    try std.testing.expect(clset_module.xEof != null);
    try std.testing.expect(clset_module.xColumn != null);
    try std.testing.expect(clset_module.xRowid != null);
    // xUpdate is null for schema-only vtab
    try std.testing.expect(clset_module.xUpdate == null);
}
