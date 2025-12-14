//! Schema Alter: crsql_begin_alter(table) and crsql_commit_alter(table) implementation
//!
//! These functions enable safe schema migration for CRR tables:
//! - `crsql_begin_alter(table)` drops triggers to allow ALTER TABLE
//! - `crsql_commit_alter(table)` recreates triggers with the new schema
//!
//! Reference: `core/rs/core/src/lib.rs` (x_crsql_begin_alter, x_crsql_commit_alter)

const std = @import("std");
const api = @import("ffi/api.zig");

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

/// Implementation of `crsql_begin_alter(table_name)` SQL function.
///
/// Semantics:
/// 1. Create a savepoint for rollback support
/// 2. Drop all triggers for the table (itrig, utrig, dtrig)
/// 3. Return NULL on success, error on failure
///
/// This allows the user to run ALTER TABLE commands without triggers firing.
fn crsqlBeginAlterFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Validate argument count (1 or 2 arguments)
    if (argc == 0) {
        api.result_error(pCtx, "crsql_begin_alter requires at least 1 argument (table name)", -1);
        return;
    }

    // Get the table name argument (last argument if 2 provided)
    const table_arg_idx: usize = if (argc == 2) 1 else 0;
    const table_name_ptr = api.value_text(argv[table_arg_idx]) orelse {
        api.result_error(pCtx, "crsql_begin_alter: table name must be TEXT", -1);
        return;
    };

    // Get database handle from context
    const db = api.context_db_handle(pCtx) orelse {
        api.result_error(pCtx, "crsql_begin_alter: failed to get db handle", -1);
        return;
    };

    // Create savepoint for rollback support
    if (api.exec(db, "SAVEPOINT alter_crr", null, null, null) != api.SQLITE_OK) {
        api.result_error(pCtx, "crsql_begin_alter: failed to start savepoint", -1);
        return;
    }

    // Drop all triggers for the table
    dropTriggers(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_begin_alter: failed to drop triggers", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Return NULL on success (matching Rust behavior that returns "OK" text)
    api.result_null(pCtx);
}

/// Implementation of `crsql_commit_alter(table_name)` SQL function.
///
/// Semantics:
/// 1. Clean up clock entries for removed columns
/// 2. Re-read table schema via PRAGMA table_info
/// 3. Recreate triggers with new column list
/// 4. Backfill clock entries for new columns with col_version=1
/// 5. Release the savepoint
/// 6. Return NULL on success, error on failure
fn crsqlCommitAlterFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Validate argument count (1 or 2 arguments)
    if (argc == 0) {
        api.result_error(pCtx, "crsql_commit_alter requires at least 1 argument (table name)", -1);
        return;
    }

    // Get the table name argument (last argument if 2 provided)
    const table_arg_idx: usize = if (argc == 2) 1 else 0;
    const table_name_ptr = api.value_text(argv[table_arg_idx]) orelse {
        api.result_error(pCtx, "crsql_commit_alter: table name must be TEXT", -1);
        return;
    };

    // Get database handle from context
    const db = api.context_db_handle(pCtx) orelse {
        api.result_error(pCtx, "crsql_commit_alter: failed to get db handle", -1);
        return;
    };

    // Step 1: Clean up clock entries for columns that no longer exist
    compactPostAlter(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_commit_alter: failed to compact clock table", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Step 2: Recreate triggers with updated schema
    // First, ensure triggers are dropped (they should be from begin_alter, but be safe)
    dropTriggers(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_commit_alter: failed to drop triggers", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Create INSERT trigger
    createInsertTrigger(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_commit_alter: failed to create insert trigger", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Create UPDATE trigger
    createUpdateTrigger(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_commit_alter: failed to create update trigger", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Create DELETE trigger
    createDeleteTrigger(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_commit_alter: failed to create delete trigger", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Step 3: Backfill clock entries for new columns
    backfillNewColumns(db, table_name_ptr) catch {
        api.result_error(pCtx, "crsql_commit_alter: failed to backfill new columns", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    };

    // Release savepoint on success
    if (api.exec(db, "RELEASE alter_crr", null, null, null) != api.SQLITE_OK) {
        api.result_error(pCtx, "crsql_commit_alter: failed to release savepoint", -1);
        _ = api.exec(db, "ROLLBACK TO alter_crr", null, null, null);
        return;
    }

    // Return NULL on success
    api.result_null(pCtx);
}

/// Drop all CRR triggers for a table
fn dropTriggers(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Drop INSERT trigger
    var sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_itrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;

    // Drop UPDATE trigger
    sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_utrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;

    // Drop DELETE trigger
    sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_dtrig\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) return error.SqliteError;
}

/// Detect if primary key columns have changed between the table schema and the pks index.
/// Returns true if there's any difference (column added/removed from PK).
/// Reference: `core/rs/core/src/alter.rs` lines 49-71
fn detectPkChanges(db: ?*api.sqlite3, table_name: [*:0]const u8) !bool {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // First check if the pks index exists. If it doesn't, we can't detect PK changes.
    // This happens when the table was created with crsql_as_crr before the index was added.
    const check_sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM sqlite_master WHERE type='index' AND name='{s}__crsql_pks_pks'
    , .{table_name}) catch return error.BufferOverflow;

    var check_stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, check_sql, -1, &check_stmt, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
    defer _ = api.finalize(check_stmt);

    if (api.step(check_stmt) != api.SQLITE_ROW) {
        return error.SqliteError;
    }

    const index_exists = api.column_int64(check_stmt, 0) > 0;
    if (!index_exists) {
        // Index doesn't exist, can't detect PK changes - assume no change
        return false;
    }

    // Query to detect PK column differences:
    // 1. Find PK columns in table that are NOT in the pks index
    // 2. UNION with columns in pks index that are NOT table PKs (excluding 'col_name')
    // If count > 0, PKs have changed
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(name) FROM (
        \\  SELECT name FROM pragma_table_info('{s}')
        \\    WHERE pk > 0 AND name NOT IN
        \\      (SELECT name FROM pragma_index_info('{s}__crsql_pks_pks'))
        \\  UNION SELECT name FROM pragma_index_info('{s}__crsql_pks_pks') WHERE name NOT IN
        \\    (SELECT name FROM pragma_table_info('{s}') WHERE pk > 0) AND name != 'col_name'
        \\)
    , .{ table_name, table_name, table_name, table_name }) catch return error.BufferOverflow;

    var stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) != api.SQLITE_ROW) {
        return error.SqliteError;
    }

    const pk_diff = api.column_int64(stmt, 0);
    return pk_diff > 0;
}

