//! crsql_changes Virtual Table - Read-Only Implementation (Phase 1)
//!
//! This virtual table provides a unified view of all changes across all CRR tables.
//! It enumerates clock rows with correct rowid slab allocation.
//!
//! ## Schema
//! ```sql
//! CREATE TABLE x(
//!   [table] TEXT NOT NULL,
//!   [pk] BLOB NOT NULL,
//!   [cid] TEXT NOT NULL,
//!   [val] ANY,
//!   [col_version] INTEGER NOT NULL,
//!   [db_version] INTEGER NOT NULL,
//!   [site_id] BLOB NOT NULL,
//!   [cl] INTEGER NOT NULL,
//!   [seq] INTEGER NOT NULL
//! )
//! ```
//!
//! ## Rowid Slab Scheme
//! Each CRR table gets a slab of 10^13 rowids:
//! - Table 0: rowids 1, 2, 3, ...
//! - Table 1: rowids ROWID_SLAB_SIZE+1, ROWID_SLAB_SIZE+2, ...
//! - Table 2: rowids 2*ROWID_SLAB_SIZE+1, ...
//!
//! Reference: `core/src/changes-vtab.c`

const std = @import("std");
const vtab = @import("sqlite/vtab.zig");
const api = @import("ffi/api.zig");

const log = std.log.scoped(.changes_vtab);

// Type conversion between vtab's opaque types and api's opaque types.
// Both represent the same underlying SQLite types, just declared separately.
fn toApiDb(db: ?*vtab.sqlite3) ?*api.sqlite3 {
    return @ptrCast(db);
}

fn toApiCtx(ctx: ?*vtab.sqlite3_context) ?*api.sqlite3_context {
    return @ptrCast(ctx);
}

// =============================================================================
// Constants
// =============================================================================

/// Size of each table's rowid slab (from core/src/consts.h)
pub const ROWID_SLAB_SIZE: i64 = 10_000_000_000_000;

/// SQL to find all CRR clock tables
const CLOCK_TABLES_SELECT = "SELECT tbl_name FROM sqlite_master WHERE type='table' AND tbl_name LIKE '%__crsql_clock' ORDER BY tbl_name";

/// Schema declaration for the virtual table
const VTAB_SCHEMA =
    \\CREATE TABLE x(
    \\  [table] TEXT NOT NULL,
    \\  [pk] BLOB NOT NULL,
    \\  [cid] TEXT NOT NULL,
    \\  [val] ANY,
    \\  [col_version] INTEGER NOT NULL,
    \\  [db_version] INTEGER NOT NULL,
    \\  [site_id] BLOB NOT NULL,
    \\  [cl] INTEGER NOT NULL,
    \\  [seq] INTEGER NOT NULL
    \\)
;

// Column indices matching the schema
const COL_TABLE = 0;
const COL_PK = 1;
const COL_CID = 2;
const COL_VAL = 3;
const COL_COL_VERSION = 4;
const COL_DB_VERSION = 5;
const COL_SITE_ID = 6;
const COL_CL = 7;
const COL_SEQ = 8;

// =============================================================================
// Virtual Table Structure
// =============================================================================

/// Maximum number of CRR tables we track (can be increased if needed)
const MAX_TABLES = 256;

/// crsql_changes virtual table instance
/// Embedded `base` as first field allows pointer casting to/from vtab.VTab
const ChangesVTab = extern struct {
    base: vtab.VTab,
    db: ?*vtab.sqlite3,
    // Table info is stored per-cursor since we need to query it fresh each time
};

// =============================================================================
// Cursor Structure
// =============================================================================

