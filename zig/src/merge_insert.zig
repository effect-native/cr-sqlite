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

/// Error set for merge operations
pub const MergeError = error{
    SqliteError,
    BufferOverflow,
    DecodeError,
    NoRows,
};

// =============================================================================
// Per-Table Statement Cache
// =============================================================================

/// Per-table cached statements for merge operations.
///
/// During sync, the same SQL patterns are executed thousands of times per table,
/// differing only in bound parameters. This struct caches the prepared statements
/// for a single table, allowing reuse across multiple merge operations.
///
/// Usage:
/// ```zig
/// var stmts = TableMergeStmts.init(db, "my_table") catch return error;
/// defer stmts.deinit();
///
/// // Use cached functions
/// const cl = try getLocalClCached(&stmts, pk);
/// try setWinnerClockCached(&stmts, pk, col_name, ...);
/// ```
pub const TableMergeStmts = struct {
    db: ?*api.sqlite3,

    /// Table name (borrowed reference, must outlive this struct)
    table_name: []const u8,

    // Cached statements - null until first use, then reused

    /// SELECT col_version FROM "{table}__crsql_clock" WHERE pk = ? AND col_name = '-1'
    get_cl_stmt: ?*api.sqlite3_stmt = null,

    /// SELECT 1 FROM "{table}__crsql_clock" WHERE pk = ? LIMIT 1
    row_exists_stmt: ?*api.sqlite3_stmt = null,

    /// SELECT col_version FROM "{table}__crsql_clock" WHERE pk = ? AND col_name = ?
    get_col_version_stmt: ?*api.sqlite3_stmt = null,

    /// INSERT OR REPLACE INTO "{table}__crsql_clock" (...) VALUES (?, ?, ?, ?, ?, ?)
    set_winner_clock_stmt: ?*api.sqlite3_stmt = null,

    /// SELECT pk FROM "{table}__crsql_pks" WHERE pks = ?
    find_pk_stmt: ?*api.sqlite3_stmt = null,

    /// SELECT 1 FROM "{table}" WHERE rowid = ? LIMIT 1
    row_exists_base_stmt: ?*api.sqlite3_stmt = null,

    /// DELETE FROM "{table}" WHERE rowid = ?
    delete_base_stmt: ?*api.sqlite3_stmt = null,

    /// DELETE FROM "{table}__crsql_clock" WHERE pk = ? AND col_name != '-1'
    drop_non_sentinel_stmt: ?*api.sqlite3_stmt = null,

    /// INSERT INTO "{table}__crsql_pks" (pk, pks) VALUES (?, ?)
    insert_pks_stmt: ?*api.sqlite3_stmt = null,

    // SQL buffers for dynamically-generated queries
    // These are built once during init or on first use

    sql_get_cl: [256]u8 = undefined,
    sql_row_exists: [256]u8 = undefined,
    sql_get_col_version: [256]u8 = undefined,
    sql_set_winner_clock: [512]u8 = undefined,
    sql_find_pk: [256]u8 = undefined,
    sql_row_exists_base: [256]u8 = undefined,
    sql_delete_base: [256]u8 = undefined,
    sql_drop_non_sentinel: [256]u8 = undefined,
    sql_insert_pks: [256]u8 = undefined,

    /// Initialize statement cache for a table.
    /// Statements are lazily prepared on first use.
    ///
    /// The table_name slice must remain valid for the lifetime of this struct.
    pub fn init(db: ?*api.sqlite3, table_name: []const u8) MergeError!TableMergeStmts {
        var self = TableMergeStmts{
            .db = db,
            .table_name = table_name,
        };

        // Pre-format SQL strings (they're used repeatedly)
        _ = std.fmt.bufPrintZ(&self.sql_get_cl, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name = '-1'", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_row_exists, "SELECT 1 FROM \"{s}__crsql_clock\" WHERE pk = ? LIMIT 1", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_get_col_version, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name = ?", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_set_winner_clock,
            \\INSERT OR REPLACE INTO "{s}__crsql_clock"
            \\  ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
            \\VALUES (?, ?, ?, ?, ?, ?)
        , .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_find_pk, "SELECT pk FROM \"{s}__crsql_pks\" WHERE pks = ?", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_row_exists_base, "SELECT 1 FROM \"{s}\" WHERE rowid = ? LIMIT 1", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_delete_base, "DELETE FROM \"{s}\" WHERE rowid = ?", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_drop_non_sentinel, "DELETE FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name != '-1'", .{table_name}) catch return MergeError.BufferOverflow;

        _ = std.fmt.bufPrintZ(&self.sql_insert_pks, "INSERT INTO \"{s}__crsql_pks\" (pk, pks) VALUES (?, ?)", .{table_name}) catch return MergeError.BufferOverflow;

        return self;
    }

    /// Release all cached statements.
    pub fn deinit(self: *TableMergeStmts) void {
        if (self.get_cl_stmt) |stmt| _ = api.finalize(stmt);
        if (self.row_exists_stmt) |stmt| _ = api.finalize(stmt);
        if (self.get_col_version_stmt) |stmt| _ = api.finalize(stmt);
        if (self.set_winner_clock_stmt) |stmt| _ = api.finalize(stmt);
        if (self.find_pk_stmt) |stmt| _ = api.finalize(stmt);
        if (self.row_exists_base_stmt) |stmt| _ = api.finalize(stmt);
        if (self.delete_base_stmt) |stmt| _ = api.finalize(stmt);
        if (self.drop_non_sentinel_stmt) |stmt| _ = api.finalize(stmt);
        if (self.insert_pks_stmt) |stmt| _ = api.finalize(stmt);

        self.get_cl_stmt = null;
        self.row_exists_stmt = null;
        self.get_col_version_stmt = null;
        self.set_winner_clock_stmt = null;
        self.find_pk_stmt = null;
        self.row_exists_base_stmt = null;
        self.delete_base_stmt = null;
        self.drop_non_sentinel_stmt = null;
        self.insert_pks_stmt = null;
    }

    /// Helper to get or prepare a statement.
    fn getOrPrepare(self: *TableMergeStmts, slot: *?*api.sqlite3_stmt, sql: [*:0]const u8) MergeError!*api.sqlite3_stmt {
        if (slot.*) |existing| {
            // Reset for reuse
            _ = api.reset(existing);
            return existing;
        }

        var stmt: ?*api.sqlite3_stmt = null;
        if (api.prepare_v2(self.db, sql, -1, &stmt, null) != api.SQLITE_OK) {
            return MergeError.SqliteError;
        }

        slot.* = stmt;
        return stmt.?;
    }
};

