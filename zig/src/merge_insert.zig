//! Merge Insert SQL Helpers
//!
//! These functions execute the SQL statements needed for merge operations.
//! They are called from changes_vtab.changesUpdate.
//!
//! ## Statement Caching
//!
//! Hot path functions like `getLocalCl`, `getLocalColVersion`, `setWinnerClock`,
//! and `findPkFromBlob` are called on every incoming change during sync.
//! For a sync with 1000 changes, this means ~4000+ prepare/finalize cycles.
//!
//! The `TableMergeStmts` struct provides per-table statement caching to reduce
//! this to ~4 prepares per table. Callers can:
//! 1. Create a `TableMergeStmts` for each table being processed
//! 2. Use the cached variants: `getLocalClCached`, `setWinnerClockCached`, etc.
//! 3. Call `deinit()` when done with the table
//!
//! The original uncached functions remain available for backwards compatibility.

const std = @import("std");
const api = @import("ffi/api.zig");
const codec = @import("codec.zig");
const site_identity = @import("site_identity.zig");
const as_crr = @import("as_crr.zig");

/// Error set for merge operations
pub const MergeError = error{
    SqliteError,
    BufferOverflow,
    DecodeError,
    NoRows,
};

/// Statement cache for per-table merge operations.
/// Holds prepared statements and SQL buffers to avoid repeated prepare/finalize cycles.
pub const TableMergeStmts = struct {
    db: ?*api.sqlite3,
    table_name: []const u8,

    // SQL buffers (must outlive the statements)
    sql_local_cl: [512]u8 = undefined,
    sql_local_col_version: [512]u8 = undefined,
    sql_set_winner_clock: [1024]u8 = undefined,
    sql_find_pk: [1024]u8 = undefined,
    sql_row_exists_base: [512]u8 = undefined,
    sql_delete_base: [512]u8 = undefined,
    sql_drop_non_sentinel: [512]u8 = undefined,
    sql_insert_pks: [1024]u8 = undefined, // DEPRECATED - not used with new schema
    sql_zero_clock_resurrect: [512]u8 = undefined,

    // Statement handles (nullable, lazily prepared)
    local_cl_stmt: ?*api.sqlite3_stmt = null,
    local_col_version_stmt: ?*api.sqlite3_stmt = null,
    set_winner_clock_stmt: ?*api.sqlite3_stmt = null,
    find_pk_stmt: ?*api.sqlite3_stmt = null,
    row_exists_base_stmt: ?*api.sqlite3_stmt = null,
    delete_base_stmt: ?*api.sqlite3_stmt = null,
    drop_non_sentinel_stmt: ?*api.sqlite3_stmt = null,
    insert_pks_stmt: ?*api.sqlite3_stmt = null, // DEPRECATED - not used with new schema
    zero_clock_resurrect_stmt: ?*api.sqlite3_stmt = null,

    pub fn init(db: ?*api.sqlite3, table_name: []const u8) !TableMergeStmts {
        return TableMergeStmts{
            .db = db,
            .table_name = table_name,
        };
    }

    pub fn deinit(self: *TableMergeStmts) void {
        if (self.local_cl_stmt) |stmt| _ = api.finalize(stmt);
        if (self.local_col_version_stmt) |stmt| _ = api.finalize(stmt);
        if (self.set_winner_clock_stmt) |stmt| _ = api.finalize(stmt);
        if (self.find_pk_stmt) |stmt| _ = api.finalize(stmt);
        if (self.row_exists_base_stmt) |stmt| _ = api.finalize(stmt);
        if (self.delete_base_stmt) |stmt| _ = api.finalize(stmt);
        if (self.drop_non_sentinel_stmt) |stmt| _ = api.finalize(stmt);
        if (self.insert_pks_stmt) |stmt| _ = api.finalize(stmt);
        if (self.zero_clock_resurrect_stmt) |stmt| _ = api.finalize(stmt);
    }

    /// Get or prepare a cached statement.
    /// - stmt_ptr: pointer to the statement handle in this struct
    /// - sql_buf: pointer to the SQL buffer in this struct
    /// Returns a prepared statement, preparing it if needed.
    pub fn getOrPrepare(
        self: *TableMergeStmts,
        stmt_ptr: *?*api.sqlite3_stmt,
        sql_buf: [*]u8,
    ) MergeError!*api.sqlite3_stmt {
        if (stmt_ptr.*) |stmt| {
            _ = api.reset(stmt);
            _ = api.clear_bindings(stmt);
            return stmt;
        }

        // Find the null terminator in the SQL buffer
        var sql_len: usize = 0;
        while (sql_len < 2048 and sql_buf[sql_len] != 0) : (sql_len += 1) {}

        if (api.prepare_v2(self.db, sql_buf, @intCast(sql_len), stmt_ptr, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }

        return stmt_ptr.*.?;
    }
};

/// Get the local causal length for a (pk, col, db_version) triple from the clock table.
/// Get the local causal length (cl) for a row from the sentinel clock entry.
/// Returns 0 if no entry exists (no local state for this row).
pub fn getLocalCl(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
) MergeError!i64 {
    var buf: [512]u8 = undefined;
    // Get sentinel col_version (which stores the row's CL)
    const sql = std.fmt.bufPrintZ(
        &buf,
        "SELECT col_version FROM \"{s}__crsql_clock\" WHERE key = ? AND col_name = '-1'",
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    // No sentinel - check if row exists at all
    var exists_buf: [512]u8 = undefined;
    const exists_sql = std.fmt.bufPrintZ(&exists_buf, "SELECT 1 FROM \"{s}__crsql_clock\" WHERE key = ? LIMIT 1", .{table_name}) catch return MergeError.BufferOverflow;

    var exists_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, exists_sql, -1, &exists_stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(exists_stmt);

    _ = api.bind_int64(exists_stmt, 1, pk);

    if (api.step(exists_stmt) == api.SQLITE_ROW) {
        return 1; // Row exists but no explicit CL, default to 1 (created)
    }

    return 0; // No local row
}

/// Cached variant of getLocalCl using TableMergeStmts.
pub fn getLocalClCached(
    stmts: *TableMergeStmts,
    pk: i64,
) MergeError!i64 {
    // Format SQL on first use
    if (stmts.local_cl_stmt == null) {
        _ = std.fmt.bufPrintZ(&stmts.sql_local_cl, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE key = ? AND col_name = '-1'", .{stmts.table_name}) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.local_cl_stmt, @ptrCast(&stmts.sql_local_cl));

    _ = api.bind_int64(stmt, 1, pk);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    // No sentinel - fall back to uncached version which checks if row exists
    // This is important because locally created rows may not have a sentinel
    // but should still have CL=1
    return getLocalCl(stmts.db, stmts.table_name, pk);
}

/// Get the col_version for a (pk, col) pair from the clock table.
/// Returns the col_version from the existing clock entry, regardless of which site wrote it.
/// Returns -1 if no entry exists (no writes to this column yet).
pub fn getLocalColVersion(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
) MergeError!i64 {
    var buf: [512]u8 = undefined;
    // Get the col_version from the clock table for this key+col_name.
    // The clock table has a unique constraint on (key, col_name), so there's only one entry.
    // We don't filter by site_id because we want the current version regardless of who wrote it.
    const sql = std.fmt.bufPrintZ(
        &buf,
        "SELECT col_version FROM \"{s}__crsql_clock\" WHERE key = ? AND col_name = ?",
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        if (api.column_type(stmt, 0) == api.SQLITE_NULL) {
            return -1; // No entry
        }
        return api.column_int64(stmt, 0);
    }

    return -1; // No entry
}

/// Cached variant of getLocalColVersion using TableMergeStmts.
pub fn getLocalColVersionCached(
    stmts: *TableMergeStmts,
    pk: i64,
    col_name: []const u8,
) MergeError!i64 {
    // Format SQL on first use
    // Get the col_version from the clock table for this key+col_name.
    // The clock table has a unique constraint on (key, col_name), so there's only one entry.
    // We don't filter by site_id because we want the current version regardless of who wrote it.
    if (stmts.local_col_version_stmt == null) {
        _ = std.fmt.bufPrintZ(&stmts.sql_local_col_version, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE key = ? AND col_name = ?", .{stmts.table_name}) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.local_col_version_stmt, @ptrCast(&stmts.sql_local_col_version));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        if (api.column_type(stmt, 0) == api.SQLITE_NULL) {
            return -1; // No entry
        }
        return api.column_int64(stmt, 0);
    }

    return -1; // No entry
}

/// Set winner clock entry for a (pk, col, col_version, db_version) in the clock table.
/// Inserts or updates the entry with the given col_version and site ID.
/// site_id can be null for local changes (will be stored as 0).
/// Note: col_version parameter is used for the col_version column, and seq is always 0.
pub fn setWinnerClock(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
    col_version: i64,
    db_version: i64,
    site_id: ?[*]const u8,
    site_id_len: usize,
    seq: i64,
) MergeError!void {
    var buf: [1024]u8 = undefined;
    // Note: site_id in clock table is INTEGER (ordinal), not BLOB
    // For local changes (site_id NULL or len 0), we use 0 as the ordinal
    // For remote changes, look up or create the ordinal for the site_id blob
    var site_ordinal: i64 = 0;
    if (site_id != null and site_id_len == 16) {
        const site_id_slice = site_id.?[0..16];
        if (site_identity.getOrCreateSiteOrdinal(db, site_id_slice)) |ordinal| {
            site_ordinal = ordinal;
        }
    }

    const sql = std.fmt.bufPrintZ(
        &buf,
        \\INSERT INTO "{s}__crsql_clock" (key, col_name, col_version, db_version, site_id, seq)
        \\VALUES (?, ?, ?, ?, ?, ?)
        \\ON CONFLICT(key, col_name) DO UPDATE SET
        \\  col_version = excluded.col_version,
        \\  db_version = excluded.db_version,
        \\  site_id = excluded.site_id,
        \\  seq = excluded.seq
    ,
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, col_version);
    _ = api.bind_int64(stmt, 4, db_version);
    _ = api.bind_int64(stmt, 5, site_ordinal);
    _ = api.bind_int64(stmt, 6, seq);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Cached variant of setWinnerClock using TableMergeStmts.
/// site_id can be null for local changes (will be stored as 0).
pub fn setWinnerClockCached(
    stmts: *TableMergeStmts,
    pk: i64,
    col_name: []const u8,
    col_version: i64,
    db_version: i64,
    site_id: ?[*]const u8,
    site_id_len: usize,
    seq: i64,
) MergeError!void {
    // Note: site_id in clock table is INTEGER (ordinal), not BLOB
    // For local changes (site_id NULL or len 0), we use 0 as the ordinal
    // For remote changes, look up or create the ordinal for the site_id blob
    var site_ordinal: i64 = 0;
    if (site_id != null and site_id_len == 16) {
        const site_id_slice = site_id.?[0..16];
        if (site_identity.getOrCreateSiteOrdinal(stmts.db, site_id_slice)) |ordinal| {
            site_ordinal = ordinal;
        }
    }

    // Format SQL on first use
    if (stmts.set_winner_clock_stmt == null) {
        _ = std.fmt.bufPrintZ(
            &stmts.sql_set_winner_clock,
            \\INSERT INTO "{s}__crsql_clock" (key, col_name, col_version, db_version, site_id, seq)
            \\VALUES (?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(key, col_name) DO UPDATE SET
            \\  col_version = excluded.col_version,
            \\  db_version = excluded.db_version,
            \\  site_id = excluded.site_id,
            \\  seq = excluded.seq
        ,
            .{stmts.table_name},
        ) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.set_winner_clock_stmt, @ptrCast(&stmts.sql_set_winner_clock));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, col_version);
    _ = api.bind_int64(stmt, 4, db_version);
    _ = api.bind_int64(stmt, 5, site_ordinal);
    _ = api.bind_int64(stmt, 6, seq);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Helper to get the name of the single PK column for a table, if it exists.
/// Returns null if the table uses rowid or has a compound PK.
/// The returned buffer is owned by the function and valid until the next call.
fn getPkColumnName(db: ?*api.sqlite3, table_name: []const u8) !?[256]u8 {
    var table_name_buf: [256]u8 = undefined;
    const table_name_z = std.fmt.bufPrintZ(&table_name_buf, "{s}", .{table_name}) catch return MergeError.BufferOverflow;
    const info = as_crr.getTableInfo(db, table_name_z) catch return MergeError.SqliteError;

    if (info.pk_count != 1) {
        return null; // Not a single-column PK
    }

    // Find the column with pk_index == 1
    for (0..info.count) |i| {
        const col = &info.columns[i];
        if (col.pk_index == 1) {
            var result: [256]u8 = undefined;
            const len = @min(col.name_len, 255);
            @memcpy(result[0..len], col.name[0..len]);
            result[len] = 0;
            return result;
        }
    }

    return null;
}

/// Find the __crsql_key (pk) for a row in the pks table given the PK blob.
/// This works with the NEW Rust/C-compatible schema where PK values are stored
/// as individual columns, not as a packed blob.
///
/// Returns MergeError.NoRows if the pk blob is not found.
pub fn findPkFromBlob(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk_blob: [*]const u8,
    pk_blob_len: usize,
) MergeError!i64 {
    // Get TableInfo to know PK column names and count
    // getTableInfo requires null-terminated string
    var table_name_buf: [256]u8 = undefined;
    const table_name_z = std.fmt.bufPrintZ(&table_name_buf, "{s}", .{table_name}) catch return MergeError.BufferOverflow;
    const info = as_crr.getTableInfo(db, table_name_z) catch return MergeError.SqliteError;

    if (info.pk_count == 0) {
        return MergeError.SqliteError; // Table must have a primary key
    }

    // Unpack the pk_blob into individual values
    // We need a temporary allocator for the unpacked values
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const pk_blob_slice: []const u8 = pk_blob[0..pk_blob_len];
    const values = codec.unpack(allocator, pk_blob_slice) catch return MergeError.DecodeError;

    if (values.len != info.pk_count) {
        return MergeError.DecodeError; // Mismatch between unpacked values and PK column count
    }

    // Build SQL: SELECT __crsql_key FROM "table__crsql_pks" WHERE "col1" = ? AND "col2" = ?
    var sql_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&sql_buf);
    var writer = fbs.writer();

    writer.print("SELECT __crsql_key FROM \"{s}__crsql_pks\" WHERE ", .{table_name}) catch return MergeError.BufferOverflow;

    // Build WHERE clause with PK columns in order
    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        // Find the column with this pk_order
        var col_name: ?[]const u8 = null;
        for (0..info.count) |i| {
            const col = &info.columns[i];
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                col_name = col.name[0..col.name_len];
                break;
            }
        }

        const name = col_name orelse return MergeError.SqliteError;

        if (pk_written > 0) {
            writer.writeAll(" AND ") catch return MergeError.BufferOverflow;
        }
        writer.print("\"{s}\" IS ?", .{name}) catch return MergeError.BufferOverflow;
        pk_written += 1;
    }

    const sql_len = fbs.pos;
    const sql = sql_buf[0..sql_len];

    // Prepare statement
    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql.ptr, @intCast(sql_len), &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    // Bind unpacked PK values in order
    for (values, 0..) |value, idx| {
        const param_idx: c_int = @intCast(idx + 1);
        const rc = switch (value) {
            .Null => api.bind_null(stmt, param_idx),
            .Integer => |i| api.bind_int64(stmt, param_idx, i),
            .Float => |f| api.bind_double(stmt, param_idx, f),
            .Text => |t| api.bind_text(stmt, param_idx, t.ptr, @intCast(t.len), api.getTransientDestructor()),
            .Blob => |b| api.bind_blob(stmt, param_idx, b.ptr, @intCast(b.len), api.getTransientDestructor()),
        };
        if (rc != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    }

    // Execute query
    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return MergeError.NoRows;
}

/// Get base_rowid for a given __crsql_key (pk) from the pks table.
/// Returns null if the entry is tombstoned (base_rowid is NULL).
pub fn getBaseRowidFromPk(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
) MergeError!?i64 {
    var buf: [256]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT base_rowid FROM \"{s}__crsql_pks\" WHERE __crsql_key = ?", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);

    if (api.step(stmt) == api.SQLITE_ROW) {
        if (api.column_type(stmt, 0) == api.SQLITE_NULL) {
            return null; // Tombstoned
        }
        return api.column_int64(stmt, 0);
    }

    return MergeError.NoRows;
}

/// Get the actual PK value(s) for a given __crsql_key from the pks table.
/// For single-column INTEGER PRIMARY KEY tables, this returns the actual PK value
/// which equals the base table's rowid.
/// Returns MergeError.NoRows if the __crsql_key is not found.
pub fn getPkValueFromKey(
    db: ?*api.sqlite3,
    table_name: []const u8,
    crsql_key: i64,
) MergeError!i64 {
    // Get the PK column name
    const pk_col = getPkColumnName(db, table_name) catch return MergeError.SqliteError;
    if (pk_col == null) {
        // No single PK column - fall back to using __crsql_key as rowid
        // This handles rowid-only tables where __crsql_key == base rowid
        return crsql_key;
    }

    const pk_col_name = pk_col.?;
    const pk_col_len = std.mem.indexOfScalar(u8, &pk_col_name, 0) orelse pk_col_name.len;
    const pk_col_slice = pk_col_name[0..pk_col_len];

    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT \"{s}\" FROM \"{s}__crsql_pks\" WHERE __crsql_key = ?", .{ pk_col_slice, table_name }) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, crsql_key);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return MergeError.NoRows;
}

/// Check if a row exists in the base table by __crsql_key.
/// Looks up the actual PK value from the pks table and uses that to match the base row.
pub fn rowExistsInBaseTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    crsql_key: i64,
) MergeError!bool {
    // Look up the actual PK value from the pks table
    const pk_value = getPkValueFromKey(db, table_name, crsql_key) catch |err| {
        if (err == MergeError.NoRows) return false;
        return err;
    };

    // Get the PK column name to use in WHERE clause
    const pk_col = getPkColumnName(db, table_name) catch return false;

    var buf: [256]u8 = undefined;

    const sql = if (pk_col) |pk_col_name| blk: {
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col_name, 0) orelse pk_col_name.len;
        const pk_col_slice = pk_col_name[0..pk_col_len];
        break :blk std.fmt.bufPrintZ(&buf, "SELECT 1 FROM \"{s}\" WHERE \"{s}\" = ?", .{ table_name, pk_col_slice }) catch return false;
    } else blk: {
        break :blk std.fmt.bufPrintZ(&buf, "SELECT 1 FROM \"{s}\" WHERE rowid = ?", .{table_name}) catch return false;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk_value);

    return api.step(stmt) == api.SQLITE_ROW;
}