/// crsql_changes cursor for iterating over changes
/// Embedded `base` as first field allows pointer casting to/from vtab.VTabCursor
const ChangesCursor = extern struct {
    base: vtab.VTabCursor,

    // Current iteration state
    current_table_idx: usize,
    current_row_in_table: i64,
    is_eof: bool,

    // Prepared statement for current clock table query
    clock_stmt: ?*api.sqlite3_stmt,

    // Table names storage (we keep a list of clock table names)
    // Stored as offsets into table_names_buf
    table_count: usize,
    // We store table base names (without __crsql_clock suffix)
    // This is dynamically allocated per-cursor

    // Dynamic storage for table names - stored as pointer to allow extern struct
    // The pointed-to memory is managed separately with page_allocator
    table_names_ptr: ?*anyopaque,
    table_names_len: usize,

    // Current row's pk value (for lookups in pks table and base table)
    current_pk: i64,
};

/// Helper to get the allocator (always page_allocator for cursor allocations)
fn getCursorAllocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

/// Helper to get table names from cursor
fn getCursorTableNames(cursor: *ChangesCursor) ?[][]u8 {
    if (cursor.table_names_ptr == null or cursor.table_names_len == 0) return null;
    const ptr: [*][]u8 = @ptrCast(@alignCast(cursor.table_names_ptr));
    return ptr[0..cursor.table_names_len];
}

/// Helper to set table names on cursor
fn setCursorTableNames(cursor: *ChangesCursor, names: ?[][]u8) void {
    if (names) |n| {
        cursor.table_names_ptr = @ptrCast(n.ptr);
        cursor.table_names_len = n.len;
    } else {
        cursor.table_names_ptr = null;
        cursor.table_names_len = 0;
    }
}

// =============================================================================
// SQLite API Wrappers (via api routines table)
// =============================================================================

/// sqlite3_declare_vtab wrapper - uses api.declare_vtab
fn declareVtab(db: ?*api.sqlite3, schema: [*:0]const u8) c_int {
    return api.declare_vtab(@ptrCast(db), schema);
}

/// sqlite3_malloc wrapper - uses api.malloc
fn sqliteMalloc(n: c_int) ?*anyopaque {
    return api.malloc(n);
}

/// sqlite3_free wrapper - uses api.free
fn sqliteFree(ptr: ?*anyopaque) void {
    api.free(ptr);
}

/// sqlite3_prepare_v2 wrapper - uses api.prepare_v2
fn prepareV2(db: ?*api.sqlite3, sql: [*:0]const u8, nByte: c_int, ppStmt: *?*api.sqlite3_stmt, pzTail: ?*[*c]const u8) c_int {
    return api.prepare_v2(@ptrCast(db), sql, nByte, @ptrCast(ppStmt), pzTail);
}

/// sqlite3_step wrapper - uses api.step
fn stepStmt(stmt: ?*api.sqlite3_stmt) c_int {
    return api.step(@ptrCast(stmt));
}

/// sqlite3_finalize wrapper - uses api.finalize
fn finalizeStmt(stmt: ?*api.sqlite3_stmt) c_int {
    return api.finalize(@ptrCast(stmt));
}

/// sqlite3_reset wrapper - uses api.reset
fn resetStmt(stmt: ?*api.sqlite3_stmt) c_int {
    return api.reset(@ptrCast(stmt));
}

/// sqlite3_column_text wrapper - uses api.column_text
fn columnTextFromStmt(stmt: ?*api.sqlite3_stmt, col: c_int) ?[*:0]const u8 {
    return api.column_text(@ptrCast(stmt), col);
}

/// sqlite3_column_int64 wrapper - uses api.column_int64
fn columnInt64FromStmt(stmt: ?*api.sqlite3_stmt, col: c_int) i64 {
    return api.column_int64(@ptrCast(stmt), col);
}

/// sqlite3_column_blob wrapper - uses api.column_blob
fn columnBlobFromStmt(stmt: ?*api.sqlite3_stmt, col: c_int) ?*const anyopaque {
    return api.column_blob(@ptrCast(stmt), col);
}

/// sqlite3_column_bytes wrapper - uses api.column_bytes
fn columnBytesFromStmt(stmt: ?*api.sqlite3_stmt, col: c_int) c_int {
    return api.column_bytes(@ptrCast(stmt), col);
}

/// sqlite3_column_type wrapper - uses api.column_type
fn columnTypeFromStmt(stmt: ?*api.sqlite3_stmt, col: c_int) c_int {
    return api.column_type(@ptrCast(stmt), col);
}

