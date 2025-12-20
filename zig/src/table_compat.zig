//! Table Compatibility Validation for CRR Promotion
//!
//! Validates that a table meets the requirements to become a CRR:
//! - Must have a PRIMARY KEY
//! - No UNIQUE indices besides PK
//! - No AUTOINCREMENT
//! - No foreign keys (when enforced)
//! - NOT NULL columns must have DEFAULT values
//! - PK columns must be NOT NULL
//!
//! Reference: `core/rs/core/src/tableinfo.rs` function `is_table_compatible`

const std = @import("std");
const api = @import("ffi/api.zig");

/// Compatibility check result
pub const CompatResult = enum {
    ok,
    no_primary_key,
    nullable_primary_key,
    has_unique_constraint,
    has_autoincrement,
    has_foreign_key,
    not_null_without_default,
};

/// Error message buffer size
const ERR_BUF_SIZE = 512;

/// Check if a table is compatible with CRR requirements.
///
/// Returns `.ok` if the table is compatible, otherwise returns the specific
/// incompatibility reason.
///
/// Check order is designed to give the most specific error first:
/// 1. AUTOINCREMENT (specific prohibition - check before PK since INTEGER PRIMARY KEY AUTOINCREMENT
///    is implicitly NOT NULL but pragma_table_info reports notnull=0)
/// 2. Primary key existence
/// 3. Primary key nullability (for non-INTEGER PRIMARY KEY cases)
/// 4. Unique constraints
/// 5. Foreign keys
/// 6. NOT NULL without DEFAULT
pub fn checkTableCompatibility(db: ?*api.sqlite3, table_name: [*:0]const u8) CompatResult {
    // 1. Check for AUTOINCREMENT first - it's a specific prohibition and INTEGER PRIMARY KEY
    // AUTOINCREMENT is implicitly NOT NULL even though pragma_table_info reports notnull=0
    if (hasAutoincrement(db, table_name)) {
        return .has_autoincrement;
    }

    // 2. Check for primary key existence
    const all_pks = countAllPrimaryKeys(db, table_name) orelse return .no_primary_key;
    if (all_pks == 0) {
        return .no_primary_key;
    }

    // 3. Check for primary key nullability
    // Note: INTEGER PRIMARY KEY is special - always NOT NULL even if not declared
    // For other PK types, we need explicit NOT NULL
    const valid_pks = countValidPrimaryKeys(db, table_name) orelse return .no_primary_key;

    // If all PKs are INTEGER PRIMARY KEY (single column, type INTEGER), it's implicitly NOT NULL
    // Otherwise, all PK columns must be explicitly NOT NULL
    if (valid_pks != all_pks) {
        // Check if this is the special INTEGER PRIMARY KEY case
        if (!isIntegerPrimaryKey(db, table_name)) {
            return .nullable_primary_key;
        }
        // If it is INTEGER PRIMARY KEY, it's implicitly NOT NULL - allow it
    }

    // 4. Check for unique constraints besides PK
    if (hasNonPkUniqueConstraints(db, table_name)) {
        return .has_unique_constraint;
    }

    // 5. Check for foreign keys
    if (hasForeignKeys(db, table_name)) {
        return .has_foreign_key;
    }

    // 6. Check NOT NULL columns have DEFAULT values (except PK columns)
    if (hasNotNullWithoutDefault(db, table_name)) {
        return .not_null_without_default;
    }

    return .ok;
}

/// Get a human-readable error message for a compatibility check result.
pub fn getErrorMessage(result: CompatResult) [*:0]const u8 {
    return switch (result) {
        .ok => "ok",
        .no_primary_key => "table must have a primary key",
        .nullable_primary_key => "primary key columns must be NOT NULL",
        .has_unique_constraint => "table cannot have unique constraints besides primary key",
        .has_autoincrement => "table cannot have autoincrement columns",
        .has_foreign_key => "table cannot have foreign key constraints",
        .not_null_without_default => "NOT NULL columns must have a default value",
    };
}

/// Count primary key columns that are NOT NULL
fn countValidPrimaryKeys(db: ?*api.sqlite3, table_name: [*:0]const u8) ?i64 {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM pragma_table_info('{s}')
        \\WHERE "pk" > 0 AND "notnull" > 0
    , .{table_name}) catch return null;

    return executeCountQuery(db, sql);
}

