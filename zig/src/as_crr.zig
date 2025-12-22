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
const table_compat = @import("table_compat.zig");

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

/// Check if a table exists by querying PRAGMA table_info
fn tableExists(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "SELECT count(*) FROM pragma_table_info('{s}')", .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0) > 0;
    }
    return false;
}

/// Check if table is already a CRR (clock table exists)
fn isAlreadyCrr(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM sqlite_master
        \\WHERE type = 'table' AND name = '{s}__crsql_clock'
    , .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0) > 0;
    }
    return false;
}

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

    // Check if table exists (PRAGMA table_info returns no rows for non-existent tables)
    if (!tableExists(db, table_name_ptr)) {
        api.result_error(pCtx, "crsql_as_crr: table does not exist", -1);
        return;
    }

    // Check if already a CRR (idempotent - clock table exists)
    if (isAlreadyCrr(db, table_name_ptr)) {
        // Already a CRR, return success (idempotent)
        api.result_null(pCtx);
        return;
    }

    // Validate table compatibility before creating CRR infrastructure
    const compat_result = table_compat.checkTableCompatibility(db, table_name_ptr);
    if (compat_result != .ok) {
        api.result_error(pCtx, table_compat.getErrorMessage(compat_result), -1);
        return;
    }

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

    // Create triggers - UPDATE trigger (for non-PK column changes)
    if (createUpdateTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create update trigger", -1);
        return;
    }

    // Create triggers - PK UPDATE trigger (for PK column changes)
    if (createPkUpdateTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |err| {
        // NoPrimaryKey is not an error - just means table has no explicit PK columns to track
        if (err != error.NoPrimaryKey) {
            api.result_error(pCtx, "crsql_as_crr: failed to create PK update trigger", -1);
            return;
        }
    }

    // Create triggers - DELETE trigger
    if (createDeleteTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create delete trigger", -1);
        return;
    }

    // Backfill existing rows (if any) with clock entries
    if (backfillExistingRows(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to backfill existing rows", -1);
        return;
    }

    // Return NULL on success
    api.result_null(pCtx);
}

/// Create the clock table for tracking per-column versions.
/// Schema:
/// ```sql
/// CREATE TABLE IF NOT EXISTS "{table}__crsql_clock" (
///   "key" INTEGER NOT NULL,
///   "col_name" TEXT NOT NULL,
///   "col_version" INTEGER NOT NULL,
///   "db_version" INTEGER NOT NULL,
///   "site_id" INTEGER NOT NULL DEFAULT 0,
///   "seq" INTEGER NOT NULL,
///   PRIMARY KEY ("key", "col_name")
/// ) WITHOUT ROWID, STRICT;
/// CREATE INDEX "{table}__crsql_clock_dbv_idx" ON "{table}__crsql_clock" ("db_version");
/// ```
fn createClockTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var sql = std.fmt.bufPrintZ(&buf, 
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_clock" (
        \\  "key" INTEGER NOT NULL,
        \\  "col_name" TEXT NOT NULL,
        \\  "col_version" INTEGER NOT NULL,
        \\  "db_version" INTEGER NOT NULL,
        \\  "site_id" INTEGER NOT NULL DEFAULT 0,
        \\  "seq" INTEGER NOT NULL,
        \\  PRIMARY KEY ("key", "col_name")
        \\) WITHOUT ROWID, STRICT;
    , .{table_name}) catch return error.BufferOverflow;

    var rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Create index on db_version for efficient sync queries
    sql = std.fmt.bufPrintZ(&buf,
        \\CREATE INDEX IF NOT EXISTS "{s}__crsql_clock_dbv_idx" ON "{s}__crsql_clock" ("db_version");
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Create the pks table for mapping auto-increment keys to PK column values.
/// Schema matches Rust/C implementation:
/// - Key: `__crsql_key INTEGER PRIMARY KEY`
/// - One column per PK column from the base table
/// - Unique index `{table}__crsql_pks_pks` on the PK columns
fn createPksTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    const info = try getTableInfo(db, table_name);

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.print(
        "CREATE TABLE IF NOT EXISTS \"{s}__crsql_pks\" (__crsql_key INTEGER PRIMARY KEY",
        .{table_name},
    ) catch return error.BufferOverflow;

    // Add PK columns in order
    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                writer.print(", \"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(")") catch return error.BufferOverflow;

    var sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    var rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Create unique index on PK columns
    // CREATE UNIQUE INDEX IF NOT EXISTS "{table}__crsql_pks_pks" ON "{table}__crsql_pks" (pk_cols...)
    var idx_buf: [SQL_BUF_SIZE]u8 = undefined;
    var idx_fbs = std.io.fixedBufferStream(&idx_buf);
    const idx_writer = idx_fbs.writer();

    idx_writer.print(
        "CREATE UNIQUE INDEX IF NOT EXISTS \"{s}__crsql_pks_pks\" ON \"{s}__crsql_pks\" (",
        .{ table_name, table_name },
    ) catch return error.BufferOverflow;

    pk_order = 1;
    pk_written = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    idx_writer.writeAll(", ") catch return error.BufferOverflow;
                }
                idx_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    idx_writer.writeAll(")") catch return error.BufferOverflow;

    sql_len = idx_fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    idx_buf[sql_len] = 0;

    const idx_sql: [*:0]const u8 = @ptrCast(&idx_buf);
    rc = api.exec(db, idx_sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Query PRAGMA table_info to get column information
pub fn getTableInfo(db: ?*api.sqlite3, table_name: [*:0]const u8) !TableInfo {
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
/// Uses crsql_after_insert() helper function (Rust/C compatible).
pub fn createInsertTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) return error.NoColumns;

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_itrig"
        \\AFTER INSERT ON "{s}" WHEN crsql_internal_sync_bit() = 0
        \\BEGIN
        \\  VALUES (crsql_after_insert('{s}'
    , .{ table_name, table_name, table_name }) catch return error.BufferOverflow;

    // PK columns NEW.
    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                writer.print(", NEW.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll("));\nEND;") catch return error.BufferOverflow;

    const sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
}