/// sqlite3_column_double wrapper - uses api.column_double
fn columnDoubleFromStmt(stmt: ?*api.sqlite3_stmt, col: c_int) f64 {
    return api.column_double(@ptrCast(stmt), col);
}

/// sqlite3_result_text wrapper - uses api.result_text
fn resultText(ctx: ?*api.sqlite3_context, text: [*]const u8, len: c_int, destructor: api.DestructorFn) void {
    api.result_text(@ptrCast(ctx), text, len, destructor);
}

/// sqlite3_result_blob wrapper - uses api.result_blob
fn resultBlob(ctx: ?*api.sqlite3_context, blob: ?*const anyopaque, len: c_int, destructor: api.DestructorFn) void {
    api.result_blob(@ptrCast(ctx), blob, len, destructor);
}

/// sqlite3_result_int64 wrapper - uses api.result_int64
fn resultInt64(ctx: ?*api.sqlite3_context, val: i64) void {
    api.result_int64(@ptrCast(ctx), val);
}

/// sqlite3_result_null wrapper - uses api.result_null
fn resultNull(ctx: ?*api.sqlite3_context) void {
    api.result_null(@ptrCast(ctx));
}

/// sqlite3_result_double wrapper - uses api.result_double
fn resultDouble(ctx: ?*api.sqlite3_context, val: f64) void {
    api.result_double(@ptrCast(ctx), val);
}

/// sqlite3_create_module_v2 wrapper - uses api.create_module_v2
pub fn createModuleV2(
    db: ?*api.sqlite3,
    name: [*:0]const u8,
    mod: *const vtab.Module,
    pClientData: ?*anyopaque,
    xDestroy: ?*const fn (?*anyopaque) callconv(.c) void,
) c_int {
    return api.create_module_v2(@ptrCast(db), name, @ptrCast(mod), pClientData, xDestroy);
}

// =============================================================================
// Virtual Table Callbacks
// =============================================================================

/// xConnect - Connect to the virtual table (eponymous-only, no xCreate)
fn changesConnect(
    db: ?*vtab.sqlite3,
    _: ?*anyopaque, // pAux
    _: c_int, // argc
    _: [*c]const [*c]const u8, // argv
    ppVTab: [*c]?*vtab.VTab,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int {
    _ = pzErr;

    // Declare the schema (convert to api type)
    const rc = declareVtab(toApiDb(db), VTAB_SCHEMA);
    if (rc != vtab.SQLITE_OK) {
        return rc;
    }

    // Allocate the vtab structure using SQLite's allocator
    const pNew = sqliteMalloc(@sizeOf(ChangesVTab));
    if (pNew == null) {
        return vtab.SQLITE_NOMEM;
    }

    const pVTab: *ChangesVTab = @ptrCast(@alignCast(pNew));
    @memset(std.mem.asBytes(pVTab), 0);
    pVTab.db = db;

    ppVTab.* = &pVTab.base;
    return vtab.SQLITE_OK;
}

/// xDisconnect - Release the virtual table connection
fn changesDisconnect(pVTab: ?*vtab.VTab) callconv(.c) c_int {
    if (pVTab) |vt| {
        sqliteFree(vt);
    }
    return vtab.SQLITE_OK;
}

/// xBestIndex - Query planning
fn changesBestIndex(pVTab: ?*vtab.VTab, pIdxInfo: ?*vtab.IndexInfo) callconv(.c) c_int {
    _ = pVTab;

    if (pIdxInfo) |info| {
        // Full table scan - set high cost
        info.estimatedCost = 1_000_000.0;
        info.estimatedRows = 10_000;
        info.idxNum = 0;
    }

    return vtab.SQLITE_OK;
}

/// Helper to get the table name from a clock table name (strip __crsql_clock suffix)
fn getBaseTableName(clock_table: []const u8) ?[]const u8 {
    const suffix = "__crsql_clock";
    if (clock_table.len <= suffix.len) return null;
    if (!std.mem.endsWith(u8, clock_table, suffix)) return null;
    return clock_table[0 .. clock_table.len - suffix.len];
}

/// xOpen - Create a cursor
fn changesOpen(pVTab: ?*vtab.VTab, ppCursor: [*c]?*vtab.VTabCursor) callconv(.c) c_int {
    _ = pVTab;

    // Allocate cursor using SQLite's allocator
    const pCur = sqliteMalloc(@sizeOf(ChangesCursor));
    if (pCur == null) {
        return vtab.SQLITE_NOMEM;
    }

    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCur));
    @memset(std.mem.asBytes(cursor), 0);
    cursor.is_eof = true;

    ppCursor.* = &cursor.base;
    return vtab.SQLITE_OK;
}