/// Count all primary key columns (regardless of nullability)
fn countAllPrimaryKeys(db: ?*api.sqlite3, table_name: [*:0]const u8) ?i64 {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM pragma_table_info('{s}')
        \\WHERE "pk" > 0
    , .{table_name}) catch return null;

    return executeCountQuery(db, sql);
}

/// Check if table has a single INTEGER PRIMARY KEY (rowid alias)
/// This is a special case in SQLite - INTEGER PRIMARY KEY is implicitly NOT NULL
/// even if not explicitly declared, because it's an alias for the rowid.
fn isIntegerPrimaryKey(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [512]u8 = undefined;
    // Check: exactly one PK column, and its type is INTEGER
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM pragma_table_info('{s}')
        \\WHERE "pk" = 1 AND upper("type") = 'INTEGER'
    , .{table_name}) catch return false;

    // Also need to check there's only one PK column total
    const count = executeCountQuery(db, sql) orelse return false;
    if (count != 1) {
        return false;
    }

    // Verify there's only one PK column (not compound)
    const total_pks = countAllPrimaryKeys(db, table_name) orelse return false;
    return total_pks == 1;
}

/// Check if table has unique constraints besides primary key
fn hasNonPkUniqueConstraints(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM pragma_index_list('{s}')
        \\WHERE "origin" != 'pk' AND "unique" = 1
    , .{table_name}) catch return false;

    if (executeCountQuery(db, sql)) |count| {
        return count > 0;
    }
    return false;
}

/// Check if table has AUTOINCREMENT
fn hasAutoincrement(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT sql FROM sqlite_master WHERE name = '{s}' AND type = 'table'
    , .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return false;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        const sql_text_ptr = api.column_text(stmt, 0);
        if (sql_text_ptr) |sql_text| {
            const sql_slice = std.mem.span(sql_text);
            // Case-insensitive search for "autoincrement"
            var lower_buf: [8192]u8 = undefined;
            if (sql_slice.len < lower_buf.len) {
                for (sql_slice, 0..) |c, i| {
                    lower_buf[i] = std.ascii.toLower(c);
                }
                const lower_slice = lower_buf[0..sql_slice.len];
                if (std.mem.indexOf(u8, lower_slice, "autoincrement") != null) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if table has foreign keys
fn hasForeignKeys(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM pragma_foreign_key_list('{s}')
    , .{table_name}) catch return false;

    if (executeCountQuery(db, sql)) |count| {
        return count > 0;
    }
    return false;
}

/// Check if table has NOT NULL columns without DEFAULT values (excluding PK columns)
fn hasNotNullWithoutDefault(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    // Use pragma_table_xinfo which provides more detailed info including hidden columns
    // notnull=1, dflt_value IS NULL, pk=0 means: NOT NULL, no default, not a PK column
    var buf: [512]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM pragma_table_xinfo('{s}')
        \\WHERE "notnull" = 1 AND "dflt_value" IS NULL AND "pk" = 0
    , .{table_name}) catch return false;

    if (executeCountQuery(db, sql)) |count| {
        return count > 0;
    }
    return false;
}

/// Execute a COUNT(*) query and return the result
fn executeCountQuery(db: ?*api.sqlite3, sql: [*:0]const u8) ?i64 {
    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return null;
    }
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }
    return null;
}

test "getErrorMessage returns correct strings" {
    // Compile-time check that error messages exist and contain expected keywords
    const pk_err = getErrorMessage(.no_primary_key);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(pk_err), "primary key") != null);

    const unique_err = getErrorMessage(.has_unique_constraint);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(unique_err), "unique") != null);

    const autoinc_err = getErrorMessage(.has_autoincrement);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(autoinc_err), "autoincrement") != null);

    const fk_err = getErrorMessage(.has_foreign_key);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(fk_err), "foreign key") != null);

    const notnull_err = getErrorMessage(.not_null_without_default);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(notnull_err), "NOT NULL") != null);

    const nullable_pk_err = getErrorMessage(.nullable_primary_key);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(nullable_pk_err), "NOT NULL") != null);
}