/// Delete row from base table by __crsql_key.
/// Looks up the actual PK value from the pks table and uses that to delete the base row.
pub fn deleteFromBaseTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    crsql_key: i64,
) MergeError!void {
    // Look up the actual PK value from the pks table
    const pk_value = try getPkValueFromKey(db, table_name, crsql_key);

    // Get the PK column name to use in WHERE clause
    const pk_col = getPkColumnName(db, table_name) catch return MergeError.SqliteError;

    var buf: [256]u8 = undefined;

    const sql = if (pk_col) |pk_col_name| blk: {
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col_name, 0) orelse pk_col_name.len;
        const pk_col_slice = pk_col_name[0..pk_col_len];
        break :blk std.fmt.bufPrintZ(&buf, "DELETE FROM \"{s}\" WHERE \"{s}\" = ?", .{ table_name, pk_col_slice }) catch return MergeError.BufferOverflow;
    } else blk: {
        break :blk std.fmt.bufPrintZ(&buf, "DELETE FROM \"{s}\" WHERE rowid = ?", .{table_name}) catch return MergeError.BufferOverflow;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk_value);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
    // Note: In the new schema, tombstoning is tracked via the clock table sentinel,
    // not via a base_rowid column in the pks table.
}

/// Drop all clock entries for a row except the sentinel (col_name = '-1') entry.
/// Used when deleting a row to clean up per-column clock entries.
pub fn dropNonSentinelClocks(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
) MergeError!void {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(
        &buf,
        "DELETE FROM \"{s}__crsql_clock\" WHERE key = ? AND col_name != '-1'",
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Reset col_version to 0 for all non-sentinel clock entries for a row.
/// Used during resurrection to mark all columns as needing re-sync.
pub fn zeroClockOnResurrect(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
) MergeError!void {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(
        &buf,
        "UPDATE \"{s}__crsql_clock\" SET col_version = 0 WHERE key = ? AND col_name != '-1'",
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Cached variant of zeroClockOnResurrect using TableMergeStmts.
pub fn zeroClockOnResurrectCached(
    stmts: *TableMergeStmts,
    pk: i64,
) MergeError!void {
    // Format SQL on first use
    if (stmts.zero_clock_resurrect_stmt == null) {
        _ = std.fmt.bufPrintZ(&stmts.sql_zero_clock_resurrect, "UPDATE \"{s}__crsql_clock\" SET col_version = 0 WHERE key = ? AND col_name != '-1'", .{stmts.table_name}) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.zero_clock_resurrect_stmt, @ptrCast(&stmts.sql_zero_clock_resurrect));

    _ = api.bind_int64(stmt, 1, pk);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Insert a row for resurrection via sentinel (no column data, just PK).
/// Creates a new row with just the PK value (non-PK columns will be NULL).
/// Used when a resurrection sentinel (odd CL) arrives for a tombstoned row.
/// Looks up the actual PK value from the pks table using __crsql_key.
pub fn insertRowForSentinelResurrection(
    db: ?*api.sqlite3,
    table_name: []const u8,
    crsql_key: i64,
) MergeError!void {
    // Look up the actual PK value from the pks table
    const pk_value = try getPkValueFromKey(db, table_name, crsql_key);

    // Get the PK column name from the table schema
    const pk_col_name = try getPkColumnName(db, table_name);

    var buf: [512]u8 = undefined;
    var stmt: ?*api.sqlite3_stmt = null;

    if (pk_col_name) |pk_col| {
        // Table has a declared PK column - insert using that column name
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col, 0) orelse pk_col.len;
        const pk_col_slice = pk_col[0..pk_col_len];

        // Build: INSERT INTO "{table}" ("{pk_col}") VALUES (?)
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (\"{s}\") VALUES (?)", .{ table_name, pk_col_slice }) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    } else {
        // No declared PK column - use rowid directly
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (rowid) VALUES (?)", .{table_name}) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    }
    defer _ = api.finalize(stmt);

    // Bind the actual PK value (not __crsql_key)
    _ = api.bind_int64(stmt, 1, pk_value);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Insert a row for resurrection (resurrecting a deleted row with new data).
/// Creates a new row with the given __crsql_key and column value.
/// Looks up the actual PK value from the pks table.
pub fn insertRowForResurrection(
    db: ?*api.sqlite3,
    table_name: []const u8,
    crsql_key: i64,
    col_name: []const u8,
    value: ?*api.sqlite3_value,
) MergeError!void {
    // Look up the actual PK value from the pks table
    const pk_value = try getPkValueFromKey(db, table_name, crsql_key);

    // Get the PK column name from the table schema
    const pk_col_name = try getPkColumnName(db, table_name);

    var buf: [1024]u8 = undefined;
    var stmt: ?*api.sqlite3_stmt = null;

    if (pk_col_name) |pk_col| {
        // Table has a declared PK column - insert using that column name
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col, 0) orelse pk_col.len;
        const pk_col_slice = pk_col[0..pk_col_len];

        // Build: INSERT INTO "{table}" ("{pk_col}", "{col}") VALUES (?, ?)
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (\"{s}\", \"{s}\") VALUES (?, ?)", .{ table_name, pk_col_slice, col_name }) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    } else {
        // No declared PK column - use rowid directly
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (rowid, \"{s}\") VALUES (?, ?)", .{ table_name, col_name }) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    }
    defer _ = api.finalize(stmt);

    // Bind the actual PK value (not __crsql_key)
    _ = api.bind_int64(stmt, 1, pk_value);

    // Bind column value based on type
    if (value) |v| {
        const val_type = api.value_type(v);
        switch (val_type) {
            api.SQLITE_INTEGER => _ = api.bind_int64(stmt, 2, api.value_int64(v)),
            api.SQLITE_FLOAT => {
                _ = api.bind_double(stmt, 2, api.value_double(v));
            },
            api.SQLITE_TEXT => {
                const text = api.value_text(v);
                const len = api.value_bytes(v);
                if (text) |t| {
                    _ = api.bind_text(stmt, 2, t, len, api.getTransientDestructor());
                } else {
                    _ = api.bind_null(stmt, 2);
                }
            },
            api.SQLITE_BLOB => {
                const blob = api.value_blob(v);
                const len = api.value_bytes(v);
                _ = api.bind_blob(stmt, 2, blob, len, api.getTransientDestructor());
            },
            else => _ = api.bind_null(stmt, 2),
        }
    } else {
        _ = api.bind_null(stmt, 2);
    }

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Update a column value in the base table for an existing row.
/// Looks up the actual PK value from the pks table and uses that to update the base row.
pub fn updateBaseTableColumn(
    db: ?*api.sqlite3,
    table_name: []const u8,
    crsql_key: i64,
    col_name: []const u8,
    value: ?*api.sqlite3_value,
) MergeError!void {
    // Look up the actual PK value from the pks table
    const pk_value = try getPkValueFromKey(db, table_name, crsql_key);

    // Get the PK column name to use in WHERE clause
    // Note: We cannot use rowid for tables without INTEGER PRIMARY KEY,
    // because rowid != PK value in those cases.
    const pk_col = getPkColumnName(db, table_name) catch return MergeError.SqliteError;

    var buf: [1024]u8 = undefined;

    const sql = if (pk_col) |pk_col_name| blk: {
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col_name, 0) orelse pk_col_name.len;
        const pk_col_slice = pk_col_name[0..pk_col_len];
        break :blk std.fmt.bufPrintZ(&buf, "UPDATE \"{s}\" SET \"{s}\" = ? WHERE \"{s}\" = ?", .{ table_name, col_name, pk_col_slice }) catch return MergeError.BufferOverflow;
    } else blk: {
        // No declared PK column - use rowid directly (only valid for rowid-based tables)
        break :blk std.fmt.bufPrintZ(&buf, "UPDATE \"{s}\" SET \"{s}\" = ? WHERE rowid = ?", .{ table_name, col_name }) catch return MergeError.BufferOverflow;
    };

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    // Bind value based on type
    if (value) |v| {
        const val_type = api.value_type(v);
        switch (val_type) {
            api.SQLITE_INTEGER => _ = api.bind_int64(stmt, 1, api.value_int64(v)),
            api.SQLITE_FLOAT => {
                _ = api.bind_double(stmt, 1, api.value_double(v));
            },
            api.SQLITE_TEXT => {
                const text = api.value_text(v);
                const len = api.value_bytes(v);
                if (text) |t| {
                    _ = api.bind_text(stmt, 1, t, len, api.getTransientDestructor());
                } else {
                    _ = api.bind_null(stmt, 1);
                }
            },
            api.SQLITE_BLOB => {
                const blob = api.value_blob(v);
                const len = api.value_bytes(v);
                _ = api.bind_blob(stmt, 1, blob, len, api.getTransientDestructor());
            },
            else => _ = api.bind_null(stmt, 1),
        }
    } else {
        _ = api.bind_null(stmt, 1);
    }
    // Use the actual PK value (which equals rowid for INTEGER PRIMARY KEY tables)
    _ = api.bind_int64(stmt, 2, pk_value);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Insert or update a column value in the base table for a given row.
/// Handles both declared-PK and rowid-based tables.
pub fn insertOrUpdateColumn(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk_blob: [*]const u8,
    pk_blob_len: usize,
    col_name: []const u8,
    value: ?*api.sqlite3_value,
) MergeError!void {
    // Decode the PK blob to get PK values
    const pk_slice = pk_blob[0..pk_blob_len];
    const values = codec.unpack(std.heap.page_allocator, pk_slice) catch return MergeError.DecodeError;
    defer {
        for (values) |val| {
            switch (val) {
                .Text => |t| std.heap.page_allocator.free(t),
                .Blob => |b| std.heap.page_allocator.free(b),
                else => {},
            }
        }
        std.heap.page_allocator.free(values);
    }

    if (values.len == 0) return MergeError.DecodeError;

    // For MVP, only handle single integer PK
    const pk_value = values[0];
    const pk_int: i64 = switch (pk_value) {
        .Integer => |i| i,
        else => return MergeError.DecodeError, // Only integer PKs supported for MVP
    };

    // Get the PK column name from the table schema
    const pk_col_name = try getPkColumnName(db, table_name);

    var buf: [1024]u8 = undefined;
    var stmt: ?*api.sqlite3_stmt = null;

    if (pk_col_name) |pk_col| {
        // Table has a declared PK column - insert using that column name
        // Find the length of the null-terminated PK column name
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col, 0) orelse pk_col.len;
        const pk_col_slice = pk_col[0..pk_col_len];

        // Build: INSERT INTO "{table}" ("{pk_col}", "{col}") VALUES (?, ?)
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (\"{s}\", \"{s}\") VALUES (?, ?)", .{ table_name, pk_col_slice, col_name }) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    } else {
        // No declared PK column - use rowid directly
        // Build: INSERT INTO "{table}" (rowid, "{col}") VALUES (?, ?)
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (rowid, \"{s}\") VALUES (?, ?)", .{ table_name, col_name }) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    }
    defer _ = api.finalize(stmt);

    // Bind the PK value
    _ = api.bind_int64(stmt, 1, pk_int);

    // Bind column value based on type
    if (value) |v| {
        const val_type = api.value_type(v);
        switch (val_type) {
            api.SQLITE_INTEGER => _ = api.bind_int64(stmt, 2, api.value_int64(v)),
            api.SQLITE_FLOAT => {
                _ = api.bind_double(stmt, 2, api.value_double(v));
            },
            api.SQLITE_TEXT => {
                const text = api.value_text(v);
                const len = api.value_bytes(v);
                _ = api.bind_text(stmt, 2, text, len, api.getTransientDestructor());
            },
            api.SQLITE_BLOB => {
                const blob = api.value_blob(v);
                const len = api.value_bytes(v);
                _ = api.bind_blob(stmt, 2, blob, len, api.getTransientDestructor());
            },
            api.SQLITE_NULL => _ = api.bind_null(stmt, 2),
            else => return MergeError.SqliteError,
        }
    } else {
        _ = api.bind_null(stmt, 2);
    }

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Insert into __crsql_pks table (wrapper for insertIntoPksTableAndGetPk).
/// DEPRECATED: This uses the old signature with base_rowid for backwards compatibility.
/// New code should call insertIntoPksTableAndGetPk directly.
pub fn insertIntoPksTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pks_blob: [*]const u8,
    pks_len: usize,
) MergeError!void {
    _ = try insertIntoPksTableAndGetPk(db, table_name, pks_blob, pks_len);
}

/// Insert into __crsql_pks table and return the __crsql_key that was assigned.
/// Works with the NEW Rust/C-compatible schema where PK values are stored as individual columns.
/// Returns the auto-generated __crsql_key via last_insert_rowid().
pub fn insertIntoPksTableAndGetPk(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pks_blob: [*]const u8,
    pks_len: usize,
) MergeError!i64 {
    // Get TableInfo to know PK column names and count
    var table_name_buf: [256]u8 = undefined;
    const table_name_z = std.fmt.bufPrintZ(&table_name_buf, "{s}", .{table_name}) catch return MergeError.BufferOverflow;
    const info = as_crr.getTableInfo(db, table_name_z) catch return MergeError.SqliteError;

    if (info.pk_count == 0) {
        return MergeError.SqliteError; // Table must have a primary key
    }

    // Unpack the pks_blob into individual values
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const pks_blob_slice: []const u8 = pks_blob[0..pks_len];
    const values = codec.unpack(allocator, pks_blob_slice) catch return MergeError.DecodeError;

    if (values.len != info.pk_count) {
        return MergeError.DecodeError; // Mismatch between unpacked values and PK column count
    }

    // Build SQL: INSERT INTO "table__crsql_pks" (__crsql_key, "col1", "col2") VALUES (NULL, ?, ?)
    var sql_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&sql_buf);
    var writer = fbs.writer();

    writer.print("INSERT INTO \"{s}__crsql_pks\" (__crsql_key", .{table_name}) catch return MergeError.BufferOverflow;

    // Add PK column names in order
    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        // Find the column with this pk_order
        var col_name: ?[]const u8 = null;
        for (0..info.count) |i| {
            const col = &info.columns[i];
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                col_name = col.name[0..col.name_len];
                break;
            }
        }

        const name = col_name orelse return MergeError.SqliteError;
        writer.print(", \"{s}\"", .{name}) catch return MergeError.BufferOverflow;
        pk_written += 1;
    }

    writer.writeAll(") VALUES (NULL") catch return MergeError.BufferOverflow;

    // Add placeholders for values
    for (0..info.pk_count) |_| {
        writer.writeAll(", ?") catch return MergeError.BufferOverflow;
    }

    writer.writeAll(")") catch return MergeError.BufferOverflow;

    const sql_len = fbs.pos;
    const sql = sql_buf[0..sql_len];

    // Prepare statement
    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql.ptr, @intCast(sql_len), &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    // Bind unpacked PK values in order
    for (values, 0..) |value, idx| {
        const param_idx: c_int = @intCast(idx + 1);
        const rc = switch (value) {
            .Null => api.bind_null(stmt, param_idx),
            .Integer => |i| api.bind_int64(stmt, param_idx, i),
            .Float => |f| api.bind_double(stmt, param_idx, f),
            .Text => |t| api.bind_text(stmt, param_idx, t.ptr, @intCast(t.len), api.getTransientDestructor()),
            .Blob => |b| api.bind_blob(stmt, param_idx, b.ptr, @intCast(b.len), api.getTransientDestructor()),
        };
        if (rc != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    }

    // Execute INSERT
    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }

    // Return the auto-generated __crsql_key
    return api.last_insert_rowid(db);
}

/// Insert a row into a PK-only table (table with no non-PK columns).
/// Decodes the pk blob to get the PK value and inserts a row with just that value.
/// Returns the new rowid.
pub fn insertPkOnlyRow(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk_blob: [*]const u8,
    pk_blob_len: usize,
) MergeError!i64 {
    // Decode the PK blob to get the PK value
    const pk_slice = pk_blob[0..pk_blob_len];
    const values = codec.unpack(std.heap.page_allocator, pk_slice) catch return MergeError.DecodeError;
    defer {
        for (values) |val| {
            switch (val) {
                .Text => |t| std.heap.page_allocator.free(t),
                .Blob => |b| std.heap.page_allocator.free(b),
                else => {},
            }
        }
        std.heap.page_allocator.free(values);
    }

    if (values.len == 0) return MergeError.DecodeError;

    // For MVP, only handle single integer PK
    const pk_value = values[0];
    const pk_int: i64 = switch (pk_value) {
        .Integer => |i| i,
        else => return MergeError.DecodeError, // Only integer PKs supported for MVP
    };

    // Get the PK column name from the table schema
    const pk_col_name = try getPkColumnName(db, table_name);

    var buf: [512]u8 = undefined;
    var stmt: ?*api.sqlite3_stmt = null;

    if (pk_col_name) |pk_col| {
        // Table has a declared PK column - insert using that column name
        const pk_col_len = std.mem.indexOfScalar(u8, &pk_col, 0) orelse pk_col.len;
        const pk_col_slice = pk_col[0..pk_col_len];

        // Build: INSERT INTO "{table}" ("{pk_col}") VALUES (?)
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (\"{s}\") VALUES (?)", .{ table_name, pk_col_slice }) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    } else {
        // No declared PK column - use rowid directly
        // Build: INSERT INTO "{table}" (rowid) VALUES (?)
        const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}\" (rowid) VALUES (?)", .{table_name}) catch return MergeError.BufferOverflow;

        if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }
    }
    defer _ = api.finalize(stmt);

    // Bind the PK value
    _ = api.bind_int64(stmt, 1, pk_int);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }

    // Return the rowid of the inserted row
    return api.last_insert_rowid(db);
}