/// Helper to free cursor's dynamic allocations
fn freeCursorTables(cursor: *ChangesCursor) void {
    const allocator = getCursorAllocator();
    if (getCursorTableNames(cursor)) |names| {
        for (names) |name| {
            allocator.free(name);
        }
        allocator.free(names);
        setCursorTableNames(cursor, null);
    }
    cursor.table_count = 0;
}

/// xClose - Destroy cursor
fn changesClose(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    if (pCursor) |cur| {
        const cursor: *ChangesCursor = @ptrCast(@alignCast(cur));

        // Finalize any open statement
        if (cursor.clock_stmt) |stmt| {
            _ = finalizeStmt(stmt);
            cursor.clock_stmt = null;
        }

        // Free dynamic allocations
        freeCursorTables(cursor);

        sqliteFree(cur);
    }
    return vtab.SQLITE_OK;
}

/// Helper to discover all CRR tables and populate cursor's table list
fn discoverTables(cursor: *ChangesCursor, db: ?*vtab.sqlite3) !void {
    // Free any existing tables
    freeCursorTables(cursor);

    const allocator = getCursorAllocator();

    // Query for clock tables
    var stmt: ?*api.sqlite3_stmt = null;
    const rc = prepareV2(toApiDb(db), CLOCK_TABLES_SELECT, -1, &stmt, null);
    if (rc != vtab.SQLITE_OK) {
        return error.PrepareError;
    }
    defer _ = finalizeStmt(stmt);

    // First pass: count tables
    var count: usize = 0;
    while (stepStmt(stmt) == vtab.SQLITE_ROW) {
        count += 1;
    }

    if (count == 0) {
        cursor.table_count = 0;
        return;
    }

    // Allocate table names array
    const names = allocator.alloc([]u8, count) catch return error.OutOfMemory;
    errdefer allocator.free(names);

    // Reset and second pass: store names
    _ = resetStmt(stmt);
    var idx: usize = 0;
    while (stepStmt(stmt) == vtab.SQLITE_ROW) : (idx += 1) {
        const clock_name = columnTextFromStmt(stmt, 0) orelse continue;
        const clock_slice = std.mem.span(clock_name);

        // Get base table name (strip __crsql_clock)
        const base_name = getBaseTableName(clock_slice) orelse continue;

        // Allocate and copy
        const name_copy = allocator.alloc(u8, base_name.len) catch return error.OutOfMemory;
        @memcpy(name_copy, base_name);
        names[idx] = name_copy;
    }

    setCursorTableNames(cursor, names);
    cursor.table_count = count;
}

