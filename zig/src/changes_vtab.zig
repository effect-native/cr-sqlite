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
const builtin = @import("builtin");
const vtab = @import("sqlite/vtab.zig");
const api = @import("ffi/api.zig");
const rows_impacted = @import("rows_impacted.zig");
const merge_insert = @import("merge_insert.zig");
const compare_values = @import("compare_values.zig");
const sync_bit = @import("sync_bit.zig");
const site_identity = @import("site_identity.zig");
const stmt_cache = @import("stmt_cache.zig");

// Platform-aware logging: use std.log on native, no-op on WASM/freestanding
const log = if (builtin.os.tag == .freestanding or builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64)
    struct {
        // No-op logger for WASM/freestanding
        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            _ = fmt;
            _ = args;
        }
    }
else
    std.log.scoped(.changes_vtab);

// Type conversion between vtab's opaque types and api's opaque types.
// Both represent the same underlying SQLite types, just declared separately.
fn toApiDb(db: ?*vtab.sqlite3) ?*api.sqlite3 {
    return @ptrCast(db);
}

fn toApiCtx(ctx: ?*vtab.sqlite3_context) ?*api.sqlite3_context {
    return @ptrCast(ctx);
}

fn toApiValue(val: ?*vtab.sqlite3_value) ?*api.sqlite3_value {
    return @ptrCast(val);
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

// Index plan encoding for xBestIndex/xFilter:
// idxNum bits encode which filters are active and their types.
// Bit layout:
//   bits 0-2: db_version filter type (0=none, 1=GT, 2=GE, 3=LT, 4=LE)
//   bits 3-5: site_id filter type (0=none, 1=ISNOT, 2=IS, 3=EQ, 4=NE)
const IDX_DB_VERSION_MASK: c_int = 0x07; // bits 0-2
const IDX_SITE_ID_MASK: c_int = 0x38; // bits 3-5
const IDX_SITE_ID_SHIFT: u5 = 3;

// db_version filter types (stored in bits 0-2)
const IDX_DB_VERSION_NONE: c_int = 0;
const IDX_DB_VERSION_GT: c_int = 1;
const IDX_DB_VERSION_GE: c_int = 2;
const IDX_DB_VERSION_LT: c_int = 3;
const IDX_DB_VERSION_LE: c_int = 4;

// site_id filter types (stored in bits 3-5, shifted)
const IDX_SITE_ID_NONE: c_int = 0;
const IDX_SITE_ID_ISNOT: c_int = 1;
const IDX_SITE_ID_IS: c_int = 2;
const IDX_SITE_ID_EQ: c_int = 3;
const IDX_SITE_ID_NE: c_int = 4;

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
    // Statement cache for improved performance (nullable, graceful fallback if init fails)
    cache: ?*stmt_cache.StmtCache,
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

    // Filter state for xBestIndex/xFilter optimization
    filter_db_version: i64, // db_version filter value
    filter_db_version_type: c_int, // IDX_DB_VERSION_GT, IDX_DB_VERSION_GE, etc.
    filter_site_id_blob: ?[*]const u8,
    filter_site_id_len: usize,
    filter_site_id_type: c_int, // IDX_SITE_ID_ISNOT, IDX_SITE_ID_IS, etc.
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

    // Initialize statement cache for performance (graceful fallback if init fails)
    pVTab.cache = stmt_cache.StmtCache.init(toApiDb(db)) catch null;

    ppVTab.* = &pVTab.base;
    return vtab.SQLITE_OK;
}

/// xDisconnect - Release the virtual table connection
fn changesDisconnect(pVTab: ?*vtab.VTab) callconv(.c) c_int {
    if (pVTab) |vt| {
        const pChangesVTab: *ChangesVTab = @ptrCast(@alignCast(vt));
        // Free statement cache if it was allocated
        if (pChangesVTab.cache) |cache| {
            cache.deinit();
        }
        sqliteFree(vt);
    }
    return vtab.SQLITE_OK;
}

