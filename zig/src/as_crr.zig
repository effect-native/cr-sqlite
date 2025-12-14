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
const SQL_BUF_SIZE = 4096;

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

    // Create triggers - Phase 1: INSERT trigger only
    if (createInsertTrigger(db, table_name_ptr)) |_| {
        // Success
    } else |_| {
        api.result_error(pCtx, "crsql_as_crr: failed to create insert trigger", -1);
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

/// Create the INSERT trigger that captures new rows.
/// For Phase 1, we use hardcoded defaults for db_version, site_id, seq.
///
/// This is a simplified version - real implementation needs to:
/// - Query table_info to get column names
/// - Generate clock entries for each non-PK column
/// - Pack actual PK values
fn createInsertTrigger(db: ?*api.sqlite3, table_name: [*:0]const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    
    // Phase 1: Minimal trigger that just records the rowid and a sentinel
    // Real implementation would iterate over non-PK columns
    const sql = std.fmt.bufPrintZ(&buf,
        \\CREATE TRIGGER IF NOT EXISTS "{s}__crsql_itrig"
        \\AFTER INSERT ON "{s}"
        \\BEGIN
        \\  INSERT OR REPLACE INTO "{s}__crsql_pks" ("pk", "pks")
        \\  VALUES (NEW.rowid, X'00');
        \\  INSERT OR REPLACE INTO "{s}__crsql_clock" 
        \\    ("pk", "col_name", "col_version", "db_version", "site_id", "seq")
        \\  VALUES 
        \\    (NEW.rowid, '-sentinel-', 1, 1, 0, 0);
        \\END;
    , .{table_name, table_name, table_name, table_name}) catch return error.BufferOverflow;

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