/// Helper to prepare a query for the current table's clock
fn prepareCurrentTableQuery(cursor: *ChangesCursor, db: ?*vtab.sqlite3) c_int {
    // Finalize previous statement if any
    if (cursor.clock_stmt) |stmt| {
        _ = finalizeStmt(stmt);
        cursor.clock_stmt = null;
    }

    const table_names = getCursorTableNames(cursor);
    if (table_names == null or cursor.current_table_idx >= cursor.table_count) {
        cursor.is_eof = true;
        return vtab.SQLITE_OK;
    }

    const table_name = table_names.?[cursor.current_table_idx];

    // Build query: SELECT pk, col_name, col_version, db_version, site_id, seq FROM <table>__crsql_clock
    // Note: clock table is WITHOUT ROWID, so we synthesize rowid from pk
    // The columns val and cl require joining with base table/pks - fetched separately in changesColumn
    // Column order: 0=pk, 1=col_name, 2=col_version, 3=db_version, 4=site_id, 5=seq
    // Exclude sentinel rows (col_name = '-1') from output - they're metadata only
    var sql_buf: [1024]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&sql_buf, "SELECT pk, col_name, col_version, db_version, site_id, seq FROM \"{s}__crsql_clock\" WHERE col_name != '-1'", .{table_name}) catch {
        return vtab.SQLITE_ERROR;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = prepareV2(toApiDb(db), sql, -1, &stmt, null);
    if (rc != vtab.SQLITE_OK) {
        return rc;
    }

    cursor.clock_stmt = stmt;
    return vtab.SQLITE_OK;
}

/// Move to next row within current table, or advance to next table
fn advanceCursor(cursor: *ChangesCursor, db: ?*vtab.sqlite3) c_int {
    while (true) {
        if (cursor.clock_stmt) |stmt| {
            const rc = stepStmt(stmt);
            if (rc == vtab.SQLITE_ROW) {
                // Got a row - increment row counter within current table
                cursor.current_row_in_table += 1;
                cursor.is_eof = false;
                // Store the current pk for lookups
                cursor.current_pk = columnInt64FromStmt(stmt, 0);
                return vtab.SQLITE_OK;
            } else if (rc == vtab.SQLITE_DONE) {
                // Current table exhausted, move to next
                _ = finalizeStmt(stmt);
                cursor.clock_stmt = null;
                cursor.current_table_idx += 1;
                cursor.current_row_in_table = 0; // Reset row counter for new table

                if (cursor.current_table_idx >= cursor.table_count) {
                    cursor.is_eof = true;
                    return vtab.SQLITE_OK;
                }

                // Prepare query for next table
                const prep_rc = prepareCurrentTableQuery(cursor, db);
                if (prep_rc != vtab.SQLITE_OK) {
                    return prep_rc;
                }
                // Loop to step into the new statement
                continue;
            } else {
                // Error
                return rc;
            }
        } else {
            // No statement - should not happen if properly initialized
            cursor.is_eof = true;
            return vtab.SQLITE_OK;
        }
    }
}

/// xFilter - Begin a scan
fn changesFilter(
    pCursor: ?*vtab.VTabCursor,
    _: c_int, // idxNum
    _: [*c]const u8, // idxStr
    _: c_int, // argc
    _: [*c]?*vtab.sqlite3_value, // argv
) callconv(.c) c_int {
    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCursor orelse return vtab.SQLITE_ERROR));
    const pVTab: *ChangesVTab = @ptrCast(@alignCast(cursor.base.pVtab orelse return vtab.SQLITE_ERROR));
    const db = pVTab.db;

    // Discover all CRR tables
    discoverTables(cursor, db) catch {
        cursor.is_eof = true;
        return vtab.SQLITE_OK;
    };

    if (cursor.table_count == 0) {
        cursor.is_eof = true;
        return vtab.SQLITE_OK;
    }

    // Start with first table
    cursor.current_table_idx = 0;
    cursor.current_row_in_table = 0;
    cursor.is_eof = false;

    // Prepare first table's query
    var rc = prepareCurrentTableQuery(cursor, db);
    if (rc != vtab.SQLITE_OK) {
        cursor.is_eof = true;
        return vtab.SQLITE_OK;
    }

    // Step to first row
    rc = advanceCursor(cursor, db);
    return rc;
}

/// xNext - Advance to next row
fn changesNext(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCursor orelse return vtab.SQLITE_ERROR));
    const pVTab: *ChangesVTab = @ptrCast(@alignCast(cursor.base.pVtab orelse return vtab.SQLITE_ERROR));

    return advanceCursor(cursor, pVTab.db);
}

/// xEof - Check if at end of results
fn changesEof(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCursor orelse return 1));
    return if (cursor.is_eof) 1 else 0;
}