/// Get the local causal length (cl) for a row.
/// Returns 0 if no local row exists.
///
/// Query: SELECT col_version FROM "{table}__crsql_clock" WHERE pk = ? AND col_name = '-1'
/// If no sentinel exists, check if any clock entry exists (return 1 if so, 0 otherwise)
pub fn getLocalCl(db: ?*api.sqlite3, table_name: []const u8, pk: i64) MergeError!i64 {
    var buf: [512]u8 = undefined;

    // First try to get sentinel col_version (which stores cl)
    const sql = std.fmt.bufPrintZ(&buf, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name = '-1'", .{table_name}) catch return MergeError.BufferOverflow;

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
    const exists_sql = std.fmt.bufPrintZ(&exists_buf, "SELECT 1 FROM \"{s}__crsql_clock\" WHERE pk = ? LIMIT 1", .{table_name}) catch return MergeError.BufferOverflow;

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

/// Get the local col_version for a specific column.
/// Returns 0 if no local entry exists.
pub fn getLocalColVersion(db: ?*api.sqlite3, table_name: []const u8, pk: i64, col_name: []const u8) MergeError!i64 {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT col_version FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name = ?", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return 0;
}

/// Update base table column value.
/// Uses UPDATE with rowid lookup.
pub fn updateBaseTableColumn(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
    value: ?*api.sqlite3_value,
) MergeError!void {
    var buf: [1024]u8 = undefined;

    // For MVP, assume single integer PK matching rowid
    const sql = std.fmt.bufPrintZ(&buf, "UPDATE \"{s}\" SET \"{s}\" = ? WHERE rowid = ?", .{ table_name, col_name }) catch return MergeError.BufferOverflow;

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
    _ = api.bind_int64(stmt, 2, pk);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Update clock table entry for a column.
pub fn setWinnerClock(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
    col_version: i64,
    db_version: i64,
    site_id_blob: ?[*]const u8,
    site_id_len: usize,
    seq: i64,
) MergeError!void {
    var buf: [1024]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\  ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\VALUES (?, ?, ?, ?, ?, ?)
    , .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, col_version);
    _ = api.bind_int64(stmt, 4, db_version);

    if (site_id_blob) |sid| {
        _ = api.bind_blob(stmt, 5, sid, @intCast(site_id_len), api.getTransientDestructor());
    } else {
        _ = api.bind_int64(stmt, 5, 0); // Local site_id = 0
    }

    _ = api.bind_int64(stmt, 6, seq);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Find the pk (rowid) from a packed PK blob.
/// Queries the __crsql_pks table to find matching row.
/// For MVP, this does a reverse lookup: find pk where pks blob matches.
pub fn findPkFromBlob(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk_blob: [*]const u8,
    pk_blob_len: usize,
) MergeError!i64 {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT pk FROM \"{s}__crsql_pks\" WHERE pks = ?", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_blob(stmt, 1, pk_blob, @intCast(pk_blob_len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return MergeError.NoRows;
}

/// Delete row from base table by rowid.
/// Used when merging a remote delete that wins over local state.
pub fn deleteFromBaseTable(db: ?*api.sqlite3, table_name: []const u8, pk: i64) MergeError!void {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DELETE FROM \"{s}\" WHERE rowid = ?", .{table_name}) catch return MergeError.BufferOverflow;

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

/// Check if a row exists in the base table by rowid.
/// Returns true if the row exists, false otherwise.
pub fn rowExistsInBaseTable(db: ?*api.sqlite3, table_name: []const u8, pk: i64) MergeError!bool {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT 1 FROM \"{s}\" WHERE rowid = ? LIMIT 1", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);

    return api.step(stmt) == api.SQLITE_ROW;
}

/// Drop all clock entries except sentinel (-1).
/// Used when merging a remote delete - removes column clock entries but keeps the sentinel.
pub fn dropNonSentinelClocks(db: ?*api.sqlite3, table_name: []const u8, pk: i64) MergeError!void {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DELETE FROM \"{s}__crsql_clock\" WHERE pk = ? AND col_name != '-1'", .{table_name}) catch return MergeError.BufferOverflow;

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

/// Get the primary key column name for a table.
/// For MVP, assumes single-column PRIMARY KEY.
/// Returns the PK column name, or null if not found.
fn getPkColumnName(db: ?*api.sqlite3, table_name: []const u8) MergeError!?[64]u8 {
    var pragma_buf: [256]u8 = undefined;
    const pragma_sql = std.fmt.bufPrintZ(&pragma_buf, "PRAGMA table_info(\"{s}\")", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, pragma_sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    // PRAGMA table_info returns: cid, name, type, notnull, dflt_value, pk
    // Column 1 is name, column 5 is pk (0 = not PK, 1+ = PK index)
    while (api.step(stmt) == api.SQLITE_ROW) {
        const pk_val = api.column_int64(stmt, 5);
        if (pk_val > 0) {
            // This is a PK column
            const name_ptr = api.column_text(stmt, 1) orelse continue;
            const name_slice = std.mem.span(name_ptr);
            if (name_slice.len >= 64) {
                return MergeError.BufferOverflow;
            }
            var result: [64]u8 = undefined;
            @memcpy(result[0..name_slice.len], name_slice);
            result[name_slice.len] = 0; // null-terminate
            return result;
        }
    }

    return null;
}

/// Insert a new row into base table with a single column value.
/// For MVP, assumes single-column INTEGER PRIMARY KEY that matches rowid.
/// Decodes the first value from pk_blob to get the PK value to insert.
/// Returns the new rowid.
pub fn insertIntoBaseTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    col_name: []const u8,
    value: ?*api.sqlite3_value,
    pk_blob: [*]const u8,
    pk_blob_len: usize,
) MergeError!i64 {
    // Decode the PK blob to get the PK value
    // For MVP, assume single integer PK
    const pk_slice = pk_blob[0..pk_blob_len];
    const values = codec.unpack(std.heap.page_allocator, pk_slice) catch return MergeError.DecodeError;
    defer {
        for (values) |v| {
            switch (v) {
                .Text => |s| std.heap.page_allocator.free(s),
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

    // Return the pk_int as the rowid (since we explicitly set it)
    return pk_int;
}

/// Insert into __crsql_pks table mapping pk (rowid) to packed pks blob.
pub fn insertIntoPksTable(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    pks_blob: [*]const u8,
    pks_len: usize,
) MergeError!void {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "INSERT INTO \"{s}__crsql_pks\" (pk, pks) VALUES (?, ?)", .{table_name}) catch return MergeError.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return MergeError.SqliteError;
    }
    defer _ = api.finalize(stmt);

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_blob(stmt, 2, pks_blob, @intCast(pks_len), api.getTransientDestructor());

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Insert a row for resurrection using existing pk (rowid).
/// Used when a previously deleted row is being resurrected.
/// The pks entry already exists, we just need to recreate the base table row.
pub fn insertRowForResurrection(
    db: ?*api.sqlite3,
    table_name: []const u8,
    pk: i64,
    col_name: []const u8,
    value: ?*api.sqlite3_value,
) MergeError!void {
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

    // Bind the pk value
    _ = api.bind_int64(stmt, 1, pk);

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

// =============================================================================
// Cached Variants (Hot Path Optimization)
// =============================================================================

/// Get the local causal length (cl) for a row using cached statement.
/// Returns 0 if no local row exists.
///
/// This is the cached variant of `getLocalCl` for use with `TableMergeStmts`.
pub fn getLocalClCached(stmts: *TableMergeStmts, pk: i64) MergeError!i64 {
    const stmt = try stmts.getOrPrepare(&stmts.get_cl_stmt, @ptrCast(&stmts.sql_get_cl));

    _ = api.bind_int64(stmt, 1, pk);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    // No sentinel - check if row exists at all using cached statement
    const exists_stmt = try stmts.getOrPrepare(&stmts.row_exists_stmt, @ptrCast(&stmts.sql_row_exists));
    _ = api.bind_int64(exists_stmt, 1, pk);

    if (api.step(exists_stmt) == api.SQLITE_ROW) {
        return 1; // Row exists but no explicit CL, default to 1 (created)
    }

    return 0; // No local row
}

/// Get the local col_version for a specific column using cached statement.
/// Returns 0 if no local entry exists.
///
/// This is the cached variant of `getLocalColVersion` for use with `TableMergeStmts`.
pub fn getLocalColVersionCached(stmts: *TableMergeStmts, pk: i64, col_name: []const u8) MergeError!i64 {
    const stmt = try stmts.getOrPrepare(&stmts.get_col_version_stmt, @ptrCast(&stmts.sql_get_col_version));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    return 0;
}

/// Update clock table entry for a column using cached statement.
///
/// This is the cached variant of `setWinnerClock` for use with `TableMergeStmts`.
pub fn setWinnerClockCached(
    stmts: *TableMergeStmts,
    pk: i64,
    col_name: []const u8,
    col_version: i64,
    db_version: i64,
    site_id_blob: ?[*]const u8,
    site_id_len: usize,
    seq: i64,
) MergeError!void {
    const stmt = try stmts.getOrPrepare(&stmts.set_winner_clock_stmt, @ptrCast(&stmts.sql_set_winner_clock));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_text(stmt, 2, col_name.ptr, @intCast(col_name.len), api.getTransientDestructor());
    _ = api.bind_int64(stmt, 3, col_version);
    _ = api.bind_int64(stmt, 4, db_version);

    if (site_id_blob) |sid| {
        _ = api.bind_blob(stmt, 5, sid, @intCast(site_id_len), api.getTransientDestructor());
    } else {
        _ = api.bind_int64(stmt, 5, 0); // Local site_id = 0
    }

    _ = api.bind_int64(stmt, 6, seq);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

/// Find the pk (rowid) from a packed PK blob using cached statement.
///
/// This is the cached variant of `findPkFromBlob` for use with `TableMergeStmts`.
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

/// Check if a row exists in the base table by rowid using cached statement.
///
/// This is the cached variant of `rowExistsInBaseTable` for use with `TableMergeStmts`.
pub fn rowExistsInBaseTableCached(stmts: *TableMergeStmts, pk: i64) MergeError!bool {
    const stmt = try stmts.getOrPrepare(&stmts.row_exists_base_stmt, @ptrCast(&stmts.sql_row_exists_base));

    _ = api.bind_int64(stmt, 1, pk);

    return api.step(stmt) == api.SQLITE_ROW;
}

/// Delete row from base table by rowid using cached statement.
///
/// This is the cached variant of `deleteFromBaseTable` for use with `TableMergeStmts`.
pub fn deleteFromBaseTableCached(stmts: *TableMergeStmts, pk: i64) MergeError!void {
    const stmt = try stmts.getOrPrepare(&stmts.delete_base_stmt, @ptrCast(&stmts.sql_delete_base));

    _ = api.bind_int64(stmt, 1, pk);

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
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

/// Insert into __crsql_pks table using cached statement.
///
/// This is the cached variant of `insertIntoPksTable` for use with `TableMergeStmts`.
pub fn insertIntoPksTableCached(
    stmts: *TableMergeStmts,
    pk: i64,
    pks_blob: [*]const u8,
    pks_len: usize,
) MergeError!void {
    const stmt = try stmts.getOrPrepare(&stmts.insert_pks_stmt, @ptrCast(&stmts.sql_insert_pks));

    _ = api.bind_int64(stmt, 1, pk);
    _ = api.bind_blob(stmt, 2, pks_blob, @intCast(pks_len), api.getTransientDestructor());

    const rc = api.step(stmt);
    if (rc != api.SQLITE_DONE) {
        return MergeError.SqliteError;
    }
}

// =============================================================================
// Tests
// =============================================================================

test "module compiles" {
    // Basic compile test - uncached functions
    _ = getLocalCl;
    _ = getLocalColVersion;
    _ = updateBaseTableColumn;
    _ = setWinnerClock;
    _ = findPkFromBlob;
    _ = deleteFromBaseTable;
    _ = rowExistsInBaseTable;
    _ = dropNonSentinelClocks;
    _ = insertIntoBaseTable;
    _ = insertIntoPksTable;
    _ = insertRowForResurrection;

    // Cached variants
    _ = getLocalClCached;
    _ = getLocalColVersionCached;
    _ = setWinnerClockCached;
    _ = findPkFromBlobCached;
    _ = rowExistsInBaseTableCached;
    _ = deleteFromBaseTableCached;
    _ = dropNonSentinelClocksCached;
    _ = insertIntoPksTableCached;
}

test "TableMergeStmts struct has expected fields" {
    // Verify the struct layout matches what we designed
    const stmts = TableMergeStmts{
        .db = null,
        .table_name = "test",
    };
    try std.testing.expectEqual(@as(?*api.sqlite3, null), stmts.db);
    try std.testing.expectEqualStrings("test", stmts.table_name);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), stmts.get_cl_stmt);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), stmts.get_col_version_stmt);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), stmts.set_winner_clock_stmt);
    try std.testing.expectEqual(@as(?*api.sqlite3_stmt, null), stmts.find_pk_stmt);
}