/// xBestIndex - Query planning
/// Recognizes db_version (>, >=, <, <=) and site_id (IS, IS NOT, =, !=) constraints
fn changesBestIndex(pVTab: ?*vtab.VTab, pIdxInfo: ?*vtab.IndexInfo) callconv(.c) c_int {
    _ = pVTab;
    if (pIdxInfo == null) return vtab.SQLITE_ERROR;

    const info = pIdxInfo.?;
    var idxNum: c_int = 0;
    var argvIndex: c_int = 1;
    var cost: f64 = 1_000_000.0;

    // Track whether we've already claimed a constraint for each column
    var have_db_version_filter = false;
    var have_site_id_filter = false;

    // Check constraints
    const nConstraint = info.nConstraint;
    if (nConstraint > 0 and info.aConstraint != null) {
        const constraints = info.aConstraint[0..@intCast(nConstraint)];
        const usages = info.aConstraintUsage[0..@intCast(nConstraint)];

        for (constraints, usages) |con, *usage| {
            if (con.usable == 0) continue;

            // COL_DB_VERSION (5) - handle GT, GE, LT, LE
            if (con.iColumn == COL_DB_VERSION and !have_db_version_filter) {
                var filter_type: c_int = IDX_DB_VERSION_NONE;
                if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_GT) {
                    filter_type = IDX_DB_VERSION_GT;
                } else if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_GE) {
                    filter_type = IDX_DB_VERSION_GE;
                } else if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_LT) {
                    filter_type = IDX_DB_VERSION_LT;
                } else if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_LE) {
                    filter_type = IDX_DB_VERSION_LE;
                }

                if (filter_type != IDX_DB_VERSION_NONE) {
                    idxNum = (idxNum & ~IDX_DB_VERSION_MASK) | filter_type;
                    usage.argvIndex = argvIndex;
                    usage.omit = 1;
                    argvIndex += 1;
                    cost /= 10.0;
                    have_db_version_filter = true;
                }
            }
            // COL_SITE_ID (6) - handle ISNOT, IS, EQ, NE
            else if (con.iColumn == COL_SITE_ID and !have_site_id_filter) {
                var filter_type: c_int = IDX_SITE_ID_NONE;
                if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_ISNOT) {
                    filter_type = IDX_SITE_ID_ISNOT;
                } else if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_IS) {
                    filter_type = IDX_SITE_ID_IS;
                } else if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_EQ) {
                    filter_type = IDX_SITE_ID_EQ;
                } else if (con.op == vtab.SQLITE_INDEX_CONSTRAINT_NE) {
                    filter_type = IDX_SITE_ID_NE;
                }

                if (filter_type != IDX_SITE_ID_NONE) {
                    idxNum = (idxNum & ~IDX_SITE_ID_MASK) | (filter_type << IDX_SITE_ID_SHIFT);
                    usage.argvIndex = argvIndex;
                    usage.omit = 1;
                    argvIndex += 1;
                    cost /= 2.0;
                    have_site_id_filter = true;
                }
            }
        }
    }

    info.idxNum = idxNum;
    info.estimatedCost = cost;
    info.estimatedRows = if (idxNum != 0) 1000 else 10000;

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