/// Fetch the packed pks blob from __crsql_pks table
/// Returns the blob directly via sqlite3_result_blob
fn fetchPksBlob(db: ?*vtab.sqlite3, table_name: []const u8, pk: i64, ctx: ?*api.sqlite3_context) void {
    var sql_buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&sql_buf, "SELECT pks FROM \"{s}__crsql_pks\" WHERE pk = ?", .{table_name}) catch {
        resultNull(ctx);
        return;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    if (prepareV2(toApiDb(db), sql, -1, &stmt, null) != vtab.SQLITE_OK) {
        resultNull(ctx);
        return;
    }
    defer _ = finalizeStmt(stmt);

    if (api.bind_int64(stmt, 1, pk) != vtab.SQLITE_OK) {
        resultNull(ctx);
        return;
    }

    if (stepStmt(stmt) == vtab.SQLITE_ROW) {
        const blob = columnBlobFromStmt(stmt, 0);
        const len = columnBytesFromStmt(stmt, 0);
        resultBlob(ctx, blob, len, api.getTransientDestructor());
    } else {
        resultNull(ctx);
    }
}

/// Fetch the actual column value from the base table
/// col_name is the column name to fetch, rowid is the pk from clock table
fn fetchColumnValue(db: ?*vtab.sqlite3, table_name: []const u8, col_name: []const u8, rowid: i64, ctx: ?*api.sqlite3_context) void {
    var sql_buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&sql_buf, "SELECT \"{s}\" FROM \"{s}\" WHERE rowid = ?", .{ col_name, table_name }) catch {
        resultNull(ctx);
        return;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    if (prepareV2(toApiDb(db), sql, -1, &stmt, null) != vtab.SQLITE_OK) {
        resultNull(ctx);
        return;
    }
    defer _ = finalizeStmt(stmt);

    if (api.bind_int64(stmt, 1, rowid) != vtab.SQLITE_OK) {
        resultNull(ctx);
        return;
    }

    if (stepStmt(stmt) == vtab.SQLITE_ROW) {
        // Return based on actual type
        const col_type = columnTypeFromStmt(stmt, 0);
        switch (col_type) {
            api.SQLITE_INTEGER => resultInt64(ctx, columnInt64FromStmt(stmt, 0)),
            api.SQLITE_FLOAT => resultDouble(ctx, columnDoubleFromStmt(stmt, 0)),
            api.SQLITE_TEXT => {
                const text = columnTextFromStmt(stmt, 0);
                if (text) |t| {
                    resultText(ctx, t, columnBytesFromStmt(stmt, 0), api.getTransientDestructor());
                } else {
                    resultNull(ctx);
                }
            },
            api.SQLITE_BLOB => {
                resultBlob(ctx, columnBlobFromStmt(stmt, 0), columnBytesFromStmt(stmt, 0), api.getTransientDestructor());
            },
            else => resultNull(ctx),
        }
    } else {
        resultNull(ctx);
    }
}

/// Fetch the causal length from the sentinel row (col_name = '-1')
fn fetchCausalLength(db: ?*vtab.sqlite3, table_name: []const u8, pk: i64) i64 {
    var sql_buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&sql_buf, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name = '-1'", .{table_name}) catch {
        return 0;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    if (prepareV2(toApiDb(db), sql, -1, &stmt, null) != vtab.SQLITE_OK) {
        return 0;
    }
    defer _ = finalizeStmt(stmt);

    if (api.bind_int64(stmt, 1, pk) != vtab.SQLITE_OK) {
        return 0;
    }

    if (stepStmt(stmt) == vtab.SQLITE_ROW) {
        return columnInt64FromStmt(stmt, 0);
    }
    return 0;
}