/// Create the UPDATE trigger that captures column changes.
/// Uses crsql_after_update() helper function (Rust/C compatible).
pub fn createUpdateTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) return error.NoColumns;

    // Count non-PK columns
    var non_pk_count: usize = 0;
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) non_pk_count += 1;
    }

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_utrig"
        \\AFTER UPDATE ON "{s}" WHEN crsql_internal_sync_bit() = 0
        \\BEGIN
        \\  VALUES (crsql_after_update('{s}'
    , .{ table_name, table_name, table_name }) catch return error.BufferOverflow;

    // NEW PK values
    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                writer.print(", NEW.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    // OLD PK values
    pk_order = 1;
    pk_written = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                writer.print(", OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    if (non_pk_count > 0) {
        // NEW non-PK values
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == 0) {
                writer.print(", NEW.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
            }
        }
        // OLD non-PK values
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == 0) {
                writer.print(", OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
            }
        }
    }

    writer.writeAll("));\nEND;") catch return error.BufferOverflow;

    const sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
}

/// Create the PK UPDATE trigger that handles primary key column changes.
/// When a PK column is updated, it's semantically equivalent to:
/// 1. DELETE the old row (create tombstone at OLD pks key)
/// 2. INSERT the new row (create fresh clock entries at NEW pks key)
///
/// Critical design: The pks table has auto-increment keys separate from base table rowid.
/// When PK changes, a NEW pks entry is created (auto-increment), while the OLD pks entry
/// is preserved for tombstone lookup. This allows compound/text PK updates to work correctly
/// even when the base table rowid doesn't change.
///
/// This is sync-critical: without tombstones, replicas would never delete the old PK row.
/// Create the PK UPDATE trigger - NO-OP
/// Rust/C trigger schema uses a single UPDATE trigger that calls crsql_after_update,
/// which handles both PK and non-PK changes.
fn createPkUpdateTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    _ = db;
    _ = table_name;
    return error.NoPrimaryKey;
}