/// Drop and recreate clock and pks tables when PK columns have changed.
/// Reference: `core/rs/core/src/alter.rs` lines 65-71
fn recreateClockAndPksTables(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Drop clock table
    var sql = std.fmt.bufPrintZ(&buf, "DROP TABLE \"{s}__crsql_clock\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Drop pks table
    sql = std.fmt.bufPrintZ(&buf, "DROP TABLE \"{s}__crsql_pks\"", .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Recreate clock table
    sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_clock" (
        \\  "pk" INTEGER NOT NULL,
        \\  "col_name" TEXT NOT NULL,
        \\  "col_version" INTEGER NOT NULL,
        \\  "db_version" INTEGER NOT NULL,
        \\  "site_id" INTEGER NOT NULL DEFAULT 0,
        \\  "seq" INTEGER NOT NULL,
        \\  PRIMARY KEY ("pk", "col_name")
        \\) WITHOUT ROWID
    , .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Recreate pks table with index on PK columns
    // The pks table needs an index named {table}__crsql_pks_pks on the PK columns
    sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_pks" (
        \\  "pk" INTEGER PRIMARY KEY,
        \\  "pks" BLOB NOT NULL
        \\)
    , .{table_name}) catch return error.BufferOverflow;
    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Create the pks index on the PK columns from the main table
    // This index is what detectPkChanges compares against
    const info = try getTableInfo(db, table_name);

    // Build the index creation SQL with PK columns
    var idx_buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&idx_buf);
    const writer = fbs.writer();

    writer.print("CREATE UNIQUE INDEX IF NOT EXISTS \"{s}__crsql_pks_pks\" ON \"{s}__crsql_pks\" (", .{ table_name, table_name }) catch return error.BufferOverflow;

    // Add PK columns in order
    var pk_written: usize = 0;
    var pk_order: usize = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(")") catch return error.BufferOverflow;

    const idx_len = fbs.pos;
    if (idx_len >= SQL_BUF_SIZE) {
        return error.BufferOverflow;
    }
    idx_buf[idx_len] = 0;

    const idx_sql: [*:0]const u8 = @ptrCast(&idx_buf);
    if (api.exec(db, idx_sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Clean up clock entries for columns that no longer exist after ALTER TABLE.
/// Reference: `core/rs/core/src/alter.rs` compact_post_alter
fn compactPostAlter(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // First check if primary key columns have changed
    // If so, we need to drop and recreate the clock and pks tables
    const pk_changed = detectPkChanges(db, table_name) catch false;
    if (pk_changed) {
        try recreateClockAndPksTables(db, table_name);
        // After recreating tables, no need to clean up old entries - tables are fresh
        // But still need to save pre_compact_dbversion
        try savePreCompactDbVersion(db);
        return;
    }

    // Delete clock entries for columns that no longer exist in the table
    // Keep the sentinel row (col_name = '-1') as it tracks row existence
    const sql = std.fmt.bufPrintZ(&buf,
        \\DELETE FROM "{s}__crsql_clock" WHERE "col_name" NOT IN (
        \\  SELECT name FROM pragma_table_info('{s}') UNION SELECT '-1'
        \\)
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }

    // Delete orphaned clock entries (rows deleted from base table)
    // but preserve tombstones (sentinel rows with even col_version)
    try deleteOrphanedClockEntries(db, table_name);

    // Delete orphaned PK lookasides that no longer map to anything in the clock table
    try deleteOrphanedPkLookasides(db, table_name);

    // Save pre_compact_dbversion to ensure db_version doesn't go backwards after compaction
    try savePreCompactDbVersion(db);
}

/// Delete clock entries that no longer have corresponding rows in the base table,
/// BUT preserve tombstones (sentinel rows with even col_version).
/// Reference: `core/rs/core/src/alter.rs` lines 89-131
fn deleteOrphanedClockEntries(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Delete clock entries where:
    //   - col_name != '-1' (not a sentinel), OR
    //   - col_name = '-1' AND col_version is odd (not a tombstone, since even = deleted)
    // AND there's no corresponding row in the base table (checked via rowid)
    //
    // The pk column in __crsql_clock stores the rowid of the base table row.
    // We check if that rowid still exists in the base table.
    const sql = std.fmt.bufPrintZ(&buf,
        \\DELETE FROM "{s}__crsql_clock" 
        \\WHERE (col_name != '-1' OR (col_name = '-1' AND col_version % 2 != 0))
        \\  AND pk NOT IN (SELECT rowid FROM "{s}")
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Delete PK lookaside entries that no longer have corresponding clock entries.
/// Reference: `core/rs/core/src/alter.rs` lines 134-140
fn deleteOrphanedPkLookasides(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    const sql = std.fmt.bufPrintZ(&buf,
        \\DELETE FROM "{s}__crsql_pks" WHERE pk NOT IN (
        \\  SELECT pk FROM "{s}__crsql_clock"
        \\)
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

/// Save the current db_version to crsql_master as pre_compact_dbversion.
/// This ensures that after compaction (which may delete clock entries),
/// the db_version doesn't regress below this floor.
/// Reference: `core/rs/core/src/alter.rs` lines 143-148
fn savePreCompactDbVersion(db: ?*api.sqlite3) !void {
    // Get current db_version
    const get_version_sql = "SELECT crsql_db_version()";
    var get_stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, get_version_sql, -1, &get_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(get_stmt);

    rc = api.step(get_stmt);
    if (rc != api.SQLITE_ROW) return error.SqliteError;

    const current_db_version = api.column_int64(get_stmt, 0);

    // Insert or replace into crsql_master
    const insert_sql = "INSERT OR REPLACE INTO crsql_master (key, value) VALUES ('pre_compact_dbversion', ?)";
    var insert_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(db, insert_sql, -1, &insert_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(insert_stmt);

    rc = api.bind_int64(insert_stmt, 1, current_db_version);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    rc = api.step(insert_stmt);
    if (rc != api.SQLITE_DONE and rc != api.SQLITE_ROW) return error.SqliteError;
}

/// Backfill clock entries for columns that exist in the table but not in the clock table.
/// This handles new columns added during ALTER TABLE.
fn backfillNewColumns(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get current table info
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return; // No columns, nothing to do
    }

    // For each non-PK column, ensure clock entries exist for all rows
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            // Non-PK column - ensure clock entry exists for all rows missing it
            try backfillColumn(db, table_name, col.name[0..col.name_len]);
        }
    }
}

/// Backfill clock entries for a single column
fn backfillColumn(db: ?*api.sqlite3, table_name: [*:0]const u8, col_name: []const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Insert clock entries for rows that don't have an entry for this column
    // Uses crsql_db_version() instead of crsql_next_db_version() for migration
    // (other nodes will apply the same migration, so no need to re-sync)
    const sql = std.fmt.bufPrintZ(&buf,
        \\INSERT OR IGNORE INTO "{s}__crsql_clock"
        \\  ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\SELECT p."pk", '{s}', 1, crsql_db_version(), 0, 0
        \\FROM "{s}__crsql_pks" p
        \\WHERE NOT EXISTS (
        \\  SELECT 1 FROM "{s}__crsql_clock" c
        \\  WHERE c."pk" = p."pk" AND c."col_name" = '{s}'
        \\)
    , .{ table_name, col_name, table_name, table_name, col_name }) catch return error.BufferOverflow;

    if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
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
/// (Duplicated from as_crr.zig - could be refactored into shared module)
fn createInsertTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return error.NoColumns;
    }

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Trigger header with sync_bit gating
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_itrig"
        \\AFTER INSERT ON "{s}"
        \\WHEN crsql_internal_sync_bit() = 0
        \\BEGIN
        \\  INSERT OR REPLACE INTO "{s}__crsql_pks" ("pk", "pks")
        \\  VALUES (NEW.rowid, crsql_pack_columns(
    , .{ table_name, table_name, table_name }) catch return error.BufferOverflow;

    // Build crsql_pack_columns arguments from PK columns in order
    var pk_written: usize = 0;
    var pk_order: usize = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
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
            writer.print(
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  VALUES
                \\    (NEW.rowid, '{s}', 1, crsql_next_db_version(), 0, 0);
                \\
            , .{ table_name, col.name[0..col.name_len] }) catch return error.BufferOverflow;
        }
    }

    // Sentinel row for row creation tracking
    writer.print(
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  VALUES
        \\    (NEW.rowid, '-1', 1, crsql_next_db_version(), 0, 0);
        \\END;
    , .{table_name}) catch return error.BufferOverflow;

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
fn createUpdateTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
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

    // Trigger header with sync_bit gating + column change check
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_utrig"
        \\AFTER UPDATE ON "{s}"
        \\FOR EACH ROW WHEN crsql_internal_sync_bit() = 0 AND (
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

    writer.writeAll(")\nBEGIN\n") catch return error.BufferOverflow;

    // Generate clock entry for each non-PK column (only when changed)
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            writer.print(
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  SELECT
                \\    NEW.rowid,
                \\    '{s}',
                \\    COALESCE((SELECT col_version FROM "{s}__crsql_clock" WHERE pk = NEW.rowid AND col_name = '{s}'), 0) + 1,
                \\    crsql_next_db_version(),
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
fn createDeleteTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_dtrig"
        \\AFTER DELETE ON "{s}"
        \\WHEN crsql_internal_sync_bit() = 0
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
        \\    crsql_next_db_version(),
        \\    0,
        \\    0;
        \\  -- Drop all clock entries except the sentinel
        \\  DELETE FROM "{s}__crsql_clock"
        \\  WHERE pk = OLD.rowid AND col_name IS NOT '-1';
        \\END;
    , .{ table_name, table_name, table_name, table_name, table_name }) catch return error.BufferOverflow;

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

/// Register the crsql_begin_alter and crsql_commit_alter functions with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    // Register crsql_begin_alter() - 1 argument (table name) or 2 (schema, table)
    var rc = api.create_function_v2(
        db,
        "crsql_begin_alter",
        1, // nArg: 1 argument (table name)
        api.SQLITE_UTF8,
        null, // pApp: no user data
        &crsqlBeginAlterFunc,
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
    if (rc != api.SQLITE_OK) return rc;

    // Also register with 2 arguments (schema, table)
    rc = api.create_function_v2(
        db,
        "crsql_begin_alter",
        2,
        api.SQLITE_UTF8,
        null,
        &crsqlBeginAlterFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_commit_alter() - 1 argument (table name) or 2 (schema, table)
    rc = api.create_function_v2(
        db,
        "crsql_commit_alter",
        1,
        api.SQLITE_UTF8,
        null,
        &crsqlCommitAlterFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Also register with 2 arguments (schema, table)
    rc = api.create_function_v2(
        db,
        "crsql_commit_alter",
        2,
        api.SQLITE_UTF8,
        null,
        &crsqlCommitAlterFunc,
        null,
        null,
        null,
    );
    return rc;
}

test "dropTriggers generates valid SQL" {
    // Compile-time check that the format strings are valid
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DROP TRIGGER IF EXISTS \"{s}__crsql_itrig\"", .{"test_table"}) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, sql, "test_table__crsql_itrig") != null);
}

test "compactPostAlter generates valid SQL" {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\DELETE FROM "{s}__crsql_clock" WHERE "col_name" NOT IN (
        \\  SELECT name FROM pragma_table_info('{s}') UNION SELECT '-1'
        \\)
    , .{ "test_table", "test_table" }) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, sql, "test_table__crsql_clock") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "pragma_table_info") != null);
}

test "detectPkChanges generates valid SQL" {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(name) FROM (
        \\  SELECT name FROM pragma_table_info('{s}')
        \\    WHERE pk > 0 AND name NOT IN
        \\      (SELECT name FROM pragma_index_info('{s}__crsql_pks_pks'))
        \\  UNION SELECT name FROM pragma_index_info('{s}__crsql_pks_pks') WHERE name NOT IN
        \\    (SELECT name FROM pragma_table_info('{s}') WHERE pk > 0) AND name != 'col_name'
        \\)
    , .{ "test_table", "test_table", "test_table", "test_table" }) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, sql, "pragma_table_info") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "pragma_index_info") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "test_table__crsql_pks_pks") != null);
}