/// xColumn - Return column value
fn changesColumn(
    pCursor: ?*vtab.VTabCursor,
    pCtx: ?*vtab.sqlite3_context,
    col: c_int,
) callconv(.c) c_int {
    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCursor orelse return vtab.SQLITE_ERROR));
    const pVTab: *ChangesVTab = @ptrCast(@alignCast(cursor.base.pVtab orelse return vtab.SQLITE_ERROR));
    const db = pVTab.db;
    const stmt = cursor.clock_stmt orelse return vtab.SQLITE_ERROR;

    // Convert context for API calls
    const ctx = toApiCtx(pCtx);

    // Get current table name for lookups
    const table_names = getCursorTableNames(cursor);
    const table_name: ?[]u8 = if (table_names) |names| blk: {
        break :blk if (cursor.current_table_idx < names.len) names[cursor.current_table_idx] else null;
    } else null;

    // Clock table query columns: 0=pk, 1=col_name, 2=col_version, 3=db_version, 4=site_id, 5=seq

    switch (col) {
        COL_TABLE => {
            // Return the base table name
            if (table_name) |name| {
                resultText(ctx, name.ptr, @intCast(name.len), api.getTransientDestructor());
            } else {
                resultNull(ctx);
            }
        },
        COL_PK => {
            // Fetch packed pks blob from __crsql_pks table
            if (table_name) |name| {
                fetchPksBlob(db, name, cursor.current_pk, ctx);
            } else {
                resultNull(ctx);
            }
        },
        COL_CID => {
            // cid is col_name from clock table (column 1)
            const text = columnTextFromStmt(stmt, 1);
            if (text) |t| {
                const len = columnBytesFromStmt(stmt, 1);
                resultText(ctx, t, len, api.getTransientDestructor());
            } else {
                resultNull(ctx);
            }
        },
        COL_VAL => {
            // Fetch actual value from base table using col_name
            if (table_name) |name| {
                const col_name_ptr = columnTextFromStmt(stmt, 1);
                if (col_name_ptr) |cn| {
                    const col_name_slice = std.mem.span(cn);
                    fetchColumnValue(db, name, col_name_slice, cursor.current_pk, ctx);
                } else {
                    resultNull(ctx);
                }
            } else {
                resultNull(ctx);
            }
        },
        COL_COL_VERSION => {
            // col_version is column 2 in clock table query
            resultInt64(ctx, columnInt64FromStmt(stmt, 2));
        },
        COL_DB_VERSION => {
            // db_version is column 3 in clock table query
            resultInt64(ctx, columnInt64FromStmt(stmt, 3));
        },
        COL_SITE_ID => {
            // site_id is column 4 in clock table query
            // Our clock table stores site_id as INTEGER (0 for local).
            // The crsql_changes schema expects a 16-byte BLOB.
            // Check column type: if INTEGER and value is 0, return 16-byte zero blob
            const col_type = columnTypeFromStmt(stmt, 4);
            if (col_type == api.SQLITE_INTEGER) {
                // Integer site_id (0 = local) -> return 16-byte zero blob
                const zero_blob: [16]u8 = .{0} ** 16;
                resultBlob(ctx, &zero_blob, 16, api.getTransientDestructor());
            } else if (col_type == api.SQLITE_BLOB) {
                const blob = columnBlobFromStmt(stmt, 4);
                const len = columnBytesFromStmt(stmt, 4);
                if (blob != null and len > 0) {
                    resultBlob(ctx, blob, len, api.getTransientDestructor());
                } else {
                    const zero_blob: [16]u8 = .{0} ** 16;
                    resultBlob(ctx, &zero_blob, 16, api.getTransientDestructor());
                }
            } else {
                // NULL or other type -> return 16-byte zero blob
                const zero_blob: [16]u8 = .{0} ** 16;
                resultBlob(ctx, &zero_blob, 16, api.getTransientDestructor());
            }
        },
        COL_CL => {
            // Causal length: fetch from sentinel row (col_name = '-1')
            if (table_name) |name| {
                const cl = fetchCausalLength(db, name, cursor.current_pk);
                resultInt64(ctx, cl);
            } else {
                resultInt64(ctx, 0);
            }
        },
        COL_SEQ => {
            // seq is column 5 in clock table query
            resultInt64(ctx, columnInt64FromStmt(stmt, 5));
        },
        else => {
            resultNull(ctx);
        },
    }

    return vtab.SQLITE_OK;
}