/// Cached version of discoverTables using StmtCache for better performance.
///
/// Uses the `select_clock_tables` slot in the cache to avoid re-preparing
/// the sqlite_master query on every xFilter call. This is particularly
/// beneficial for sync operations that repeatedly query crsql_changes.
fn discoverTablesCached(cursor: *ChangesCursor, cache: *stmt_cache.StmtCache) !void {
    // Free any existing tables
    freeCursorTables(cursor);

    const allocator = getCursorAllocator();

    // Query for clock tables using cached statement
    // Note: CLOCK_TABLES_SELECT uses tbl_name, but cache uses 'name' - use a compatible query
    const stmt = try stmt_cache.prepareOnce(
        cache.db,
        "SELECT tbl_name FROM sqlite_master WHERE type='table' AND tbl_name LIKE '%__crsql_clock' ORDER BY tbl_name",
        &cache.select_clock_tables,
    );

    // First pass: count tables
    var count: usize = 0;
    while (api.step(stmt) == api.SQLITE_ROW) {
        count += 1;
    }

    if (count == 0) {
        stmt_cache.resetStmt(stmt);
        cursor.table_count = 0;
        return;
    }

    // Allocate table names array
    const names = allocator.alloc([]u8, count) catch {
        stmt_cache.resetStmt(stmt);
        return error.OutOfMemory;
    };
    errdefer allocator.free(names);

    // Reset and second pass: store names
    stmt_cache.resetStmt(stmt);
    var idx: usize = 0;
    while (api.step(stmt) == api.SQLITE_ROW) : (idx += 1) {
        const clock_name = api.column_text(stmt, 0) orelse continue;
        const clock_slice = std.mem.span(clock_name);

        // Get base table name (strip __crsql_clock)
        const base_name = getBaseTableName(clock_slice) orelse continue;

        // Allocate and copy
        const name_copy = allocator.alloc(u8, base_name.len) catch {
            stmt_cache.resetStmt(stmt);
            return error.OutOfMemory;
        };
        @memcpy(name_copy, base_name);
        names[idx] = name_copy;
    }

    stmt_cache.resetStmt(stmt);
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

    // Build query with optional db_version filter
    // Note: We only push down the db_version filter to SQL query.
    // Site_id filter is applied in shouldSkipSiteId since it requires ordinal lookup.
    const sql = switch (cursor.filter_db_version_type) {
        IDX_DB_VERSION_GT => std.fmt.bufPrintZ(&sql_buf, "SELECT pk, col_name, col_version, db_version, site_id, seq FROM \"{s}__crsql_clock\" WHERE db_version > ?", .{table_name}) catch {
            return vtab.SQLITE_ERROR;
        },
        IDX_DB_VERSION_GE => std.fmt.bufPrintZ(&sql_buf, "SELECT pk, col_name, col_version, db_version, site_id, seq FROM \"{s}__crsql_clock\" WHERE db_version >= ?", .{table_name}) catch {
            return vtab.SQLITE_ERROR;
        },
        IDX_DB_VERSION_LT => std.fmt.bufPrintZ(&sql_buf, "SELECT pk, col_name, col_version, db_version, site_id, seq FROM \"{s}__crsql_clock\" WHERE db_version < ?", .{table_name}) catch {
            return vtab.SQLITE_ERROR;
        },
        IDX_DB_VERSION_LE => std.fmt.bufPrintZ(&sql_buf, "SELECT pk, col_name, col_version, db_version, site_id, seq FROM \"{s}__crsql_clock\" WHERE db_version <= ?", .{table_name}) catch {
            return vtab.SQLITE_ERROR;
        },
        else => std.fmt.bufPrintZ(&sql_buf, "SELECT pk, col_name, col_version, db_version, site_id, seq FROM \"{s}__crsql_clock\"", .{table_name}) catch {
            return vtab.SQLITE_ERROR;
        },
    };

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = prepareV2(toApiDb(db), sql, -1, &stmt, null);
    if (rc != vtab.SQLITE_OK) {
        return rc;
    }

    // Bind db_version filter if present
    if (cursor.filter_db_version_type != IDX_DB_VERSION_NONE) {
        if (api.bind_int64(stmt, 1, cursor.filter_db_version) != vtab.SQLITE_OK) {
            _ = finalizeStmt(stmt);
            return vtab.SQLITE_ERROR;
        }
    }

    cursor.clock_stmt = stmt;
    return vtab.SQLITE_OK;
}

/// Check if the current row is a sentinel row (col_name = '-1')
/// Sentinel rows are metadata-only and should be excluded from crsql_changes output
fn isSentinelRow(stmt: ?*api.sqlite3_stmt) bool {
    const col_name_ptr = columnTextFromStmt(stmt, 1);
    if (col_name_ptr) |cn| {
        const col_name_slice = std.mem.span(cn);
        return std.mem.eql(u8, col_name_slice, "-1");
    }
    return false;
}

/// Check if the current row should be skipped based on site_id filter
/// Returns true if the row should be skipped based on the filter type:
/// - ISNOT: skip if site_id matches filter (exclude matching)
/// - IS/EQ: skip if site_id does NOT match filter (include only matching)
/// - NE: skip if site_id matches filter (exclude matching)
fn shouldSkipSiteId(cursor: *ChangesCursor, db: ?*vtab.sqlite3, stmt: ?*api.sqlite3_stmt) bool {
    if (cursor.filter_site_id_type == IDX_SITE_ID_NONE or cursor.filter_site_id_blob == null) {
        return false;
    }

    // Get site_id from clock table (column 4)
    // Clock table stores site_id as INTEGER ordinal (0 for local) or BLOB for remote
    const col_type = columnTypeFromStmt(stmt, 4);

    // Get the actual 16-byte site_id for this row
    var row_site_id: [16]u8 = .{0} ** 16;
    var have_row_site_id = false;

    if (col_type == api.SQLITE_INTEGER) {
        // Integer ordinal - look up actual site_id
        const ordinal = columnInt64FromStmt(stmt, 4);
        if (site_identity.getSiteIdByOrdinal(toApiDb(db), ordinal)) |site_blob| {
            row_site_id = site_blob;
            have_row_site_id = true;
        }
    } else if (col_type == api.SQLITE_BLOB) {
        // Direct blob
        const row_blob = columnBlobFromStmt(stmt, 4);
        const row_len = columnBytesFromStmt(stmt, 4);
        if (row_blob != null and row_len == 16) {
            const row_ptr: [*]const u8 = @ptrCast(row_blob);
            @memcpy(&row_site_id, row_ptr[0..16]);
            have_row_site_id = true;
        }
    }

    if (!have_row_site_id) {
        // Can't determine row's site_id - don't skip by default
        return false;
    }

    // Compare with filter
    const filter_blob = cursor.filter_site_id_blob.?;
    const filter_len = cursor.filter_site_id_len;

    // Check if they match (filter must be 16 bytes for proper comparison)
    const matches = (filter_len == 16) and std.mem.eql(u8, &row_site_id, filter_blob[0..16]);

    // Apply filter logic based on type
    switch (cursor.filter_site_id_type) {
        IDX_SITE_ID_ISNOT, IDX_SITE_ID_NE => {
            // ISNOT/NE: skip if matches (we want rows that DON'T match)
            return matches;
        },
        IDX_SITE_ID_IS, IDX_SITE_ID_EQ => {
            // IS/EQ: skip if NOT matches (we want rows that DO match)
            return !matches;
        },
        else => return false,
    }
}