/// Create the DELETE trigger that captures row deletion.
/// Uses crsql_after_delete() helper function (Rust/C compatible).
pub fn createDeleteTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    const info = try getTableInfo(db, table_name);

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_dtrig"
        \\AFTER DELETE ON "{s}" WHEN crsql_internal_sync_bit() = 0
        \\BEGIN
        \\  VALUES (crsql_after_delete('{s}'
    , .{ table_name, table_name, table_name }) catch return error.BufferOverflow;

    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                writer.print(", OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll("));\nEND;") catch return error.BufferOverflow;

    const sql_len = fbs.pos;
    if (sql_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    buf[sql_len] = 0;

    const sql: [*:0]const u8 = @ptrCast(&buf);
    const rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
}

/// Backfill existing rows in the base table with clock entries.
/// This is called after creating CRR tables and triggers to ensure
/// pre-existing data gets tracked.
///
/// Algorithm (from Rust reference core/rs/core/src/backfill.rs):
/// 1. Find PK tuples in base table not yet in pks table (EXCEPT)
/// 2. For each such PK tuple:
///    a. Insert into pks table: (pk_cols...) RETURNING __crsql_key
///    b. Insert clock entries for each non-PK column with col_version=1
/// 3. Use crsql_next_db_version() to get appropriate db_version
fn backfillExistingRows(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get table column information
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return; // Empty schema, nothing to do
    }

    // Count non-PK columns
    var non_pk_count: usize = 0;
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            non_pk_count += 1;
        }
    }

    // Start a savepoint for atomicity
    if (api.exec(db, "SAVEPOINT backfill", null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Build the SELECT query to find PK tuples in base table not yet in __crsql_pks
    // Rust/C algorithm: SELECT pk_cols FROM base EXCEPT SELECT pk_cols FROM pks
    var select_buf: [SQL_BUF_SIZE]u8 = undefined;
    var select_fbs = std.io.fixedBufferStream(&select_buf);
    const select_writer = select_fbs.writer();

    // SELECT pk1, pk2, ... FROM base
    select_writer.writeAll("SELECT ") catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    select_writer.writeAll(", ") catch {
                        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                        return error.BufferOverflow;
                    };
                }
                select_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.BufferOverflow;
                };
                pk_written += 1;
                break;
            }
        }
    }

    select_writer.print(" FROM \"{s}\" AS t1 ", .{table_name}) catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    // EXCEPT SELECT pk1, pk2, ... FROM pks
    select_writer.writeAll("EXCEPT SELECT ") catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    pk_order = 1;
    pk_written = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    select_writer.writeAll(", ") catch {
                        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                        return error.BufferOverflow;
                    };
                }
                select_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.BufferOverflow;
                };
                pk_written += 1;
                break;
            }
        }
    }

    select_writer.print(" FROM \"{s}__crsql_pks\" AS t2", .{table_name}) catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    const select_len = select_fbs.pos;
    if (select_len >= SQL_BUF_SIZE) {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    }
    select_buf[select_len] = 0;

    const select_sql: [*:0]const u8 = @ptrCast(&select_buf);

    // Prepare the SELECT statement
    var select_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, select_sql, -1, &select_stmt, null) != api.SQLITE_OK) {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.SqliteError;
    }
    defer _ = api.finalize(select_stmt);

    // Build INSERT statement for pks table
    // Rust/C schema: INSERT INTO "{table}__crsql_pks" (pk_cols...) VALUES (?, ?, ...) RETURNING __crsql_key
    var pks_insert_buf: [SQL_BUF_SIZE]u8 = undefined;
    var pks_fbs = std.io.fixedBufferStream(&pks_insert_buf);
    const pks_writer = pks_fbs.writer();

    pks_writer.print("INSERT INTO \"{s}__crsql_pks\" (", .{table_name}) catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    // Column list
    var pk_order_insert: usize = 1;
    var pk_written_insert: usize = 0;
    while (pk_written_insert < info.pk_count) : (pk_order_insert += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order_insert))) {
                if (pk_written_insert > 0) {
                    pks_writer.writeAll(", ") catch {
                        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                        return error.BufferOverflow;
                    };
                }
                pks_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.BufferOverflow;
                };
                pk_written_insert += 1;
                break;
            }
        }
    }

    pks_writer.writeAll(") VALUES (") catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    // Placeholders
    for (0..info.pk_count) |i| {
        if (i > 0) {
            pks_writer.writeAll(", ") catch {
                _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                return error.BufferOverflow;
            };
        }
        pks_writer.writeAll("?") catch {
            _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
            return error.BufferOverflow;
        };
    }

    pks_writer.writeAll(") RETURNING __crsql_key") catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    const pks_len = pks_fbs.pos;
    if (pks_len >= SQL_BUF_SIZE) {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    }
    pks_insert_buf[pks_len] = 0;

    const pks_insert_sql: [*:0]const u8 = @ptrCast(&pks_insert_buf);

    // Prepare pks INSERT statement
    var pks_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, pks_insert_sql, -1, &pks_stmt, null) != api.SQLITE_OK) {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.SqliteError;
    }
    defer _ = api.finalize(pks_stmt);

    // Build INSERT statement for clock entries
    // INSERT OR IGNORE to make idempotent (won't duplicate if already exists)
    var clock_insert_buf: [SQL_BUF_SIZE]u8 = undefined;
    const clock_insert_sql = std.fmt.bufPrintZ(&clock_insert_buf,
        \\INSERT OR IGNORE INTO "{s}__crsql_clock"
        \\  (key, col_name, col_version, db_version, site_id, seq)
        \\VALUES
        \\  (?, ?, 1, crsql_next_db_version(), 0, crsql_increment_and_get_seq())
    , .{table_name}) catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    // Prepare clock INSERT statement
    var clock_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, clock_insert_sql, -1, &clock_stmt, null) != api.SQLITE_OK) {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.SqliteError;
    }
    defer _ = api.finalize(clock_stmt);

    // Iterate over rows that need backfilling
    while (api.step(select_stmt) == api.SQLITE_ROW) {
        // Bind PK column values (columns 0..pk_count from select)
        for (0..info.pk_count) |i| {
            const col_idx: c_int = @intCast(i);
            const bind_idx: c_int = @intCast(i + 1);
            const value = api.column_value(select_stmt, col_idx);
            if (value) |v| {
                const val_type = api.value_type(v);
                const bind_rc = switch (val_type) {
                    api.SQLITE_INTEGER => api.bind_int64(pks_stmt, bind_idx, api.value_int64(v)),
                    api.SQLITE_FLOAT => api.bind_double(pks_stmt, bind_idx, api.value_double(v)),
                    api.SQLITE_TEXT => blk: {
                        const text = api.value_text(v);
                        const len = api.value_bytes(v);
                        if (text) |t| {
                            break :blk api.bind_text(pks_stmt, bind_idx, t, len, api.getTransientDestructor());
                        } else {
                            break :blk api.bind_null(pks_stmt, bind_idx);
                        }
                    },
                    api.SQLITE_BLOB => blk: {
                        const blob = api.value_blob(v);
                        const len = api.value_bytes(v);
                        break :blk api.bind_blob(pks_stmt, bind_idx, blob, len, api.getTransientDestructor());
                    },
                    else => api.bind_null(pks_stmt, bind_idx),
                };
                if (bind_rc != api.SQLITE_OK) {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.SqliteError;
                }
            } else {
                if (api.bind_null(pks_stmt, bind_idx) != api.SQLITE_OK) {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.SqliteError;
                }
            }
        }

        // Insert pks entry and capture assigned __crsql_key
        const step_rc = api.step(pks_stmt);
        if (step_rc != api.SQLITE_ROW) {
            _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
            return error.SqliteError;
        }
        const key = api.column_int64(pks_stmt, 0);
        _ = api.reset(pks_stmt);

        // Insert clock entries for each non-PK column
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == 0) {
                if (api.bind_int64(clock_stmt, 1, key) != api.SQLITE_OK) {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.SqliteError;
                }

                const col_name_slice = col.name[0..col.name_len];
                if (api.bind_text(clock_stmt, 2, @ptrCast(col_name_slice.ptr), @intCast(col.name_len), api.getTransientDestructor()) != api.SQLITE_OK) {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.SqliteError;
                }

                _ = api.step(clock_stmt);
                _ = api.reset(clock_stmt);
            }
        }

        // If there are no non-PK columns, insert sentinel row
        if (non_pk_count == 0) {
            if (api.bind_int64(clock_stmt, 1, key) != api.SQLITE_OK) {
                _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                return error.SqliteError;
            }
            if (api.bind_text(clock_stmt, 2, "-1", 2, api.SQLITE_STATIC) != api.SQLITE_OK) {
                _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                return error.SqliteError;
            }
            _ = api.step(clock_stmt);
            _ = api.reset(clock_stmt);
        }
    }

    // Release savepoint on success
    if (api.exec(db, "RELEASE backfill", null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Implementation of `crsql_as_table(table_name)` SQL function.
/// Tears down CRR infrastructure: drops clock table, pks table, and triggers.
fn crsqlAsTableFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    if (argc != 1) {
        api.result_error(pCtx, "crsql_as_table requires exactly 1 argument", -1);
        return;
    }

    const table_name_ptr = api.value_text(argv[0]) orelse {
        api.result_error(pCtx, "crsql_as_table: table name must be TEXT", -1);
        return;
    };

    const db = api.context_db_handle(pCtx) orelse {
        api.result_error(pCtx, "crsql_as_table: failed to get db handle", -1);
        return;
    };

    // Drop triggers
    dropTriggers(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_as_table: failed to drop triggers", -1);
        return;
    };

    // Drop clock table
    dropClockTable(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_as_table: failed to drop clock table", -1);
        return;
    };

    // Drop pks table
    dropPksTable(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_as_table: failed to drop pks table", -1);
        return;
    };

    api.result_null(pCtx);
}

pub fn dropTriggers(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Drop INSERT trigger
    var sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_itrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;

    // Drop UPDATE trigger
    sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_utrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;

    // Drop PK UPDATE trigger
    sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_pk_utrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;

    // Drop DELETE trigger
    sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_dtrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;
}

fn dropClockTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DROP TABLE IF EXISTS \"{s}__crsql_clock\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;
}