/// Cached variant of findPkFromBlob using TableMergeStmts.
/// DEPRECATED - This assumes old schema with pks blob column.
/// New code should use the uncached findPkFromBlob which works with new schema.
pub fn findPkFromBlobCached(
    stmts: *TableMergeStmts,
    pk_blob: [*]const u8,
    pk_blob_len: usize,
) MergeError!i64 {
    // Format SQL on first use
    if (stmts.find_pk_stmt == null) {
        _ = std.fmt.bufPrintZ(&stmts.sql_find_pk, "SELECT __crsql_key FROM \"{s}__crsql_pks\" WHERE pks = ?", .{stmts.table_name}) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.find_pk_stmt, @ptrCast(&stmts.sql_find_pk));

    _ = api.bind_blob(stmt, 1, pk_blob, @intCast(pk_blob_len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return MergeError.NoRows;
}

/// Check if row exists in base table (cached variant).
/// Looks up the actual PK value from the pks table and uses that to match the base row.
///
/// This is the cached variant of `rowExistsInBaseTable` for use with `TableMergeStmts`.
/// Note: Falls back to uncached version since we need to use PK column name, not rowid.
pub fn rowExistsInBaseTableCached(stmts: *TableMergeStmts, crsql_key: i64) MergeError!bool {
    // Use uncached version which properly handles PK column vs rowid
    return rowExistsInBaseTable(stmts.db, stmts.table_name, crsql_key);
}

/// Delete row from base table (cached variant).
/// Looks up the actual PK value from the pks table and uses that to delete the base row.
///
/// This is the cached variant of `deleteFromBaseTable` for use with `TableMergeStmts`.
/// Note: Falls back to uncached version since we need to use PK column name, not rowid.
pub fn deleteFromBaseTableCached(stmts: *TableMergeStmts, crsql_key: i64) MergeError!void {
    // Use uncached version which properly handles PK column vs rowid
    return deleteFromBaseTable(stmts.db, stmts.table_name, crsql_key);
}

/// Drop all clock entries except sentinel (-1) using cached statement.
///
/// This is the cached variant of `dropNonSentinelClocks` for use with `TableMergeStmts`.
pub fn dropNonSentinelClocksCached(stmts: *TableMergeStmts, pk: i64) MergeError!void {
    // Format SQL on first use
    if (stmts.drop_non_sentinel_stmt == null) {
        _ = std.fmt.bufPrintZ(&stmts.sql_drop_non_sentinel, "DELETE FROM \"{s}__crsql_clock\" WHERE key = ? AND col_name != '-1'", .{stmts.table_name}) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.drop_non_sentinel_stmt, @ptrCast(&stmts.sql_drop_non_sentinel));

    _ = api.bind_int64(stmt, 1, pk);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Cached variant of insertIntoPksTableAndGetPk.
/// DEPRECATED - This assumes old schema with base_rowid and pks blob.
/// New code should use uncached insertIntoPksTableAndGetPk which works with new schema.
pub fn insertIntoPksTableCached(
    stmts: *TableMergeStmts,
    base_rowid: i64,
    pks_blob: [*]const u8,
    pks_len: usize,
) MergeError!i64 {
    // Format SQL on first use
    if (stmts.insert_pks_stmt == null) {
        _ = std.fmt.bufPrintZ(&stmts.sql_insert_pks, "INSERT OR IGNORE INTO \"{s}__crsql_pks\" (base_rowid, pks) VALUES (?, ?)", .{stmts.table_name}) catch return MergeError.BufferOverflow;
    }
    const stmt = try stmts.getOrPrepare(&stmts.insert_pks_stmt, @ptrCast(&stmts.sql_insert_pks));

    _ = api.bind_int64(stmt, 1, base_rowid);
    _ = api.bind_blob(stmt, 2, pks_blob, @intCast(pks_len), api.getTransientDestructor());

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }

    // Query back the pk
    var pk_buf: [256]u8 = undefined;
    const pk_sql = std.fmt.bufPrintZ(&pk_buf, "SELECT __crsql_key FROM \"{s}__crsql_pks\" WHERE pks = ?", .{stmts.table_name}) catch return MergeError.BufferOverflow;

    var pk_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(stmts.db, pk_sql, -1, &pk_stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(pk_stmt);

    _ = api.bind_blob(pk_stmt, 1, pks_blob, @intCast(pks_len), api.getTransientDestructor());

    if (api.step(pk_stmt) == api.SQLITE_ROW) {
        return api.column_int64(pk_stmt, 0);
    }

    return MergeError.NoRows;
}

/// Prepare cached statements for TableMergeStmts.
/// This pre-builds all SQL statements that will be used frequently.
pub fn prepareStmts(stmts: *TableMergeStmts) MergeError!void {
    // Local causal length query
    _ = std.fmt.bufPrintZ(
        &stmts.sql_local_cl,
        "SELECT cl FROM \"{s}__crsql_clock\" WHERE __crsql_key = ? AND col_name = ? AND db_version = ? AND site_id IS NULL",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Local col_version query
    _ = std.fmt.bufPrintZ(
        &stmts.sql_local_col_version,
        "SELECT MAX(col_version) FROM \"{s}__crsql_clock\" WHERE __crsql_key = ? AND col_name = ? AND site_id IS NULL",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Set winner clock
    _ = std.fmt.bufPrintZ(
        &stmts.sql_set_winner_clock,
        \\INSERT INTO "{s}__crsql_clock" (__crsql_key, col_name, col_version, db_version, site_id, cl, seq)
        \\VALUES (?, ?, ?, ?, ?, ?, 0)
        \\ON CONFLICT(__crsql_key, col_name, col_version, db_version, site_id)
        \\DO UPDATE SET cl = excluded.cl, seq = 0
    ,
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Find pk from blob - DEPRECATED (old schema)
    _ = std.fmt.bufPrintZ(
        &stmts.sql_find_pk,
        "SELECT __crsql_key FROM \"{s}__crsql_pks\" WHERE pks = ?",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Row exists in base table
    _ = std.fmt.bufPrintZ(
        &stmts.sql_row_exists_base,
        "SELECT 1 FROM \"{s}\" WHERE rowid = ?",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Delete from base table
    _ = std.fmt.bufPrintZ(
        &stmts.sql_delete_base,
        "DELETE FROM \"{s}\" WHERE rowid = ?",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Drop non-sentinel clocks
    _ = std.fmt.bufPrintZ(
        &stmts.sql_drop_non_sentinel,
        "DELETE FROM \"{s}__crsql_clock\" WHERE __crsql_key = ? AND (col_version != -1 OR site_id IS NOT NULL)",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;

    // Insert into pks - DEPRECATED (old schema)
    _ = std.fmt.bufPrintZ(
        &stmts.sql_insert_pks,
        "INSERT INTO \"{s}__crsql_pks\" (base_rowid, pks) VALUES (?, ?) ON CONFLICT(pks) DO UPDATE SET base_rowid = excluded.base_rowid",
        .{stmts.table_name},
    ) catch return MergeError.BufferOverflow;
}