/// Move to next row within current table, or advance to next table
fn advanceCursor(cursor: *ChangesCursor, db: ?*vtab.sqlite3) c_int {
    while (true) {
        if (cursor.clock_stmt) |stmt| {
            const rc = stepStmt(stmt);
            if (rc == vtab.SQLITE_ROW) {
                // Skip sentinel rows (col_name = '-1') - they're metadata only
                if (isSentinelRow(stmt)) {
                    continue;
                }

                // Check site_id filter - skip rows based on filter type
                if (shouldSkipSiteId(cursor, db, stmt)) {
                    // Skip this row, continue to next
                    continue;
                }

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
    idxNum: c_int, // idxNum from xBestIndex
    _: [*c]const u8, // idxStr
    argc: c_int, // number of constraint values
    argv: [*c]?*vtab.sqlite3_value, // constraint values
) callconv(.c) c_int {
    const cursor: *ChangesCursor = @ptrCast(@alignCast(pCursor orelse return vtab.SQLITE_ERROR));
    const pVTab: *ChangesVTab = @ptrCast(@alignCast(cursor.base.pVtab orelse return vtab.SQLITE_ERROR));
    const db = pVTab.db;

    // Reset filter state
    cursor.filter_db_version = 0;
    cursor.filter_db_version_type = IDX_DB_VERSION_NONE;
    cursor.filter_site_id_blob = null;
    cursor.filter_site_id_len = 0;
    cursor.filter_site_id_type = IDX_SITE_ID_NONE;

    // Extract constraint values from argv based on idxNum
    var argIdx: usize = 0;
    const db_version_filter_type = idxNum & IDX_DB_VERSION_MASK;
    if (db_version_filter_type != IDX_DB_VERSION_NONE and argc > @as(c_int, @intCast(argIdx))) {
        cursor.filter_db_version = api.value_int64(toApiValue(argv[argIdx]));
        cursor.filter_db_version_type = db_version_filter_type;
        argIdx += 1;
    }
    const site_id_filter_type = (idxNum & IDX_SITE_ID_MASK) >> IDX_SITE_ID_SHIFT;
    if (site_id_filter_type != IDX_SITE_ID_NONE and argc > @as(c_int, @intCast(argIdx))) {
        cursor.filter_site_id_blob = @ptrCast(api.value_blob(toApiValue(argv[argIdx])));
        cursor.filter_site_id_len = @intCast(api.value_bytes(toApiValue(argv[argIdx])));
        cursor.filter_site_id_type = site_id_filter_type;
    }

    // Discover all CRR tables (use cached version if available for better performance)
    if (pVTab.cache) |cache| {
        discoverTablesCached(cursor, cache) catch {
            cursor.is_eof = true;
            return vtab.SQLITE_OK;
        };
    } else {
        // Fallback to uncached version if cache initialization failed
        discoverTables(cursor, db) catch {
            cursor.is_eof = true;
            return vtab.SQLITE_OK;
        };
    }

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
            // Check if this is a sentinel row (col_name = '-1')
            const col_name_ptr = columnTextFromStmt(stmt, 1);
            if (col_name_ptr) |cn| {
                const col_name_slice = std.mem.span(cn);
                if (std.mem.eql(u8, col_name_slice, "-1")) {
                    // Sentinel rows have NULL value
                    resultNull(ctx);
                } else if (table_name) |name| {
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
            // Our clock table stores site_id as INTEGER ordinal (0 for local).
            // The crsql_changes schema expects a 16-byte BLOB.
            // We need to look up the actual site_id from the ordinal.
            const col_type = columnTypeFromStmt(stmt, 4);
            if (col_type == api.SQLITE_INTEGER) {
                // Integer site_id ordinal - look up actual site_id blob
                const ordinal = columnInt64FromStmt(stmt, 4);
                if (site_identity.getSiteIdByOrdinal(toApiDb(db), ordinal)) |site_blob| {
                    resultBlob(ctx, &site_blob, 16, api.getTransientDestructor());
                } else {
                    // Fallback to zeros if lookup fails
                    const zero_blob: [16]u8 = .{0} ** 16;
                    resultBlob(ctx, &zero_blob, 16, api.getTransientDestructor());
                }
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
            // If this IS the sentinel row, col_version is the causal length
            const col_name_ptr = columnTextFromStmt(stmt, 1);
            if (col_name_ptr) |cn| {
                const col_name_slice = std.mem.span(cn);
                if (std.mem.eql(u8, col_name_slice, "-1")) {
                    // We ARE the sentinel - col_version IS cl
                    resultInt64(ctx, columnInt64FromStmt(stmt, 2));
                } else if (table_name) |name| {
                    // Regular column - fetch from sentinel
                    const cl = fetchCausalLength(db, name, cursor.current_pk);
                    resultInt64(ctx, cl);
                } else {
                    resultInt64(ctx, 0);
                }
            } else if (table_name) |name| {
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
// xUpdate - INSERT/UPDATE/DELETE handler
// =============================================================================

/// xUpdate callback for INSERT operations on crsql_changes
///
/// INSERT format (9 columns):
///   argv[2] = table (TEXT)
///   argv[3] = pk (BLOB) - packed primary key
///   argv[4] = cid (TEXT) - column name or '-1' for delete sentinel
///   argv[5] = val (ANY) - new value
///   argv[6] = col_version (INT)
///   argv[7] = db_version (INT)
///   argv[8] = site_id (BLOB) - source site, NULL for local
///   argv[9] = cl (INT) - causal length
///   argv[10] = seq (INT) - sequence number
///
/// Operation detection:
/// - argc == 1: DELETE (not supported)
/// - argc > 1, argv[0] is NULL: INSERT
/// - argc > 1, argv[0] is not NULL: UPDATE (not supported)
fn changesUpdate(
    pVTab: ?*vtab.VTab,
    argc: c_int,
    argv: [*c]?*vtab.sqlite3_value,
    pRowid: *i64,
) callconv(.c) c_int {
    // Need at least argv[0] and argv[1] for INSERT detection
    if (argc < 2) {
        log.debug("changesUpdate: argc < 2, returning error", .{});
        return vtab.SQLITE_ERROR;
    }

    // Check operation type: INSERT has argv[0] == NULL
    const first_arg_type = api.value_type(toApiValue(argv[0]));
    if (first_arg_type != api.SQLITE_NULL) {
        // DELETE (argc==1) or UPDATE (argv[0] not null) - not supported yet
        log.debug("changesUpdate: DELETE/UPDATE not supported", .{});
        return vtab.SQLITE_READONLY;
    }

    // This is an INSERT operation
    // For crsql_changes, we expect 9 columns + 2 = 11 args
    // argv[0] = old rowid (NULL for INSERT)
    // argv[1] = new rowid (may be NULL for auto-generate)
    // argv[2..10] = column values (9 columns)
    if (argc < 11) {
        log.debug("changesUpdate: INSERT with argc={}, expected 11", .{argc});
        return vtab.SQLITE_ERROR;
    }

    const pChangesVTab: *ChangesVTab = @ptrCast(@alignCast(pVTab orelse return vtab.SQLITE_ERROR));
    const vtab_db = pChangesVTab.db orelse return vtab.SQLITE_ERROR;

    // Extract INSERT values
    // Column 0: table name (TEXT)
    const table_name = api.value_text(toApiValue(argv[2]));
    if (table_name == null) {
        log.debug("changesUpdate: table name is NULL", .{});
        return vtab.SQLITE_ERROR;
    }

    // Column 1: pk (BLOB) - packed primary key
    const pk_blob = api.value_blob(toApiValue(argv[3]));
    const pk_len = api.value_bytes(toApiValue(argv[3]));

    // Column 2: cid (TEXT) - column name
    const cid = api.value_text(toApiValue(argv[4]));
    if (cid == null) {
        log.debug("changesUpdate: cid is NULL", .{});
        return vtab.SQLITE_ERROR;
    }

    // Column 3: val (ANY) - handled below during actual merge
    // Column 4: col_version (INT)
    const col_version = api.value_int64(toApiValue(argv[6]));

    // Column 5: db_version (INT)
    const db_version = api.value_int64(toApiValue(argv[7]));

    // Column 6: site_id (BLOB) - may be NULL for local changes
    const site_id_blob = api.value_blob(toApiValue(argv[8]));
    const site_id_len = api.value_bytes(toApiValue(argv[8]));

    // Column 7: cl (INT) - causal length
    const cl = api.value_int64(toApiValue(argv[9]));

    // Column 8: seq (INT) - sequence number
    const seq = api.value_int64(toApiValue(argv[10]));

    log.debug("changesUpdate INSERT: table={s}, cid={s}, col_ver={}, db_ver={}, cl={}, seq={}", .{
        table_name.?,
        cid.?,
        col_version,
        db_version,
        cl,
        seq,
    });

    // Validate pk blob exists
    if (pk_blob == null and pk_len > 0) {
        log.debug("changesUpdate: pk blob is NULL but length > 0", .{});
        return vtab.SQLITE_ERROR;
    }

    // Set sync_bit to 1 to gate off triggers during merge operations.
    // This prevents infinite loops where merge writes would trigger clock updates.
    // The guard ensures sync_bit is reset to 0 even if we return early due to errors.
    const guard = sync_bit.SyncBitGuard.init();
    defer guard.deinit();

    // Get table name as slice for helper functions
    const table_slice = std.mem.span(table_name.?);
    const cid_slice = std.mem.span(cid.?);

    // Step 1: Find the pk (rowid) from the packed blob
    const pk_ptr: [*]const u8 = @ptrCast(pk_blob orelse {
        log.debug("changesUpdate: pk_blob is NULL", .{});
        return vtab.SQLITE_ERROR;
    });
    const api_db = toApiDb(vtab_db);
    const pk_rowid = merge_insert.findPkFromBlob(api_db, table_slice, pk_ptr, @intCast(pk_len)) catch |err| {
        // If row doesn't exist locally, we need to INSERT it
        if (err == merge_insert.MergeError.NoRows) {
            // Handle sentinel operations (cid = "-1") for non-existent rows
            const is_sentinel_for_new = std.mem.eql(u8, cid_slice, "-1");
            if (is_sentinel_for_new) {
                // Sentinel for non-existent row - this is a tombstone/delete marker
                // We need to create just the clock entry without a base table row
                // For now, skip - the row doesn't exist and we're being told to delete it
                log.debug("changesUpdate: sentinel for non-existent row, skipping", .{});
                pRowid.* = 0;
                return vtab.SQLITE_OK;
            }

            // No local row - INSERT new row
            log.debug("changesUpdate: no local row, inserting new row", .{});

            // Get the value from argv[5] (column 3: val)
            const insert_value = toApiValue(argv[5]);

            // Step 1a: Insert into base table
            const new_pk = merge_insert.insertIntoBaseTable(api_db, table_slice, cid_slice, insert_value, pk_ptr, @intCast(pk_len)) catch {
                log.debug("changesUpdate: insertIntoBaseTable failed", .{});
                return vtab.SQLITE_ERROR;
            };

            // Step 1b: Insert into __crsql_pks table
            merge_insert.insertIntoPksTable(api_db, table_slice, new_pk, pk_ptr, @intCast(pk_len)) catch {
                log.debug("changesUpdate: insertIntoPksTable failed", .{});
                return vtab.SQLITE_ERROR;
            };

            // Step 1c: Insert clock entry for the column
            const site_id_ptr_insert: ?[*]const u8 = @ptrCast(site_id_blob);
            merge_insert.setWinnerClock(api_db, table_slice, new_pk, cid_slice, col_version, db_version, site_id_ptr_insert, @intCast(site_id_len), seq) catch {
                log.debug("changesUpdate: setWinnerClock for new row failed", .{});
                return vtab.SQLITE_ERROR;
            };

            // Step 1d: Insert sentinel clock entry with the incoming cl
            merge_insert.setWinnerClock(api_db, table_slice, new_pk, "-1", cl, db_version, site_id_ptr_insert, @intCast(site_id_len), seq) catch {
                log.debug("changesUpdate: setWinnerClock for sentinel failed", .{});
                return vtab.SQLITE_ERROR;
            };

            // Increment rows impacted
            rows_impacted.incrementRowsImpacted();

            pRowid.* = 0;
            return vtab.SQLITE_OK;
        }
        log.debug("changesUpdate: findPkFromBlob failed", .{});
        return vtab.SQLITE_ERROR;
    };

    // Step 2: Get local causal length
    const local_cl = merge_insert.getLocalCl(api_db, table_slice, pk_rowid) catch {
        log.debug("changesUpdate: getLocalCl failed", .{});
        return vtab.SQLITE_ERROR;
    };

    // Step 3: CL gating - if remote CL is less than local, reject immediately
    if (cl < local_cl) {
        log.debug("changesUpdate: remote cl {} < local cl {}, no-op", .{ cl, local_cl });
        pRowid.* = 0;
        return vtab.SQLITE_OK; // No-op, local wins
    }

    // Step 4: Handle sentinel-only operations (cid = "-1")
    const is_sentinel = std.mem.eql(u8, cid_slice, "-1");
    if (is_sentinel) {
        // Sentinel operations: CL parity determines state
        // - Even CL = deleted (tombstone)
        // - Odd CL = live (resurrection marker)
        if (cl > local_cl) {
            const is_delete = (@mod(cl, 2) == 0); // Even CL = deleted state

            if (is_delete) {
                // Delete from base table first
                merge_insert.deleteFromBaseTable(api_db, table_slice, pk_rowid) catch {
                    log.debug("changesUpdate: deleteFromBaseTable failed", .{});
                    return vtab.SQLITE_ERROR;
                };

                // Drop all non-sentinel clock entries
                merge_insert.dropNonSentinelClocks(api_db, table_slice, pk_rowid) catch {
                    log.debug("changesUpdate: dropNonSentinelClocks failed", .{});
                    return vtab.SQLITE_ERROR;
                };
            }
            // For resurrection (odd CL), we don't delete - just update the sentinel clock.
            // The actual row data will come from separate column change entries.

            // Update the sentinel clock
            merge_insert.setWinnerClock(api_db, table_slice, pk_rowid, cid_slice, col_version, db_version, @ptrCast(site_id_blob), @intCast(site_id_len), seq) catch {
                log.debug("changesUpdate: setWinnerClock for sentinel failed", .{});
                return vtab.SQLITE_ERROR;
            };
            rows_impacted.incrementRowsImpacted();
        }
        pRowid.* = 0;
        return vtab.SQLITE_OK;
    }

    // Step 4b: Check if row needs resurrection
    // A row needs resurrection if:
    //   - The incoming cl indicates live (odd) OR cl > local_cl
    //   - BUT the row doesn't actually exist in the base table
    // This handles both:
    //   - Out-of-order delivery: sentinel arrives first, updates cl to 3 (live), then column data arrives
    //   - In-order delivery: column data arrives when local_cl is still even (deleted)
    const row_exists = merge_insert.rowExistsInBaseTable(api_db, table_slice, pk_rowid) catch false;
    const incoming_is_live = @mod(cl, 2) == 1; // odd cl = live state

    if (!row_exists and incoming_is_live) {
        // Resurrection case: row doesn't exist but should be live
        log.debug("changesUpdate: resurrection needed - row doesn't exist, incoming cl={} (live)", .{cl});

        // Get the value from argv[5]
        const resurrect_value = toApiValue(argv[5]);

        // Re-insert into base table using the existing pk (the pks entry still exists)
        merge_insert.insertRowForResurrection(api_db, table_slice, pk_rowid, cid_slice, resurrect_value) catch {
            log.debug("changesUpdate: insertRowForResurrection failed", .{});
            return vtab.SQLITE_ERROR;
        };

        // Update clock entry for the column
        const site_id_ptr_res: ?[*]const u8 = @ptrCast(site_id_blob);
        merge_insert.setWinnerClock(api_db, table_slice, pk_rowid, cid_slice, col_version, db_version, site_id_ptr_res, @intCast(site_id_len), seq) catch {
            log.debug("changesUpdate: setWinnerClock for resurrection failed", .{});
            return vtab.SQLITE_ERROR;
        };

        rows_impacted.incrementRowsImpacted();
        pRowid.* = 0;
        return vtab.SQLITE_OK;
    }

    // Step 5: For column updates, check if remote wins
    // Get local col_version for this specific column
    const local_col_version = merge_insert.getLocalColVersion(api_db, table_slice, pk_rowid, cid_slice) catch {
        log.debug("changesUpdate: getLocalColVersion failed", .{});
        return vtab.SQLITE_ERROR;
    };

    // Determine winner based on merge rules:
    // 1. Higher CL wins (already checked above)
    // 2. If CL equal, higher col_version wins
    // 3. If col_version equal, compare values (larger wins)
    var remote_wins = false;

    if (cl > local_cl) {
        // Remote has higher CL, wins unconditionally
        remote_wins = true;
    } else if (cl == local_cl) {
        // CL tied, compare col_version
        if (col_version > local_col_version) {
            remote_wins = true;
        } else if (col_version == local_col_version) {
            // Version tied, compare values (larger value wins)
            // Get remote value from argv[5]
            const remote_value = toApiValue(argv[5]);

            // Fetch local value for comparison
            var local_value_buf: [1024]u8 = undefined;
            if (std.fmt.bufPrintZ(&local_value_buf, "SELECT \"{s}\" FROM \"{s}\" WHERE rowid = ?", .{ cid_slice, table_slice })) |local_value_sql| {
                var local_stmt: ?*api.sqlite3_stmt = null;
                if (api.prepare_v2(api_db, local_value_sql, -1, &local_stmt, null) == api.SQLITE_OK) {
                    defer _ = api.finalize(local_stmt);
                    _ = api.bind_int64(local_stmt, 1, pk_rowid);

                    if (api.step(local_stmt) == api.SQLITE_ROW) {
                        // Compare using compare_values module
                        const local_sqlite_value = api.column_value(local_stmt, 0);
                        const cmp = compare_values.compareSqliteValues(remote_value, local_sqlite_value);
                        if (cmp > 0) {
                            // Remote value is larger, remote wins
                            remote_wins = true;
                        }
                        // If cmp <= 0, local wins (remote_wins stays false)
                    } else {
                        // No local row, remote wins
                        remote_wins = true;
                    }
                }
                // If prepare failed, local wins (conservative)
            } else |_| {
                // Buffer overflow, local wins (conservative)
            }
        }
        // If col_version < local_col_version, local wins (remote_wins stays false)
    }

    if (!remote_wins) {
        log.debug("changesUpdate: local wins (local_cl={}, local_cv={}, remote_cl={}, remote_cv={})", .{ local_cl, local_col_version, cl, col_version });
        pRowid.* = 0;
        return vtab.SQLITE_OK; // No-op
    }

    // Step 6: Remote wins - update base table and clock
    log.debug("changesUpdate: remote wins, updating table={s} col={s}", .{ table_slice, cid_slice });

    // Get the value from argv[5] (column 3: val)
    const value = toApiValue(argv[5]);

    // Update base table column
    merge_insert.updateBaseTableColumn(api_db, table_slice, pk_rowid, cid_slice, value) catch {
        log.debug("changesUpdate: updateBaseTableColumn failed", .{});
        return vtab.SQLITE_ERROR;
    };

    // Update clock table
    const site_id_ptr: ?[*]const u8 = @ptrCast(site_id_blob);
    merge_insert.setWinnerClock(api_db, table_slice, pk_rowid, cid_slice, col_version, db_version, site_id_ptr, @intCast(site_id_len), seq) catch {
        log.debug("changesUpdate: setWinnerClock failed", .{});
        return vtab.SQLITE_ERROR;
    };

    // Advance db_version to at least the incoming db_version when remote wins
    // This ensures crsql_db_version() reflects that a real change was applied
    _ = site_identity.nextDbVersion(db_version);

    // Increment rows impacted counter
    rows_impacted.incrementRowsImpacted();

    // Set rowid to 0 (we don't use rowid for inserts into this vtab)
    pRowid.* = 0;

    return vtab.SQLITE_OK;
}

// =============================================================================
// Module Definition
// =============================================================================

/// The crsql_changes module definition (writable for sync operations)
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
    .xUpdate = changesUpdate, // INSERT support for sync
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

    // Writable: xUpdate is implemented for INSERT support
    try std.testing.expect(changes_module.xUpdate != null);
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

test "discoverTablesCached uses stmt_cache module" {
    // Verify that the cached function exists and has correct signature
    // This is a compile-time check - the function signature must match expected types
    const fn_info = @typeInfo(@TypeOf(discoverTablesCached));
    try std.testing.expect(fn_info == .@"fn");
    try std.testing.expectEqual(@as(usize, 2), fn_info.@"fn".params.len);
}