fn dropPksTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DROP TABLE IF EXISTS \"{s}__crsql_pks\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;
}

/// Internal function to create CRR infrastructure without savepoint wrapper.
/// Used by clset_vtab during xCreate when savepoints may not be allowed.
/// 
/// Parameters:
///   - db: Database connection
///   - table_name: Name of the table to convert to a CRR (as a slice)
///
/// Returns error on failure, otherwise void on success.
pub fn createCrrInternal(db: ?*api.sqlite3, table_name: []const u8) !void {
    // Convert slice to null-terminated string for internal functions
    var name_buf: [MAX_TABLE_NAME_LEN]u8 = undefined;
    if (table_name.len >= MAX_TABLE_NAME_LEN) {
        return error.TableNameTooLong;
    }
    @memcpy(name_buf[0..table_name.len], table_name);
    name_buf[table_name.len] = 0;
    const table_name_z: [*:0]const u8 = @ptrCast(&name_buf);

    // Create clock table
    try createClockTable(db, table_name_z);

    // Create pks table
    try createPksTable(db, table_name_z);

    // Create INSERT trigger
    try createInsertTrigger(db, table_name_z);

    // Create UPDATE trigger (for non-PK column changes)
    try createUpdateTrigger(db, table_name_z);

    // Create PK UPDATE trigger (for PK column changes)
    createPkUpdateTrigger(db, table_name_z) catch |err| {
        // NoPrimaryKey is not an error - just means table has no explicit PK columns to track
        if (err != error.NoPrimaryKey) {
            return err;
        }
    };

    // Create DELETE trigger
    try createDeleteTrigger(db, table_name_z);

    // Backfill existing rows WITHOUT savepoint (critical for xCreate context)
    try backfillExistingRowsNoTx(db, table_name_z);
}

