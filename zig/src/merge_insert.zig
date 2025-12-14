//! Merge Insert SQL Helpers
//!
//! These functions execute the SQL statements needed for merge operations.
//! They are called from changes_vtab.changesUpdate.

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
                // bind_double not wrapped yet, use bind_int64 with bits
                // TODO: Add bind_double to api.zig
                _ = api.bind_null(stmt, 1);
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

// =============================================================================
// Tests
// =============================================================================

test "module compiles" {
    // Basic compile test
    _ = getLocalCl;
    _ = getLocalColVersion;
    _ = updateBaseTableColumn;
    _ = setWinnerClock;
    _ = findPkFromBlob;
}
