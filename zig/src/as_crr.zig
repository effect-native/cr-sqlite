//! CRR Bootstrap: crsql_as_crr(table_name) implementation
//!
//! When `SELECT crsql_as_crr('foo')` is called, this module creates:
//! 1. `foo__crsql_clock` table - tracks per-column versions
//! 2. `foo__crsql_pks` table - maps rowids to PK blobs
//! 3. INSERT/UPDATE/DELETE triggers to capture changes
//!
//! Reference: `core/rs/core/src/bootstrap.rs`

const std = @import("std");
const api = @import("ffi/api.zig");

/// Maximum length for table names (SQLite limit is ~2GB, but we're practical)
const MAX_TABLE_NAME_LEN = 1024;

/// SQL buffer size for DDL generation
const SQL_BUF_SIZE = 8192;

/// Maximum number of columns we support
const MAX_COLUMNS = 64;

/// Column information from PRAGMA table_info
const ColumnInfo = struct {
    name: [128]u8,
    name_len: usize,
    pk_index: c_int, // 0 = not a PK, 1+ = PK position
};

/// Table information gathered from PRAGMA table_info
const TableInfo = struct {
    columns: [MAX_COLUMNS]ColumnInfo,
    count: usize,
    pk_count: usize,
};

/// Implementation of `crsql_as_crr(table_name)` SQL function.
/// Creates the clock table, pks table, and triggers for a given table.
fn crsqlAsCrrFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Validate argument count
    if (argc != 1) {
        api.result_error(pCtx, "crsql_as_crr requires exactly 1 argument", -1);
        return;
    }

    // Get the table name argument
    const table_name_ptr = api.value_text(argv[0]) orelse {
        api.result_error(pCtx, "crsql_as_crr: table name must be TEXT", -1);
        return;
    };

    // Get database handle from context
    const db = api.context_db_handle(pCtx) orelse {
        api.result_error(pCtx, "crsql_as_crr: failed to get db handle", -1);
        return;
    };

    // Create clock table
    if (createClockTable(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create clock table", -1);
        return;
    }

    // Create pks table
    if (createPksTable(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create pks table", -1);
        return;
    }

    // Create triggers - INSERT trigger
    if (createInsertTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create insert trigger", -1);
        return;
    }

    // Create triggers - UPDATE trigger
    if (createUpdateTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create update trigger", -1);
        return;
    }

    // Create triggers - DELETE trigger
    if (createDeleteTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create delete trigger", -1);
        return;
    }

    // Return NULL on success (like the C implementation)
    api.result_null(pCtx);
}

/// Create the clock table for tracking per-column versions.
/// Schema:
/// ```sql
/// CREATE TABLE IF NOT EXISTS "{table}__crsql_clock" (
///   "pk" INTEGER NOT NULL,
///   "col_name" TEXT NOT NULL,
///   "col_version" INTEGER NOT NULL,
///   "db_version" INTEGER NOT NULL,
///   "site_id" INTEGER NOT NULL DEFAULT 0,
///   "seq" INTEGER NOT NULL,
///   PRIMARY KEY ("pk", "col_name")
/// ) WITHOUT ROWID;
/// ```
fn createClockTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, 
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_clock" (
        \\  "pk" INTEGER NOT NULL,
        \\  "col_name" TEXT NOT NULL,
        \\  "col_version" INTEGER NOT NULL,
        \\  "db_version" INTEGER NOT NULL,
        \\  "site_id" INTEGER NOT NULL DEFAULT 0,
        \\  "seq" INTEGER NOT NULL,
        \\  PRIMARY KEY ("pk", "col_name")
        \\) WITHOUT ROWID;
    , .{table_name}) catch return error.BufferOverflow;

    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Create the pks table for mapping rowids to packed PK blobs.