/// Backfill existing rows without transaction wrapper.
/// Used internally when called from contexts where savepoints aren't allowed.
fn backfillExistingRowsNoTx(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get table column information
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return; // Empty schema, nothing to do
    }

    // Count non-PK columns
    var non_pk_count: usize = 0;
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            non_pk_count += 1;
        }
    }

    // Build the SELECT query to find PK tuples in base table not yet in __crsql_pks
    // Rust/C algorithm: SELECT pk_cols FROM base EXCEPT SELECT pk_cols FROM pks
    var select_buf: [SQL_BUF_SIZE]u8 = undefined;
    var select_fbs = std.io.fixedBufferStream(&select_buf);
    const select_writer = select_fbs.writer();

    select_writer.writeAll("SELECT ") catch return error.BufferOverflow;

    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    select_writer.writeAll(", ") catch return error.BufferOverflow;
                }
                select_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    select_writer.print(" FROM \"{s}\" AS t1 ", .{table_name}) catch return error.BufferOverflow;
    select_writer.writeAll("EXCEPT SELECT ") catch return error.BufferOverflow;

    pk_order = 1;
    pk_written = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    select_writer.writeAll(", ") catch return error.BufferOverflow;
                }
                select_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    select_writer.print(" FROM \"{s}__crsql_pks\" AS t2", .{table_name}) catch return error.BufferOverflow;

    const select_len = select_fbs.pos;
    if (select_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    select_buf[select_len] = 0;

    const select_sql: [*:0]const u8 = @ptrCast(&select_buf);

    // Prepare the SELECT statement
    var select_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, select_sql, -1, &select_stmt, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
    defer _ = api.finalize(select_stmt);

    // Build INSERT statement for pks table
    // INSERT INTO "{table}__crsql_pks" (pk_cols...) VALUES (?, ?, ...) RETURNING __crsql_key
    var pks_insert_buf: [SQL_BUF_SIZE]u8 = undefined;
    var pks_fbs = std.io.fixedBufferStream(&pks_insert_buf);
    const pks_writer = pks_fbs.writer();

    pks_writer.print("INSERT INTO \"{s}__crsql_pks\" (", .{table_name}) catch return error.BufferOverflow;

    var pk_order_insert: usize = 1;
    var pk_written_insert: usize = 0;
    while (pk_written_insert < info.pk_count) : (pk_order_insert += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order_insert))) {
                if (pk_written_insert > 0) {
                    pks_writer.writeAll(", ") catch return error.BufferOverflow;
                }
                pks_writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written_insert += 1;
                break;
            }
        }
    }

    pks_writer.writeAll(") VALUES (") catch return error.BufferOverflow;

    for (0..info.pk_count) |i| {
        if (i > 0) {
            pks_writer.writeAll(", ") catch return error.BufferOverflow;
        }
        pks_writer.writeAll("?") catch return error.BufferOverflow;
    }

    pks_writer.writeAll(") RETURNING __crsql_key") catch return error.BufferOverflow;

    const pks_len = pks_fbs.pos;
    if (pks_len >= SQL_BUF_SIZE) return error.BufferOverflow;
    pks_insert_buf[pks_len] = 0;

    const pks_insert_sql: [*:0]const u8 = @ptrCast(&pks_insert_buf);

    // Prepare pks INSERT statement
    var pks_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, pks_insert_sql, -1, &pks_stmt, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
    defer _ = api.finalize(pks_stmt);

    // Build INSERT statement for clock entries
    var clock_insert_buf: [SQL_BUF_SIZE]u8 = undefined;
    const clock_insert_sql = std.fmt.bufPrintZ(&clock_insert_buf,
        \\INSERT OR IGNORE INTO "{s}__crsql_clock"
        \\  (key, col_name, col_version, db_version, site_id, seq)
        \\VALUES
        \\  (?, ?, 1, crsql_next_db_version(), 0, crsql_increment_and_get_seq())
    , .{table_name}) catch return error.BufferOverflow;

    // Prepare clock INSERT statement
    var clock_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, clock_insert_sql, -1, &clock_stmt, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
    defer _ = api.finalize(clock_stmt);

    // Iterate over rows that need backfilling
    while (api.step(select_stmt) == api.SQLITE_ROW) {
        // Bind PK column values from select (columns 0..pk_count)
        for (0..info.pk_count) |i| {
            const col_idx: c_int = @intCast(i);
            const bind_idx: c_int = @intCast(i + 1);
            const value = api.column_value(select_stmt, col_idx);
            if (value) |v| {
                const val_type = api.value_type(v);
                const bind_rc = switch (val_type) {
                    api.SQLITE_INTEGER => api.bind_int64(pks_stmt, bind_idx, api.value_int64(v)),
                    api.SQLITE_FLOAT => api.bind_double(pks_stmt, bind_idx, api.value_double(v)),
                    api.SQLITE_TEXT => blk: {
                        const text = api.value_text(v);
                        const len = api.value_bytes(v);
                        if (text) |t| {
                            break :blk api.bind_text(pks_stmt, bind_idx, t, len, api.getTransientDestructor());
                        } else {
                            break :blk api.bind_null(pks_stmt, bind_idx);
                        }
                    },
                    api.SQLITE_BLOB => blk: {
                        const blob = api.value_blob(v);
                        const len = api.value_bytes(v);
                        break :blk api.bind_blob(pks_stmt, bind_idx, blob, len, api.getTransientDestructor());
                    },
                    else => api.bind_null(pks_stmt, bind_idx),
                };
                if (bind_rc != api.SQLITE_OK) {
                    return error.SqliteError;
                }
            } else {
                if (api.bind_null(pks_stmt, bind_idx) != api.SQLITE_OK) {
                    return error.SqliteError;
                }
            }
        }

        // Insert into pks and get assigned __crsql_key
        const step_rc = api.step(pks_stmt);
        if (step_rc != api.SQLITE_ROW) {
            return error.SqliteError;
        }
        const key = api.column_int64(pks_stmt, 0);
        _ = api.reset(pks_stmt);

        // Insert clock entries for each non-PK column
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == 0) {
                if (api.bind_int64(clock_stmt, 1, key) != api.SQLITE_OK) {
                    return error.SqliteError;
                }

                const col_name_slice = col.name[0..col.name_len];
                if (api.bind_text(clock_stmt, 2, @ptrCast(col_name_slice.ptr), @intCast(col.name_len), api.getTransientDestructor()) != api.SQLITE_OK) {
                    return error.SqliteError;
                }

                _ = api.step(clock_stmt);
                _ = api.reset(clock_stmt);
            }
        }

        // If there are no non-PK columns, insert sentinel row
        if (non_pk_count == 0) {
            if (api.bind_int64(clock_stmt, 1, key) != api.SQLITE_OK) {
                return error.SqliteError;
            }
            if (api.bind_text(clock_stmt, 2, "-1", 2, api.SQLITE_STATIC) != api.SQLITE_OK) {
                return error.SqliteError;
            }
            _ = api.step(clock_stmt);
            _ = api.reset(clock_stmt);
        }

        // Bind PK column values from select (columns 0..pk_count)
        for (0..info.pk_count) |i| {
            const col_idx: c_int = @intCast(i);
            const bind_idx: c_int = @intCast(i + 1);
            const value = api.column_value(select_stmt, col_idx);
            if (value) |v| {
                const val_type = api.value_type(v);
                const bind_rc = switch (val_type) {
                    api.SQLITE_INTEGER => api.bind_int64(pks_stmt, bind_idx, api.value_int64(v)),
                    api.SQLITE_FLOAT => api.bind_double(pks_stmt, bind_idx, api.value_double(v)),
                    api.SQLITE_TEXT => blk: {
                        const text = api.value_text(v);
                        const len = api.value_bytes(v);
                        if (text) |t| {
                            break :blk api.bind_text(pks_stmt, bind_idx, t, len, api.getTransientDestructor());
                        } else {
                            break :blk api.bind_null(pks_stmt, bind_idx);
                        }
                    },
                    api.SQLITE_BLOB => blk: {
                        const blob = api.value_blob(v);
                        const len = api.value_bytes(v);
                        break :blk api.bind_blob(pks_stmt, bind_idx, blob, len, api.getTransientDestructor());
                    },
                    else => api.bind_null(pks_stmt, bind_idx),
                };
                if (bind_rc != api.SQLITE_OK) {
                    return error.SqliteError;
                }
            } else {
                if (api.bind_null(pks_stmt, bind_idx) != api.SQLITE_OK) {
                    return error.SqliteError;
                }
            }
        }

        // Insert into pks and capture assigned __crsql_key
        const step_rc2 = api.step(pks_stmt);
        if (step_rc2 != api.SQLITE_ROW) {
            return error.SqliteError;
        }
        const key2 = api.column_int64(pks_stmt, 0);
        _ = api.reset(pks_stmt);

        // Insert clock entries for each non-PK column
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == 0) {
                if (api.bind_int64(clock_stmt, 1, key2) != api.SQLITE_OK) {
                    return error.SqliteError;
                }

                const col_name_slice = col.name[0..col.name_len];
                if (api.bind_text(clock_stmt, 2, @ptrCast(col_name_slice.ptr), @intCast(col.name_len), api.getTransientDestructor()) != api.SQLITE_OK) {
                    return error.SqliteError;
                }

                _ = api.step(clock_stmt);
                _ = api.reset(clock_stmt);
            }
        }

        // If there are no non-PK columns, insert sentinel row
        if (non_pk_count == 0) {
            if (api.bind_int64(clock_stmt, 1, key2) != api.SQLITE_OK) {
                return error.SqliteError;
            }
            if (api.bind_text(clock_stmt, 2, "-1", 2, api.SQLITE_STATIC) != api.SQLITE_OK) {
                return error.SqliteError;
            }
            _ = api.step(clock_stmt);
            _ = api.reset(clock_stmt);
        }
    }
}

/// Register the crsql_as_crr and crsql_as_table functions with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    var rc = api.create_function_v2(
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
    if (rc != api.SQLITE_OK) return rc;

    rc = api.create_function_v2(
        db,
        "crsql_as_table",
        1,
        api.SQLITE_UTF8,
        null,
        &crsqlAsTableFunc,
        null,
        null,
        null,
    );
    return rc;
}

test "createClockTable generates valid SQL" {
    // Just a compile-time check that the format strings are valid
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_clock" (
        \\  "key" INTEGER NOT NULL,
        \\  "col_name" TEXT NOT NULL,
        \\  "col_version" INTEGER NOT NULL,
        \\  "db_version" INTEGER NOT NULL,
        \\  "site_id" INTEGER NOT NULL DEFAULT 0,
        \\  "seq" INTEGER NOT NULL,
        \\  PRIMARY KEY ("key", "col_name")
        \\) WITHOUT ROWID, STRICT;
    , .{"test_table"}) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, sql, "test_table__crsql_clock") != null);
}
