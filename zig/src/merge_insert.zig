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

    // Statement handles (nullable, lazily prepared)
    local_cl_stmt: ?*api.sqlite3_stmt = null,
    local_col_version_stmt: ?*api.sqlite3_stmt = null,
    set_winner_clock_stmt: ?*api.sqlite3_stmt = null,
    find_pk_stmt: ?*api.sqlite3_stmt = null,
    row_exists_base_stmt: ?*api.sqlite3_stmt = null,
    delete_base_stmt: ?*api.sqlite3_stmt = null,
    drop_non_sentinel_stmt: ?*api.sqlite3_stmt = null,
    insert_pks_stmt: ?*api.sqlite3_stmt = null, // DEPRECATED - not used with new schema

    pub fn init(db: ?*api.sqlite3, table_name: []const u8) TableMergeStmts {
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
/// Returns 0 if no entry exists (first write to this column).
pub fn getLocalCl(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
    db_version: i64,
) MergeError!i64 {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(
        &buf,
        "SELECT cl FROM \"{s}__crsql_clock\" WHERE __crsql_key = ? AND col_name = ? AND db_version = ? AND site_id IS NULL",
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, db_version);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return 0; // No entry = causal length 0
}

/// Cached variant of getLocalCl using TableMergeStmts.
pub fn getLocalClCached(
    stmts: *TableMergeStmts,
    pk: i64,
    col_name: []const u8,
    db_version: i64,
) MergeError!i64 {
    const stmt = try stmts.getOrPrepare(&stmts.local_cl_stmt, @ptrCast(&stmts.sql_local_cl));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, db_version);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return 0; // No entry = causal length 0
}