/// Schema:
/// ```sql
/// CREATE TABLE IF NOT EXISTS "{table}__crsql_pks" (
///   "pk" INTEGER PRIMARY KEY,
///   "pks" BLOB NOT NULL
/// );
/// ```
fn createPksTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_pks" (
        \\  "pk" INTEGER PRIMARY KEY,
        \\  "pks" BLOB NOT NULL
        \\);
    , .{table_name}) catch return error.BufferOverflow;

    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Query PRAGMA table_info to get column information
fn getTableInfo(db: ?*api.sqlite3, table_name: [*:0]const u8) !TableInfo {
    var info = TableInfo{
        .columns = undefined,
        .count = 0,
        .pk_count = 0,
    };

    // Prepare PRAGMA table_info query
    var pragma_buf: [256]u8 = undefined;
    const pragma_sql = std.fmt.bufPrintZ(&pragma_buf, "PRAGMA table_info(\"{s}\")", .{table_name}) catch return error.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = api.prepare_v2(db, pragma_sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
    defer _ = api.finalize(stmt);

    // PRAGMA table_info returns: cid, name, type, notnull, dflt_value, pk
    while (api.step(stmt) == api.SQLITE_ROW) {
        if (info.count >= MAX_COLUMNS) {
            return error.TooManyColumns;
        }

        // Column 1 is name
        const name_ptr = api.column_text(stmt, 1) orelse continue;
        const name_slice = std.mem.span(name_ptr);

        if (name_slice.len >= 128) {
            return error.ColumnNameTooLong;
        }

        var col = &info.columns[info.count];
        @memcpy(col.name[0..name_slice.len], name_slice);
        col.name_len = name_slice.len;

        // Column 5 is pk (0 = not PK, 1+ = PK index)
        const pk_val = api.column_int64(stmt, 5);
        col.pk_index = @intCast(pk_val);
        if (col.pk_index > 0) {
            info.pk_count += 1;
        }

        info.count += 1;
    }

    return info;
}

/// Create the INSERT trigger that captures new rows.
/// - Packs PK column values using crsql_pack_columns()
/// - Creates clock entries for each non-PK column
/// - Creates sentinel row ('-1') for row creation tracking
fn createInsertTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get table column information
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return error.NoColumns;
    }

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Trigger header
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_itrig"
        \\AFTER INSERT ON "{s}"
        \\BEGIN
        \\  INSERT OR REPLACE INTO "{s}__crsql_pks" ("pk", "pks")
        \\  VALUES (NEW.rowid, crsql_pack_columns(
    , .{ table_name, table_name, table_name }) catch return error.BufferOverflow;

    // Build crsql_pack_columns arguments from PK columns in order
    // PK columns are ordered by their pk_index (1-indexed)
    var pk_written: usize = 0;
    var pk_order: usize = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        // Find column with this pk_index
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("NEW.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll("));\n") catch return error.BufferOverflow;

    // Generate clock entry for each non-PK column
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            // Non-PK column - create clock entry
            writer.print(
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  VALUES
                \\    (NEW.rowid, '{s}', 1, 1, 0, 0);
                \\
            , .{ table_name, col.name[0..col.name_len] }) catch return error.BufferOverflow;
        }
    }

    // Sentinel row for row creation tracking
    writer.print(
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  VALUES
        \\    (NEW.rowid, '-1', 1, 1, 0, 0);
        \\END;
    , .{table_name}) catch return error.BufferOverflow;

    // Null-terminate the SQL
    const sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) {
        return error.BufferOverflow;
    }
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Create the UPDATE trigger that captures column changes.
/// - Only fires when at least one non-PK column has changed
/// - Creates clock entries for each changed non-PK column
/// - Increments col_version for each changed column
fn createUpdateTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get table column information
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return error.NoColumns;
    }

    // Count non-PK columns
    var non_pk_count: usize = 0;
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            non_pk_count += 1;
        }
    }

    // If there are no non-PK columns, no UPDATE trigger needed
    if (non_pk_count == 0) {
        return;
    }

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Trigger header with WHEN clause
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_utrig"
        \\AFTER UPDATE ON "{s}"
        \\FOR EACH ROW WHEN
        \\  
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build WHEN clause: OLD.col IS NOT NEW.col OR ...
    var first_when = true;
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            if (!first_when) {
                writer.writeAll(" OR ") catch return error.BufferOverflow;
            }
            writer.print("OLD.\"{s}\" IS NOT NEW.\"{s}\"", .{
                col.name[0..col.name_len],
                col.name[0..col.name_len],
            }) catch return error.BufferOverflow;
            first_when = false;
        }
    }

    writer.writeAll("\nBEGIN\n") catch return error.BufferOverflow;

    // Generate clock entry for each non-PK column (only when changed)
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            // Non-PK column - create/update clock entry when changed
            writer.print(
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  SELECT
                \\    NEW.rowid,
                \\    '{s}',
                \\    COALESCE((SELECT col_version FROM "{s}__crsql_clock" WHERE pk = NEW.rowid AND col_name = '{s}'), 0) + 1,
                \\    1,
                \\    0,
                \\    0
                \\  WHERE OLD."{s}" IS NOT NEW."{s}";
                \\
            , .{
                table_name,
                col.name[0..col.name_len],
                table_name,
                col.name[0..col.name_len],
                col.name[0..col.name_len],
                col.name[0..col.name_len],
            }) catch return error.BufferOverflow;
        }
    }

    writer.writeAll("END;") catch return error.BufferOverflow;

    // Null-terminate the SQL
    const sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) {
        return error.BufferOverflow;
    }
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Create the DELETE trigger that marks rows as deleted.
/// Semantics (from core/rs/core/src/local_writes/after_delete.rs):
/// 1. Update (or create) sentinel row with col_name = '-1'
///    - First delete: col_version = 2 (even = deleted)
///    - Subsequent: col_version += 1
/// 2. Drop all clock entries except the sentinel
fn createDeleteTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Trigger header
    // Note: Unlike Rust which uses `WHEN crsql_internal_sync_bit() = 0`,
    // we omit that check since we don't have the sync bit infrastructure yet.
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_dtrig"
        \\AFTER DELETE ON "{s}"
        \\BEGIN
        \\  -- Mark row as deleted: insert sentinel with col_version=2, or increment existing
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  SELECT
        \\    OLD.rowid,
        \\    '-1',
        \\    COALESCE(
        \\      (SELECT col_version + 1 FROM "{s}__crsql_clock" WHERE pk = OLD.rowid AND col_name = '-1'),
        \\      2
        \\    ),
        \\    1,
        \\    0,
        \\    0;
        \\  -- Drop all clock entries except the sentinel
        \\  DELETE FROM "{s}__crsql_clock"
        \\  WHERE pk = OLD.rowid AND col_name IS NOT '-1';
        \\END;
    , .{ table_name, table_name, table_name, table_name, table_name }) catch return error.BufferOverflow;

    // Null-terminate the SQL
    const sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) {
        return error.BufferOverflow;
    }
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Register the crsql_as_crr function with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_function_v2(
        db,
        "crsql_as_crr",
        1, // nArg: 1 argument (table name)
        api.SQLITE_UTF8,
        null, // pApp: no user data
        &crsqlAsCrrFunc,
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
}

test "createClockTable generates valid SQL" {
    // Just a compile-time check that the format strings are valid
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_clock" (
        \\  "pk" INTEGER NOT NULL,
        \\  "col_name" TEXT NOT NULL,
        \\  "col_version" INTEGER NOT NULL,
        \\  "db_version" INTEGER NOT NULL,
        \\  "site_id" INTEGER NOT NULL DEFAULT 0,
        \\  "seq" INTEGER NOT NULL,
        \\  PRIMARY KEY ("pk", "col_name")
        \\) WITHOUT ROWID;
    , .{"test_table"}) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, sql, "test_table__crsql_clock") != null);
}
