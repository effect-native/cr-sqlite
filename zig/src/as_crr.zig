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

/// Create the pks table for mapping auto-increment keys to packed PK blobs.
/// The pk column is an auto-increment key that is INDEPENDENT of base table rowid.
/// This allows compound/text PK tables to have separate entries for old and new PKs
/// when a PK column is updated (old entry for tombstone, new entry for live row).
///
/// The base_rowid column stores the current base table rowid for live rows.
/// For tombstoned entries, base_rowid is NULL (the row no longer exists).
/// This allows efficient value lookups: pks.pk -> pks.base_rowid -> base_table.rowid
///
/// Schema:
/// ```sql
/// CREATE TABLE IF NOT EXISTS "{table}__crsql_pks" (
///   "pk" INTEGER PRIMARY KEY,     -- Auto-increment key (clock table references this)
///   "base_rowid" INTEGER,         -- Base table rowid (NULL for tombstoned entries)
///   "pks" BLOB NOT NULL UNIQUE    -- Packed PK blob, unique constraint for lookups
/// );
/// ```
fn createPksTable(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TABLE IF NOT EXISTS "{s}__crsql_pks" (
        \\  "pk" INTEGER PRIMARY KEY,
        \\  "base_rowid" INTEGER,
        \\  "pks" BLOB NOT NULL UNIQUE
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
/// - Creates pks entry with auto-increment key
/// - Creates clock entries for each non-PK column using pks key (not base rowid)
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

    // Trigger header with sync_bit gating
    // Use INSERT ... ON CONFLICT to handle resurrection: if blob exists (from tombstone),
    // update base_rowid to point to the new row, keeping the same pk key
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_itrig"
        \\AFTER INSERT ON "{s}"
        \\WHEN crsql_internal_sync_bit() = 0
        \\BEGIN
        \\  INSERT INTO "{s}__crsql_pks" ("base_rowid", "pks")
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

    writer.writeAll(")) ON CONFLICT(pks) DO UPDATE SET base_rowid = NEW.rowid;\n") catch return error.BufferOverflow;

    // Generate clock entry for each non-PK column
    // Use subquery to get the pks key for this blob (not base table rowid)
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            // Non-PK column - create clock entry
            // The pk is looked up from pks table by blob, not using base table rowid
            writer.print(
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  VALUES
                \\    ((SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
            , .{ table_name, table_name }) catch return error.BufferOverflow;

            // Rewrite pk columns for subquery
            pk_written = 0;
            pk_order = 1;
            while (pk_written < info.pk_count) : (pk_order += 1) {
                for (info.columns[0..info.count]) |pk_col| {
                    if (pk_col.pk_index == @as(c_int, @intCast(pk_order))) {
                        if (pk_written > 0) {
                            writer.writeAll(", ") catch return error.BufferOverflow;
                        }
                        writer.print("NEW.\"{s}\"", .{pk_col.name[0..pk_col.name_len]}) catch return error.BufferOverflow;
                        pk_written += 1;
                        break;
                    }
                }
            }

            writer.print(
                \\)), '{s}', 1, crsql_next_db_version(), 0, crsql_increment_and_get_seq());
                \\
            , .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
        }
    }

    // Sentinel row for row creation tracking
    // Use subquery to get the pks key for this blob
    writer.print(
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  VALUES
        \\    ((SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Rewrite pk columns for subquery
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |pk_col| {
            if (pk_col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("NEW.\"{s}\"", .{pk_col.name[0..pk_col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(")), '-1', 1, crsql_next_db_version(), 0, crsql_increment_and_get_seq());\nEND;") catch return error.BufferOverflow;

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

/// Create the UPDATE trigger that captures non-PK column changes.
/// - Only fires when at least one non-PK column has changed AND no PK column changed
/// - Creates clock entries for each changed non-PK column
/// - Increments col_version for each changed column
/// Note: PK column changes are handled by the separate PK update trigger
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

    // Trigger header with sync_bit gating + column change check
    // This trigger only fires when non-PK columns change AND PK columns stay the same
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_utrig"
        \\AFTER UPDATE ON "{s}"
        \\FOR EACH ROW WHEN crsql_internal_sync_bit() = 0 AND (
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build WHEN clause for non-PK column changes: OLD.col IS NOT NEW.col OR ...
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

    // Add exclusion for PK column changes: AND all PK columns are unchanged
    // This prevents this trigger from firing when PK changes (handled by pk_utrig)
    if (info.pk_count > 0) {
        writer.writeAll(") AND (") catch return error.BufferOverflow;
        var first_pk = true;
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index > 0) {
                if (!first_pk) {
                    writer.writeAll(" AND ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\" IS NEW.\"{s}\"", .{
                    col.name[0..col.name_len],
                    col.name[0..col.name_len],
                }) catch return error.BufferOverflow;
                first_pk = false;
            }
        }
    }

    // Close the parentheses for conditions
    writer.writeAll(")\nBEGIN\n") catch return error.BufferOverflow;

    // Generate clock entry for each non-PK column (only when changed)
    // Use pks table lookup to get the pk key (not base table rowid)
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            // Non-PK column - create/update clock entry when changed
            // The pk is looked up from pks table by blob
            writer.print(
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  SELECT
                \\    (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
            , .{ table_name, table_name }) catch return error.BufferOverflow;

            // Write PK columns for subquery
            var pk_written_inner: usize = 0;
            var pk_order_inner: usize = 1;
            while (pk_written_inner < info.pk_count) : (pk_order_inner += 1) {
                for (info.columns[0..info.count]) |pk_col| {
                    if (pk_col.pk_index == @as(c_int, @intCast(pk_order_inner))) {
                        if (pk_written_inner > 0) {
                            writer.writeAll(", ") catch return error.BufferOverflow;
                        }
                        writer.print("NEW.\"{s}\"", .{pk_col.name[0..pk_col.name_len]}) catch return error.BufferOverflow;
                        pk_written_inner += 1;
                        break;
                    }
                }
            }

            // Continue with col_version lookup using the same pk subquery pattern
            writer.print(
                \\)),
                \\    '{s}',
                \\    COALESCE((SELECT col_version FROM "{s}__crsql_clock" WHERE pk = (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
            , .{ col.name[0..col.name_len], table_name, table_name }) catch return error.BufferOverflow;

            // Write PK columns again for the nested subquery
            pk_written_inner = 0;
            pk_order_inner = 1;
            while (pk_written_inner < info.pk_count) : (pk_order_inner += 1) {
                for (info.columns[0..info.count]) |pk_col| {
                    if (pk_col.pk_index == @as(c_int, @intCast(pk_order_inner))) {
                        if (pk_written_inner > 0) {
                            writer.writeAll(", ") catch return error.BufferOverflow;
                        }
                        writer.print("NEW.\"{s}\"", .{pk_col.name[0..pk_col.name_len]}) catch return error.BufferOverflow;
                        pk_written_inner += 1;
                        break;
                    }
                }
            }

            writer.print(
                \\)) AND col_name = '{s}'), 0) + 1,
                \\    crsql_next_db_version(),
                \\    0,
                \\    crsql_increment_and_get_seq()
                \\  WHERE OLD."{s}" IS NOT NEW."{s}";
                \\
            , .{
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
fn createPkUpdateTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get table column information
    const info = try getTableInfo(db, table_name);
    if (info.count == 0) {
        return error.NoColumns;
    }

    // If pk_count == 0, skip - no PK columns to track changes on
    if (info.pk_count == 0) {
        return error.NoPrimaryKey;
    }

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Trigger header: fires when ANY PK column changes
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_pk_utrig"
        \\AFTER UPDATE ON "{s}"
        \\FOR EACH ROW WHEN crsql_internal_sync_bit() = 0 AND (
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build WHEN clause: OLD.pk_col IS NOT NEW.pk_col OR ...
    var first_pk = true;
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index > 0) {
            if (!first_pk) {
                writer.writeAll(" OR ") catch return error.BufferOverflow;
            }
            writer.print("OLD.\"{s}\" IS NOT NEW.\"{s}\"", .{
                col.name[0..col.name_len],
                col.name[0..col.name_len],
            }) catch return error.BufferOverflow;
            first_pk = false;
        }
    }

    writer.writeAll(")\nBEGIN\n") catch return error.BufferOverflow;

    // Step 1: Tombstone the OLD PK
    // Look up the OLD pk key from pks table and mark it as deleted
    // The OLD pks entry stays in place - it maps OLD pk blob to the clock key
    writer.print(
        \\  -- Step 1: Tombstone the old PK (mark as deleted)
        \\  -- Look up the pk key for OLD pk blob
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  SELECT
        \\    (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build OLD pk columns for pack_columns
    var pk_written: usize = 0;
    var pk_order: usize = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.print(
        \\)),
        \\    '-1',
        \\    COALESCE(
        \\      (SELECT col_version + 1 FROM "{s}__crsql_clock"
        \\       WHERE pk = (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build OLD pk columns again for nested subquery
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.print(
        \\)) AND col_name = '-1'),
        \\      2
        \\    ),
        \\    crsql_next_db_version(),
        \\    0,
        \\    crsql_increment_and_get_seq();
        \\  -- Delete all non-sentinel clock entries for old PK
        \\  DELETE FROM "{s}__crsql_clock"
        \\  WHERE pk = (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build OLD pk columns again for delete
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(")) AND col_name IS NOT '-1';\n") catch return error.BufferOverflow;

    // Step 1b: Mark old pks entry as tombstoned (clear base_rowid)
    writer.print(
        \\  -- Step 1b: Mark old pks entry as tombstoned
        \\  UPDATE "{s}__crsql_pks" SET base_rowid = NULL
        \\  WHERE pks = crsql_pack_columns(
    , .{table_name}) catch return error.BufferOverflow;

    // Build OLD pk columns for update
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(");\n") catch return error.BufferOverflow;

    // Step 2: Create NEW pks entry for the NEW pk blob
    // INSERT with base_rowid = NEW.rowid
    writer.print(
        \\  -- Step 2: Create NEW pks entry with base_rowid
        \\  INSERT INTO "{s}__crsql_pks" ("base_rowid", "pks")
        \\  VALUES (NEW.rowid, crsql_pack_columns(
    , .{table_name}) catch return error.BufferOverflow;

    // Build NEW pk columns for pack_columns
    pk_written = 0;
    pk_order = 1;
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

    // Step 3: Create fresh clock entries for all non-PK columns under NEW pks key
    for (info.columns[0..info.count]) |col| {
        if (col.pk_index == 0) {
            writer.print(
                \\  -- Step 3: Create clock entry for '{s}' under new PK
                \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
                \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
                \\  VALUES
                \\    ((SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
            , .{ col.name[0..col.name_len], table_name, table_name }) catch return error.BufferOverflow;

            // Build NEW pk columns for subquery
            pk_written = 0;
            pk_order = 1;
            while (pk_written < info.pk_count) : (pk_order += 1) {
                for (info.columns[0..info.count]) |pk_col| {
                    if (pk_col.pk_index == @as(c_int, @intCast(pk_order))) {
                        if (pk_written > 0) {
                            writer.writeAll(", ") catch return error.BufferOverflow;
                        }
                        writer.print("NEW.\"{s}\"", .{pk_col.name[0..pk_col.name_len]}) catch return error.BufferOverflow;
                        pk_written += 1;
                        break;
                    }
                }
            }

            writer.print(
                \\)), '{s}', 1, crsql_next_db_version(), 0, crsql_increment_and_get_seq());
                \\
            , .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
        }
    }

    // Step 4: Create sentinel for new row (row created)
    writer.print(
        \\  -- Step 4: Create sentinel for new PK (row created)
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  VALUES
        \\    ((SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build NEW pk columns for subquery
    pk_written = 0;
    pk_order = 1;
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

    writer.writeAll(")), '-1', 1, crsql_next_db_version(), 0, crsql_increment_and_get_seq());\nEND;") catch return error.BufferOverflow;

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
/// Note: Uses pks table lookup to get the pk key (not base table rowid)
fn createDeleteTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    // Get table column information for pk columns
    const info = try getTableInfo(db, table_name);

    var buf: [SQL_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Trigger header with sync_bit gating
    writer.print(
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_dtrig"
        \\AFTER DELETE ON "{s}"
        \\WHEN crsql_internal_sync_bit() = 0
        \\BEGIN
        \\  -- Mark row as deleted: insert sentinel with col_version=2, or increment existing
        \\  -- Use pks table lookup to get the pk key
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock"
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  SELECT
        \\    (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name, table_name, table_name }) catch return error.BufferOverflow;

    // Build OLD pk columns for pack_columns
    var pk_written: usize = 0;
    var pk_order: usize = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.print(
        \\)),
        \\    '-1',
        \\    COALESCE(
        \\      (SELECT col_version + 1 FROM "{s}__crsql_clock"
        \\       WHERE pk = (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build OLD pk columns again for nested subquery
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.print(
        \\)) AND col_name = '-1'),
        \\      2
        \\    ),
        \\    crsql_next_db_version(),
        \\    0,
        \\    crsql_increment_and_get_seq();
        \\  -- Drop all clock entries except the sentinel
        \\  DELETE FROM "{s}__crsql_clock"
        \\  WHERE pk = (SELECT pk FROM "{s}__crsql_pks" WHERE pks = crsql_pack_columns(
    , .{ table_name, table_name }) catch return error.BufferOverflow;

    // Build OLD pk columns again for delete
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(")) AND col_name IS NOT '-1';\n") catch return error.BufferOverflow;

    // Mark pks entry as tombstoned (clear base_rowid)
    writer.print(
        \\  -- Mark pks entry as tombstoned
        \\  UPDATE "{s}__crsql_pks" SET base_rowid = NULL
        \\  WHERE pks = crsql_pack_columns(
    , .{table_name}) catch return error.BufferOverflow;

    // Build OLD pk columns for update
    pk_written = 0;
    pk_order = 1;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                if (pk_written > 0) {
                    writer.writeAll(", ") catch return error.BufferOverflow;
                }
                writer.print("OLD.\"{s}\"", .{col.name[0..col.name_len]}) catch return error.BufferOverflow;
                pk_written += 1;
                break;
            }
        }
    }

    writer.writeAll(");\nEND;") catch return error.BufferOverflow;

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

/// Backfill existing rows in the base table with clock entries.
/// This is called after creating CRR tables and triggers to ensure
/// pre-existing data gets tracked.
///
/// Algorithm (from Rust reference core/rs/core/src/backfill.rs):
/// 1. Find rows in base table not yet in pks table (via LEFT JOIN/EXCEPT)
/// 2. For each such row:
///    a. Insert into pks table: (rowid, crsql_pack_columns(pk_cols...))
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

    // Build the SELECT query to find rows not yet backfilled
    // Query: SELECT rowid, pk_cols... FROM table WHERE rowid NOT IN (SELECT pk FROM table__crsql_pks)
    var select_buf: [SQL_BUF_SIZE]u8 = undefined;
    var select_fbs = std.io.fixedBufferStream(&select_buf);
    const select_writer = select_fbs.writer();

    select_writer.print("SELECT rowid", .{}) catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    // Add PK columns in order for crsql_pack_columns
    var pk_order: usize = 1;
    var pk_written: usize = 0;
    while (pk_written < info.pk_count) : (pk_order += 1) {
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == @as(c_int, @intCast(pk_order))) {
                select_writer.print(", \"{s}\"", .{col.name[0..col.name_len]}) catch {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.BufferOverflow;
                };
                pk_written += 1;
                break;
            }
        }
    }

    // Find rows not yet in pks table (use base_rowid column, not pk)
    select_writer.print(" FROM \"{s}\" WHERE rowid NOT IN (SELECT base_rowid FROM \"{s}__crsql_pks\" WHERE base_rowid IS NOT NULL)", .{ table_name, table_name }) catch {
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
    var pks_insert_buf: [SQL_BUF_SIZE]u8 = undefined;
    var pks_fbs = std.io.fixedBufferStream(&pks_insert_buf);
    const pks_writer = pks_fbs.writer();

    // Insert with base_rowid instead of pk (pk auto-increments)
    pks_writer.print("INSERT OR IGNORE INTO \"{s}__crsql_pks\" (base_rowid, pks) VALUES (?, crsql_pack_columns(", .{table_name}) catch {
        _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
        return error.BufferOverflow;
    };

    // Add placeholders for each PK column value
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

    pks_writer.writeAll("))") catch {
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
        \\  (pk, col_name, col_version, db_version, site_id, seq)
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
        // Column 0 is rowid
        const rowid = api.column_int64(select_stmt, 0);

        // Insert into pks table
        // Bind rowid as first param
        if (api.bind_int64(pks_stmt, 1, rowid) != api.SQLITE_OK) {
            _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
            return error.SqliteError;
        }

        // Bind PK column values (columns 1..pk_count from select)
        for (1..info.pk_count + 1) |i| {
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

        _ = api.step(pks_stmt);
        _ = api.reset(pks_stmt);

        // Insert clock entries for each non-PK column
        for (info.columns[0..info.count]) |col| {
            if (col.pk_index == 0) {
                // Non-PK column - create clock entry
                if (api.bind_int64(clock_stmt, 1, rowid) != api.SQLITE_OK) {
                    _ = api.exec(db, "ROLLBACK TO backfill", null, null, null);
                    return error.SqliteError;
                }

                // Bind column name
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
            if (api.bind_int64(clock_stmt, 1, rowid) != api.SQLITE_OK) {
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

fn dropTriggers(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
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