/// Get the local col_version for a (pk, col) pair from the clock table.
/// Returns -1 if no entry exists (no writes to this column yet).
pub fn getLocalColVersion(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
) MergeError!i64 {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(
        &buf,
        "SELECT MAX(col_version) FROM \"{s}__crsql_clock\" WHERE __crsql_key = ? AND col_name = ? AND site_id IS NULL",
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
/// Inserts or updates the entry with the given causal length and site ID.
pub fn setWinnerClock(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
    col_version: i64,
    db_version: i64,
    site_id: [*]const u8,
    site_id_len: usize,
    cl: i64,
) MergeError!void {
    var buf: [1024]u8 = undefined;
    const sql = std.fmt.bufPrintZ(
        &buf,
        \\INSERT INTO "{s}__crsql_clock" (__crsql_key, col_name, col_version, db_version, site_id, cl, seq)
        \\VALUES (?, ?, ?, ?, ?, ?, 0)
        \\ON CONFLICT(__crsql_key, col_name, col_version, db_version, site_id)
        \\DO UPDATE SET cl = excluded.cl, seq = 0
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
    _ = api.bind_blob(stmt, 5, site_id, @intCast(site_id_len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 6, cl);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Cached variant of setWinnerClock using TableMergeStmts.
pub fn setWinnerClockCached(
    stmts: *TableMergeStmts,
    pk: i64,
    col_name: []const u8,
    col_version: i64,
    db_version: i64,
    site_id: [*]const u8,
    site_id_len: usize,
    cl: i64,
) MergeError!void {
    const stmt = try stmts.getOrPrepare(&stmts.set_winner_clock_stmt, @ptrCast(&stmts.sql_set_winner_clock));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, col_version);
    _ = api.bind_int64(stmt, 4, db_version);
    _ = api.bind_blob(stmt, 5, site_id, @intCast(site_id_len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 6, cl);

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

    const sql = std.mem.sliceTo(&sql_buf, 0);

    // Prepare statement
    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql.ptr, -1, &stmt, null) != api.SQLITE_OK) {
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

/// Check if a row exists in the base table by __crsql_key (pk).
/// First looks up base_rowid from pks table, then checks if row exists in base table.
pub fn rowExistsInBaseTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
) MergeError!bool {
    const base_rowid_opt = getBaseRowidFromPk(db, table_name, pk) catch return false;
    const base_rowid = base_rowid_opt orelse return false; // Tombstoned = no row

    var buf: [256]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT 1 FROM \"{s}\" WHERE rowid = ?", .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, base_rowid);

    return api.step(stmt) == api.SQLITE_ROW;
}

/// Delete row from base table by __crsql_key (pk).
/// First looks up base_rowid from pks table, then deletes from base table.
/// Also marks the pks entry as tombstoned (sets base_rowid to NULL).
pub fn deleteFromBaseTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
) MergeError!void {
    const base_rowid_opt = getBaseRowidFromPk(db, table_name, pk) catch return;
    const base_rowid = base_rowid_opt orelse return; // Already tombstoned

    // Delete from base table
    var buf: [256]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DELETE FROM \"{s}\" WHERE rowid = ?", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, base_rowid);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }

    // Mark pks entry as tombstoned
    var tombstone_buf: [512]u8 = undefined;
    const tombstone_sql = std.fmt.bufPrintZ(&tombstone_buf, "UPDATE \"{s}__crsql_pks\" SET base_rowid = NULL WHERE __crsql_key = ?", .{table_name}) catch return MergeError.BufferOverflow;

    var tombstone_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, tombstone_sql, -1, &tombstone_stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(tombstone_stmt);

    _ = api.bind_int64(tombstone_stmt, 1, pk);

    const tombstone_rc = api.step(tombstone_stmt);
    if (tombstone_rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Drop all clock entries for a (pk, col) pair except the sentinel (-1, site_id=NULL) entry.
pub fn dropNonSentinelClocks(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
) MergeError!void {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(
        &buf,
        "DELETE FROM \"{s}__crsql_clock\" WHERE __crsql_key = ? AND col_name = ? AND (col_version != -1 OR site_id IS NOT NULL)",
        .{table_name},
    ) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());

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

    const sql = std.mem.sliceTo(&sql_buf, 0);

    // Prepare statement
    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql.ptr, -1, &stmt, null) != api.SQLITE_OK) {
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
    const stmt = try stmts.getOrPrepare(&stmts.find_pk_stmt, @ptrCast(&stmts.sql_find_pk));

    _ = api.bind_blob(stmt, 1, pk_blob, @intCast(pk_blob_len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return MergeError.NoRows;
}

/// Check if a row exists in the base table by pks table key using cached statement.
/// First looks up base_rowid from pks table, then checks base table.
///
/// This is the cached variant of `rowExistsInBaseTable` for use with `TableMergeStmts`.
pub fn rowExistsInBaseTableCached(stmts: *TableMergeStmts, pk: i64) MergeError!bool {
    // First, get base_rowid from pks table (not cached - uses uncached lookup)
    const base_rowid_opt = getBaseRowidFromPk(stmts.db, stmts.table_name, pk) catch return false;
    const base_rowid = base_rowid_opt orelse return false; // Tombstoned entry = no row exists

    const stmt = try stmts.getOrPrepare(&stmts.row_exists_base_stmt, @ptrCast(&stmts.sql_row_exists_base));

    _ = api.bind_int64(stmt, 1, base_rowid);

    return api.step(stmt) == api.SQLITE_ROW;
}

/// Delete row from base table by pks table key using cached statement.
/// First looks up base_rowid from pks table, then deletes from base table.
/// Also marks the pks entry as tombstoned (sets base_rowid to NULL).
///
/// This is the cached variant of `deleteFromBaseTable` for use with `TableMergeStmts`.
pub fn deleteFromBaseTableCached(stmts: *TableMergeStmts, pk: i64) MergeError!void {
    // First, get base_rowid from pks table (not cached - uses uncached lookup)
    const base_rowid_opt = getBaseRowidFromPk(stmts.db, stmts.table_name, pk) catch return;
    const base_rowid = base_rowid_opt orelse return; // Already tombstoned, nothing to delete

    // Delete from base table
    const stmt = try stmts.getOrPrepare(&stmts.delete_base_stmt, @ptrCast(&stmts.sql_delete_base));

    _ = api.bind_int64(stmt, 1, base_rowid);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }

    // Mark pks entry as tombstoned (not cached - infrequent operation)
    var buf: [512]u8 = undefined;
    const tombstone_sql = std.fmt.bufPrintZ(&buf, "UPDATE \"{s}__crsql_pks\" SET base_rowid = NULL WHERE __crsql_key = ?", .{stmts.table_name}) catch return MergeError.BufferOverflow;

    var tombstone_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(stmts.db, tombstone_sql, -1, &tombstone_stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(tombstone_stmt);

    _ = api.bind_int64(tombstone_stmt, 1, pk);

    const tombstone_rc = api.step(tombstone_stmt);
    if (tombstone_rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Drop all clock entries except sentinel (-1) using cached statement.
///
/// This is the cached variant of `dropNonSentinelClocks` for use with `TableMergeStmts`.
pub fn dropNonSentinelClocksCached(stmts: *TableMergeStmts, pk: i64) MergeError!void {
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