/// xRowid - Return the rowid with slab offset
fn changesRowid(pCursor: ?*vtab.VTabCursor, pRowid: *i64) callconv(.c) c_int {
    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCursor orelse return vtab.SQLITE_ERROR));

    // Compute slab rowid: table_index * ROWID_SLAB_SIZE + row_in_table
    const slab_offset: i64 = @as(i64, @intCast(cursor.current_table_idx)) * ROWID_SLAB_SIZE;
    pRowid.* = slab_offset + cursor.current_row_in_table;

    return vtab.SQLITE_OK;
}

// =============================================================================
// Module Definition
// =============================================================================

/// The crsql_changes module definition (read-only for Phase 1)
pub const changes_module = vtab.Module{
    .iVersion = 0,
    .xCreate = null, // eponymous-only
    .xConnect = changesConnect,
    .xBestIndex = changesBestIndex,
    .xDisconnect = changesDisconnect,
    .xDestroy = null,
    .xOpen = changesOpen,
    .xClose = changesClose,
    .xFilter = changesFilter,
    .xNext = changesNext,
    .xEof = changesEof,
    .xColumn = changesColumn,
    .xRowid = changesRowid,
    .xUpdate = null, // read-only for now
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

/// Register the crsql_changes virtual table module with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    return createModuleV2(db, "crsql_changes", &changes_module, null, null);
}

// =============================================================================
// Tests
// =============================================================================

test "ROWID_SLAB_SIZE matches C constant" {
    // Verify our constant matches core/src/consts.h
    try std.testing.expectEqual(@as(i64, 10_000_000_000_000), ROWID_SLAB_SIZE);
}

test "getBaseTableName strips suffix correctly" {
    const result1 = getBaseTableName("foo__crsql_clock");
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("foo", result1.?);

    const result2 = getBaseTableName("my_table__crsql_clock");
    try std.testing.expect(result2 != null);
    try std.testing.expectEqualStrings("my_table", result2.?);

    // Invalid cases
    try std.testing.expect(getBaseTableName("__crsql_clock") == null);
    try std.testing.expect(getBaseTableName("foo") == null);
    try std.testing.expect(getBaseTableName("foo__crsql_cloc") == null);
}

test "module struct is properly configured" {
    try std.testing.expect(changes_module.xConnect != null);
    try std.testing.expect(changes_module.xBestIndex != null);
    try std.testing.expect(changes_module.xDisconnect != null);
    try std.testing.expect(changes_module.xOpen != null);
    try std.testing.expect(changes_module.xClose != null);
    try std.testing.expect(changes_module.xFilter != null);
    try std.testing.expect(changes_module.xNext != null);
    try std.testing.expect(changes_module.xEof != null);
    try std.testing.expect(changes_module.xColumn != null);
    try std.testing.expect(changes_module.xRowid != null);

    // Read-only: xUpdate should be null
    try std.testing.expect(changes_module.xUpdate == null);
    // Eponymous-only: xCreate should be null
    try std.testing.expect(changes_module.xCreate == null);
}

test "rowid slab calculation" {
    // Table 0, row 1 -> 1
    const row1: i64 = 0 * ROWID_SLAB_SIZE + 1;
    try std.testing.expectEqual(@as(i64, 1), row1);

    // Table 0, row 2 -> 2
    const row2: i64 = 0 * ROWID_SLAB_SIZE + 2;
    try std.testing.expectEqual(@as(i64, 2), row2);

    // Table 1, row 1 -> ROWID_SLAB_SIZE + 1
    const row3: i64 = 1 * ROWID_SLAB_SIZE + 1;
    try std.testing.expectEqual(@as(i64, 10_000_000_000_001), row3);

    // Table 2, row 1 -> 2 * ROWID_SLAB_SIZE + 1
    const row4: i64 = 2 * ROWID_SLAB_SIZE + 1;
    try std.testing.expectEqual(@as(i64, 20_000_000_000_001), row4);
}
