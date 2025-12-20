//! Schema Automigrate: crsql_automigrate(schema_sql[, cleanup_sql]) implementation
//!
//! Performs automatic schema migration to match a desired schema:
//! - Creates tables defined in schema but not in DB
//! - Drops tables in DB but not in schema (excluding system tables)
//! - Adds/drops columns to match schema
//! - Reconciles indices
//! - Uses CRR alter flow for tables that are CRRs
//! - Atomic: invalid schema = no partial changes
//!
//! Reference: `core/rs/core/src/automigrate.rs`

const std = @import("std");
const api = @import("ffi/api.zig");

/// SQL buffer size for DDL generation
const SQL_BUF_SIZE = 8192;

/// Maximum number of tables/columns we can track
const MAX_ITEMS = 128;

/// Maximum length for a table/column/index name
const MAX_NAME_LEN = 128;

/// SQL to check if an index is unique
const IS_UNIQUE_IDX_SQL = "SELECT \"unique\" FROM pragma_index_list(?) WHERE name = ?";

/// SQL to get columns in an index
const IDX_COLS_SQL = "SELECT name FROM pragma_index_info(?) ORDER BY seqno ASC";

/// Implementation of `crsql_automigrate(schema_sql[, cleanup_sql])` SQL function.
///
/// Semantics:
/// 1. Parse schema in an in-memory database (with CRR statements stripped)
/// 2. Compare current schema to desired schema
/// 3. Drop tables not in desired schema
/// 4. For each table in both: add/drop columns, reconcile indices
/// 5. Apply the original schema (creates new tables, applies CRR)
/// 6. All within a savepoint for atomicity
fn crsqlAutomigrateFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    if (argc < 1) {
        api.result_error(pCtx, "crsql_automigrate requires at least 1 argument (schema)", -1);
        return;
    }

    // Get the schema argument
    const schema_ptr = api.value_text(argv[0]) orelse {
        // NULL schema treated as empty string
        finishSuccess(pCtx);
        return;
    };
    const schema = std.mem.span(schema_ptr);

    // Get optional cleanup SQL (second argument)
    var cleanup_sql: ?[]const u8 = null;
    if (argc >= 2) {
        if (api.value_text(argv[1])) |cleanup_ptr| {
            cleanup_sql = std.mem.span(cleanup_ptr);
        }
    }

    // Get database handle from context
    const db = api.context_db_handle(pCtx) orelse {
        api.result_error(pCtx, "crsql_automigrate: failed to get db handle", -1);
        return;
    };

    // Perform the migration
    automigrate_impl(pCtx, db, schema, cleanup_sql) catch {
        // Error message should already be set
        return;
    };

    finishSuccess(pCtx);
}

fn finishSuccess(pCtx: ?*api.sqlite3_context) void {
    api.result_text(pCtx, "migration complete", -1, api.SQLITE_STATIC);
}

/// Core automigrate implementation
fn automigrate_impl(
    pCtx: ?*api.sqlite3_context,
    local_db: ?*api.sqlite3,
    schema: []const u8,
    cleanup_sql: ?[]const u8,
) !void {
    // Strip CRR statements for validation in memory db
    var stripped_buf: [SQL_BUF_SIZE * 4]u8 = undefined;
    const stripped = stripCrrStatements(schema, &stripped_buf) catch {
        api.result_error(pCtx, "crsql_automigrate: schema too large", -1);
        return error.SchemaTooBig;
    };

    // Open in-memory database to parse/validate schema
    var mem_db: ?*api.sqlite3 = null;
    var rc = api.open(":memory:", &mem_db);
    if (rc != api.SQLITE_OK or mem_db == null) {
        api.result_error(pCtx, "could not open the temporary migration db", -1);
        return error.CantOpen;
    }
    defer {
        // Run cleanup SQL if provided
        if (cleanup_sql) |cleanup| {
            if (cleanup.len > 0) {
                // Need null-terminated string
                var cleanup_buf: [SQL_BUF_SIZE]u8 = undefined;
                if (cleanup.len < cleanup_buf.len) {
                    @memcpy(cleanup_buf[0..cleanup.len], cleanup);
                    cleanup_buf[cleanup.len] = 0;
                    _ = api.exec(mem_db, @ptrCast(&cleanup_buf), null, null, null);
                }
            }
        }
        _ = api.close_v2(mem_db);
    }

    // Execute stripped schema in memory db to validate it
    if (stripped.len > 0) {
        // Need null-terminated string for exec
        var exec_buf: [SQL_BUF_SIZE * 4]u8 = undefined;
        if (stripped.len >= exec_buf.len) {
            api.result_error(pCtx, "crsql_automigrate: schema too large", -1);
            return error.SchemaTooBig;
        }
        @memcpy(exec_buf[0..stripped.len], stripped);
        exec_buf[stripped.len] = 0;

        rc = api.exec(mem_db, @ptrCast(&exec_buf), null, null, null);
        if (rc != api.SQLITE_OK) {
            // Get error message from mem_db
            const err_msg = api.errmsg(mem_db);
            api.result_error(pCtx, err_msg, -1);
            return error.InvalidSchema;
        }
    }

    // Start savepoint for atomicity
    rc = api.exec(local_db, "SAVEPOINT automigrate_tables", null, null, null);
    if (rc != api.SQLITE_OK) {
        api.result_error(pCtx, "crsql_automigrate: failed to start savepoint", -1);
        return error.SavepointFailed;
    }

    // Perform the migration
    migrateTo(local_db, mem_db) catch |err| {
        _ = api.exec(local_db, "ROLLBACK", null, null, null);
        const err_msg = api.errmsg(mem_db);
        api.result_error(pCtx, err_msg, -1);
        return err;
    };

    // Apply original schema (creates new tables, applies CRR statements)
    if (schema.len > 0) {
        var schema_buf: [SQL_BUF_SIZE * 4]u8 = undefined;
        if (schema.len >= schema_buf.len) {
            _ = api.exec(local_db, "ROLLBACK", null, null, null);
            api.result_error(pCtx, "crsql_automigrate: schema too large", -1);
            return error.SchemaTooBig;
        }
        @memcpy(schema_buf[0..schema.len], schema);
        schema_buf[schema.len] = 0;

        const schema_ptr: [*:0]const u8 = @ptrCast(&schema_buf);
        rc = api.exec(local_db, schema_ptr, null, null, null);
        if (rc != api.SQLITE_OK) {
            _ = api.exec(local_db, "ROLLBACK", null, null, null);
            const err_msg = api.errmsg(local_db);
            api.result_error(pCtx, err_msg, -1);
            return error.SchemaApplyFailed;
        }
    }

    // Release savepoint
    rc = api.exec(local_db, "RELEASE automigrate_tables", null, null, null);
    if (rc != api.SQLITE_OK) {
        _ = api.exec(local_db, "ROLLBACK", null, null, null);
        api.result_error(pCtx, "crsql_automigrate: failed to release savepoint", -1);
        return error.SavepointFailed;
    }
}

/// Strip crsql_as_crr and crsql_fract_as_ordered statements from schema
fn stripCrrStatements(schema: []const u8, buf: []u8) ![]const u8 {
    var out_pos: usize = 0;
    var lines = std.mem.splitScalar(u8, schema, '\n');

    while (lines.next()) |line| {
        // Check if line contains CRR statements (case-insensitive)
        var lower_buf: [SQL_BUF_SIZE]u8 = undefined;
        const lower_line = toLower(line, &lower_buf);

        if (std.mem.indexOf(u8, lower_line, "crsql_as_crr") != null or
            std.mem.indexOf(u8, lower_line, "crsql_fract_as_ordered") != null)
        {
            // Skip this line
            continue;
        }

        // Copy line to output
        if (out_pos + line.len + 1 > buf.len) {
            return error.BufferOverflow;
        }
        @memcpy(buf[out_pos .. out_pos + line.len], line);
        out_pos += line.len;
        buf[out_pos] = '\n';
        out_pos += 1;
    }

    return buf[0..out_pos];
}

fn toLower(str: []const u8, buf: []u8) []const u8 {
    const len = @min(str.len, buf.len);
    for (0..len) |i| {
        buf[i] = std.ascii.toLower(str[i]);
    }
    return buf[0..len];
}

/// Compare local_db schema to mem_db (desired) schema and migrate
fn migrateTo(local_db: ?*api.sqlite3, mem_db: ?*api.sqlite3) !void {
    // Query for tables (excluding system tables)
    const sql =
        \\SELECT name FROM sqlite_master WHERE type = 'table'
        \\    AND name NOT LIKE 'sqlite_%'
        \\    AND name NOT LIKE 'crsql_%'
        \\    AND name NOT LIKE '__crsql_%'
        \\    AND name NOT LIKE '%__crsql_%'
    ;

    // Get tables in mem_db (desired)
    var mem_tables: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var mem_table_lens: [MAX_ITEMS]usize = undefined;
    var mem_count: usize = 0;

    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(mem_db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(stmt);

    while (api.step(stmt) == api.SQLITE_ROW) {
        const name_ptr = api.column_text(stmt, 0) orelse continue;
        const name = std.mem.span(name_ptr);
        if (name.len >= MAX_NAME_LEN or mem_count >= MAX_ITEMS) continue;
        @memcpy(mem_tables[mem_count][0..name.len], name);
        mem_table_lens[mem_count] = name.len;
        mem_count += 1;
    }

    // Get tables in local_db (current)
    var local_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(local_db, sql, -1, &local_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(local_stmt);

    var removed_tables: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var removed_lens: [MAX_ITEMS]usize = undefined;
    var removed_count: usize = 0;

    var maybe_modified: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var modified_lens: [MAX_ITEMS]usize = undefined;
    var modified_count: usize = 0;

    while (api.step(local_stmt) == api.SQLITE_ROW) {
        const name_ptr = api.column_text(local_stmt, 0) orelse continue;
        const name = std.mem.span(name_ptr);
        if (name.len >= MAX_NAME_LEN) continue;

        // Check if this table exists in mem_db
        var found = false;
        for (0..mem_count) |i| {
            if (std.mem.eql(u8, name, mem_tables[i][0..mem_table_lens[i]])) {
                found = true;
                break;
            }
        }

        if (found) {
            // Table exists in both - may need modification
            if (modified_count < MAX_ITEMS) {
                @memcpy(maybe_modified[modified_count][0..name.len], name);
                modified_lens[modified_count] = name.len;
                modified_count += 1;
            }
        } else {
            // Table only in local - should be removed
            if (removed_count < MAX_ITEMS) {
                @memcpy(removed_tables[removed_count][0..name.len], name);
                removed_lens[removed_count] = name.len;
                removed_count += 1;
            }
        }
    }

    // Drop tables not in desired schema
    try dropTables(local_db, removed_tables[0..removed_count], removed_lens[0..removed_count]);

    // Modify existing tables
    for (0..modified_count) |i| {
        const table_name = maybe_modified[i][0..modified_lens[i]];
        try maybeModifyTable(local_db, table_name, mem_db);
    }
}

fn dropTables(db: ?*api.sqlite3, tables: [][MAX_NAME_LEN]u8, lens: []usize) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    for (0..tables.len) |i| {
        const name = tables[i][0..lens[i]];
        const sql = std.fmt.bufPrintZ(&buf, "DROP TABLE \"{s}\"", .{name}) catch continue;
        if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
            return error.SqliteError;
        }
    }
}

fn maybeModifyTable(local_db: ?*api.sqlite3, table_name: []const u8, mem_db: ?*api.sqlite3) !void {
    // Get columns in local table
    var local_cols: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var local_lens: [MAX_ITEMS]usize = undefined;
    var local_count: usize = 0;

    // Get columns in mem table
    var mem_cols: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var mem_lens: [MAX_ITEMS]usize = undefined;
    var mem_count: usize = 0;

    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Query pragma_table_info for both
    const pragma_sql = "SELECT name FROM pragma_table_info(?)";

    var local_stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(local_db, pragma_sql, -1, &local_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(local_stmt);

    // Bind table name (need null-terminated)
    var table_buf: [MAX_NAME_LEN + 1]u8 = undefined;
    @memcpy(table_buf[0..table_name.len], table_name);
    table_buf[table_name.len] = 0;
    const table_ptr: [*:0]const u8 = @ptrCast(&table_buf);
    rc = api.bind_text(local_stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    while (api.step(local_stmt) == api.SQLITE_ROW) {
        const col_ptr = api.column_text(local_stmt, 0) orelse continue;
        const col_name = std.mem.span(col_ptr);
        if (col_name.len >= MAX_NAME_LEN or local_count >= MAX_ITEMS) continue;
        @memcpy(local_cols[local_count][0..col_name.len], col_name);
        local_lens[local_count] = col_name.len;
        local_count += 1;
    }

    var mem_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(mem_db, pragma_sql, -1, &mem_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(mem_stmt);

    rc = api.bind_text(mem_stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    while (api.step(mem_stmt) == api.SQLITE_ROW) {
        const col_ptr = api.column_text(mem_stmt, 0) orelse continue;
        const col_name = std.mem.span(col_ptr);
        if (col_name.len >= MAX_NAME_LEN or mem_count >= MAX_ITEMS) continue;
        @memcpy(mem_cols[mem_count][0..col_name.len], col_name);
        mem_lens[mem_count] = col_name.len;
        mem_count += 1;
    }

    // Find removed columns (in local but not in mem)
    var removed_cols: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var removed_lens: [MAX_ITEMS]usize = undefined;
    var removed_count: usize = 0;

    // Find added columns (in mem but not in local)
    var added_cols: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var added_lens: [MAX_ITEMS]usize = undefined;
    var added_count: usize = 0;

    for (0..local_count) |i| {
        const col = local_cols[i][0..local_lens[i]];
        var found = false;
        for (0..mem_count) |j| {
            if (std.mem.eql(u8, col, mem_cols[j][0..mem_lens[j]])) {
                found = true;
                break;
            }
        }
        if (!found and removed_count < MAX_ITEMS) {
            @memcpy(removed_cols[removed_count][0..col.len], col);
            removed_lens[removed_count] = col.len;
            removed_count += 1;
        }
    }

    for (0..mem_count) |i| {
        const col = mem_cols[i][0..mem_lens[i]];
        var found = false;
        for (0..local_count) |j| {
            if (std.mem.eql(u8, col, local_cols[j][0..local_lens[j]])) {
                found = true;
                break;
            }
        }
        if (!found and added_count < MAX_ITEMS) {
            @memcpy(added_cols[added_count][0..col.len], col);
            added_lens[added_count] = col.len;
            added_count += 1;
        }
    }

    // Check if this is a CRR table
    const is_crr = checkIsCrr(local_db, table_name);

    // Begin alter if CRR
    if (is_crr) {
        const begin_sql = std.fmt.bufPrintZ(&buf, "SELECT crsql_begin_alter('{s}')", .{table_name}) catch return error.BufferOverflow;
        var begin_stmt: ?*api.sqlite3_stmt = null;
        rc = api.prepare_v2(local_db, begin_sql, -1, &begin_stmt, null);
        if (rc != api.SQLITE_OK) return error.SqliteError;
        _ = api.step(begin_stmt);
        _ = api.finalize(begin_stmt);
    }

    // Drop columns
    try dropColumns(local_db, table_name, removed_cols[0..removed_count], removed_lens[0..removed_count]);

    // Add columns
    try addColumns(local_db, table_name, added_cols[0..added_count], added_lens[0..added_count], mem_db);

    // Update indices
    try maybeUpdateIndices(local_db, table_name, mem_db);

    // Commit alter if CRR
    if (is_crr) {
        const commit_sql = std.fmt.bufPrintZ(&buf, "SELECT crsql_commit_alter('{s}')", .{table_name}) catch return error.BufferOverflow;
        var commit_stmt: ?*api.sqlite3_stmt = null;
        rc = api.prepare_v2(local_db, commit_sql, -1, &commit_stmt, null);
        if (rc != api.SQLITE_OK) return error.SqliteError;
        _ = api.step(commit_stmt);
        _ = api.finalize(commit_stmt);
    }
}

fn checkIsCrr(db: ?*api.sqlite3, table_name: []const u8) bool {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf,
        \\SELECT count(*) FROM sqlite_master 
        \\WHERE type='table' AND name='{s}__crsql_clock'
    , .{table_name}) catch return false;

    var stmt: ?*api.sqlite3_stmt = null;
    const rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return false;
    defer _ = api.finalize(stmt);

    if (api.step(stmt) == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0) > 0;
    }
    return false;
}

fn dropColumns(db: ?*api.sqlite3, table_name: []const u8, cols: [][MAX_NAME_LEN]u8, lens: []usize) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Drop fractindex view if it exists
    const drop_view_sql = std.fmt.bufPrintZ(&buf, "DROP VIEW IF EXISTS \"{s}_fractindex\"", .{table_name}) catch return error.BufferOverflow;
    _ = api.exec(db, drop_view_sql, null, null, null);

    for (0..cols.len) |i| {
        const col = cols[i][0..lens[i]];
        const sql = std.fmt.bufPrintZ(&buf, "ALTER TABLE \"{s}\" DROP COLUMN \"{s}\"", .{ table_name, col }) catch continue;
        if (api.exec(db, sql, null, null, null) != api.SQLITE_OK) {
            return error.SqliteError;
        }
    }
}

fn addColumns(
    db: ?*api.sqlite3,
    table_name: []const u8,
    cols: [][MAX_NAME_LEN]u8,
    lens: []usize,
    mem_db: ?*api.sqlite3,
) !void {
    if (cols.len == 0) return;

    // For each column to add, get its info from mem_db
    for (0..cols.len) |i| {
        const col_name = cols[i][0..lens[i]];
        try addColumn(db, table_name, col_name, mem_db);
    }
}

fn addColumn(
    db: ?*api.sqlite3,
    table_name: []const u8,
    col_name: []const u8,
    mem_db: ?*api.sqlite3,
) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;

    // Get column info from pragma_table_info
    const info_sql = "SELECT name, type, \"notnull\", dflt_value, pk FROM pragma_table_info(?) WHERE name = ?";

    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(mem_db, info_sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(stmt);

    // Bind table name
    var table_buf: [MAX_NAME_LEN + 1]u8 = undefined;
    @memcpy(table_buf[0..table_name.len], table_name);
    table_buf[table_name.len] = 0;
    const table_ptr: [*:0]const u8 = @ptrCast(&table_buf);
    rc = api.bind_text(stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    // Bind column name
    var col_buf: [MAX_NAME_LEN + 1]u8 = undefined;
    @memcpy(col_buf[0..col_name.len], col_name);
    col_buf[col_name.len] = 0;
    const col_ptr: [*:0]const u8 = @ptrCast(&col_buf);
    rc = api.bind_text(stmt, 2, col_ptr, @intCast(col_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    if (api.step(stmt) != api.SQLITE_ROW) {
        return error.SqliteError;
    }

    const is_pk = api.column_int64(stmt, 4) != 0;
    if (is_pk) {
        // Cannot add PK columns via automigrate
        return error.CannotAddPrimaryKey;
    }

    const col_type_ptr = api.column_text(stmt, 1);
    const col_type: []const u8 = if (col_type_ptr) |p| std.mem.span(p) else "";

    const notnull = api.column_int64(stmt, 2) != 0;

    // Get default value
    const dflt_type = api.column_type(stmt, 3);
    var dflt_str: []const u8 = "";
    var dflt_buf: [256]u8 = undefined;
    if (dflt_type != api.SQLITE_NULL) {
        if (api.column_text(stmt, 3)) |dflt_ptr| {
            const dflt = std.mem.span(dflt_ptr);
            const written = std.fmt.bufPrint(&dflt_buf, "DEFAULT {s}", .{dflt}) catch "";
            dflt_str = written;
        }
    }

    // Build ALTER TABLE statement
    const notnull_str: []const u8 = if (notnull) "NOT NULL " else "";
    const sql = std.fmt.bufPrintZ(&buf, "ALTER TABLE \"{s}\" ADD COLUMN \"{s}\" {s} {s}{s}", .{
        table_name,
        col_name,
        col_type,
        notnull_str,
        dflt_str,
    }) catch return error.BufferOverflow;

    rc = api.exec(db, sql, null, null, null);
    if (rc != api.SQLITE_OK) {
        return error.SqliteError;
    }
}

fn maybeUpdateIndices(db: ?*api.sqlite3, table_name: []const u8, mem_db: ?*api.sqlite3) !void {
    // Get indices from both databases (excluding pk indices)
    const sql = "SELECT name FROM pragma_index_list(?) WHERE origin != 'pk'";

    var local_indices: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var local_lens: [MAX_ITEMS]usize = undefined;
    var local_count: usize = 0;

    var mem_indices: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var mem_lens: [MAX_ITEMS]usize = undefined;
    var mem_count: usize = 0;

    var table_buf: [MAX_NAME_LEN + 1]u8 = undefined;
    @memcpy(table_buf[0..table_name.len], table_name);
    table_buf[table_name.len] = 0;
    const table_ptr: [*:0]const u8 = @ptrCast(&table_buf);

    // Query local indices
    var local_stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, sql, -1, &local_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(local_stmt);

    rc = api.bind_text(local_stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    while (api.step(local_stmt) == api.SQLITE_ROW) {
        const name_ptr = api.column_text(local_stmt, 0) orelse continue;
        const name = std.mem.span(name_ptr);
        if (name.len >= MAX_NAME_LEN or local_count >= MAX_ITEMS) continue;
        @memcpy(local_indices[local_count][0..name.len], name);
        local_lens[local_count] = name.len;
        local_count += 1;
    }

    // Query mem indices
    var mem_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(mem_db, sql, -1, &mem_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(mem_stmt);

    rc = api.bind_text(mem_stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    while (api.step(mem_stmt) == api.SQLITE_ROW) {
        const name_ptr = api.column_text(mem_stmt, 0) orelse continue;
        const name = std.mem.span(name_ptr);
        if (name.len >= MAX_NAME_LEN or mem_count >= MAX_ITEMS) continue;
        @memcpy(mem_indices[mem_count][0..name.len], name);
        mem_lens[mem_count] = name.len;
        mem_count += 1;
    }

    // Find indices to drop (in local but not in mem)
    var removed: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var removed_lens: [MAX_ITEMS]usize = undefined;
    var removed_count: usize = 0;

    // Find indices that exist in both (may need modification)
    var maybe_modified: [MAX_ITEMS][MAX_NAME_LEN]u8 = undefined;
    var modified_lens: [MAX_ITEMS]usize = undefined;
    var modified_count: usize = 0;

    for (0..local_count) |i| {
        const idx = local_indices[i][0..local_lens[i]];
        var found = false;
        for (0..mem_count) |j| {
            if (std.mem.eql(u8, idx, mem_indices[j][0..mem_lens[j]])) {
                found = true;
                if (modified_count < MAX_ITEMS) {
                    @memcpy(maybe_modified[modified_count][0..idx.len], idx);
                    modified_lens[modified_count] = idx.len;
                    modified_count += 1;
                }
                break;
            }
        }
        if (!found and removed_count < MAX_ITEMS) {
            @memcpy(removed[removed_count][0..idx.len], idx);
            removed_lens[removed_count] = idx.len;
            removed_count += 1;
        }
    }

    // Drop removed indices
    try dropIndices(db, removed[0..removed_count], removed_lens[0..removed_count]);

    // Check if modified indices need to be recreated
    for (0..modified_count) |i| {
        const idx = maybe_modified[i][0..modified_lens[i]];
        try maybeRecreateIndex(db, table_name, idx, mem_db);
    }
}

fn dropIndices(db: ?*api.sqlite3, indices: [][MAX_NAME_LEN]u8, lens: []usize) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    for (0..indices.len) |i| {
        const idx = indices[i][0..lens[i]];
        const sql = std.fmt.bufPrintZ(&buf, "DROP INDEX IF EXISTS \"{s}\"", .{idx}) catch continue;
        _ = api.exec(db, sql, null, null, null);
    }
}

fn maybeRecreateIndex(db: ?*api.sqlite3, table_name: []const u8, idx_name: []const u8, mem_db: ?*api.sqlite3) !void {
    // Check if uniqueness differs
    var table_buf: [MAX_NAME_LEN + 1]u8 = undefined;
    @memcpy(table_buf[0..table_name.len], table_name);
    table_buf[table_name.len] = 0;
    const table_ptr: [*:0]const u8 = @ptrCast(&table_buf);

    var idx_buf: [MAX_NAME_LEN + 1]u8 = undefined;
    @memcpy(idx_buf[0..idx_name.len], idx_name);
    idx_buf[idx_name.len] = 0;
    const idx_ptr: [*:0]const u8 = @ptrCast(&idx_buf);

    // Check uniqueness in both
    var local_stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, IS_UNIQUE_IDX_SQL, -1, &local_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(local_stmt);

    rc = api.bind_text(local_stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    rc = api.bind_text(local_stmt, 2, idx_ptr, @intCast(idx_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    const local_step_rc = api.step(local_stmt);
    if (local_step_rc != api.SQLITE_ROW) return;
    const local_unique = api.column_int64(local_stmt, 0);

    var mem_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(mem_db, IS_UNIQUE_IDX_SQL, -1, &mem_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(mem_stmt);

    rc = api.bind_text(mem_stmt, 1, table_ptr, @intCast(table_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    rc = api.bind_text(mem_stmt, 2, idx_ptr, @intCast(idx_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    const mem_step_rc = api.step(mem_stmt);
    if (mem_step_rc != api.SQLITE_ROW) {
        // Index doesn't exist in mem_db - this shouldn't happen if we got here
        return error.DebugMemStepFailed;
    }
    const mem_unique = api.column_int64(mem_stmt, 0);

    // If uniqueness differs, recreate index
    // NOTE: Must finalize statements BEFORE dropping index to avoid "database is locked"
    if (local_unique != mem_unique) {
        _ = api.finalize(local_stmt);
        local_stmt = null; // prevent double-finalize in defer
        _ = api.finalize(mem_stmt);
        mem_stmt = null; // prevent double-finalize in defer
        try recreateIndex(db, idx_name);
        return;
    }

    // Done with uniqueness check, finalize those statements before column check
    _ = api.finalize(local_stmt);
    local_stmt = null;
    _ = api.finalize(mem_stmt);
    mem_stmt = null;

    // Check if columns differ
    var local_cols_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(db, IDX_COLS_SQL, -1, &local_cols_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(local_cols_stmt);

    rc = api.bind_text(local_cols_stmt, 1, idx_ptr, @intCast(idx_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    var mem_cols_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(mem_db, IDX_COLS_SQL, -1, &mem_cols_stmt, null);
    if (rc != api.SQLITE_OK) return error.SqliteError;
    defer _ = api.finalize(mem_cols_stmt);

    rc = api.bind_text(mem_cols_stmt, 1, idx_ptr, @intCast(idx_name.len), api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return error.SqliteError;

    // Compare columns
    while (true) {
        const local_rc = api.step(local_cols_stmt);
        const mem_rc = api.step(mem_cols_stmt);

        if (local_rc == api.SQLITE_ROW and mem_rc == api.SQLITE_ROW) {
            const local_col = api.column_text(local_cols_stmt, 0);
            const mem_col = api.column_text(mem_cols_stmt, 0);

            if (local_col == null or mem_col == null) {
                // Finalize statements before dropping index
                _ = api.finalize(local_cols_stmt);
                local_cols_stmt = null;
                _ = api.finalize(mem_cols_stmt);
                mem_cols_stmt = null;
                try recreateIndex(db, idx_name);
                return;
            }

            if (!std.mem.eql(u8, std.mem.span(local_col.?), std.mem.span(mem_col.?))) {
                // Finalize statements before dropping index
                _ = api.finalize(local_cols_stmt);
                local_cols_stmt = null;
                _ = api.finalize(mem_cols_stmt);
                mem_cols_stmt = null;
                try recreateIndex(db, idx_name);
                return;
            }
        } else if (local_rc != mem_rc) {
            // Different number of columns
            // Finalize statements before dropping index
            _ = api.finalize(local_cols_stmt);
            local_cols_stmt = null;
            _ = api.finalize(mem_cols_stmt);
            mem_cols_stmt = null;
            try recreateIndex(db, idx_name);
            return;
        } else {
            // Both done
            break;
        }
    }
}

fn recreateIndex(db: ?*api.sqlite3, idx_name: []const u8) !void {
    var buf: [SQL_BUF_SIZE]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "DROP INDEX IF EXISTS \"{s}\"", .{idx_name}) catch return error.BufferOverflow;
    // Drop index - ignore errors since the index might not exist or might be auto-dropped
    _ = api.exec(db, sql, null, null, null);
    // Index will be recreated when schema is re-applied
}

/// Register the crsql_automigrate function with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    // Register with 1 argument (schema only)
    var rc = api.create_function_v2(
        db,
        "crsql_automigrate",
        1, // nArg: 1 argument (schema)
        api.SQLITE_UTF8,
        null, // pApp: no user data
        &crsqlAutomigrateFunc,
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register with 2 arguments (schema, cleanup_sql)
    rc = api.create_function_v2(
        db,
        "crsql_automigrate",
        2,
        api.SQLITE_UTF8,
        null,
        &crsqlAutomigrateFunc,
        null,
        null,
        null,
    );
    return rc;
}

test "stripCrrStatements removes crsql_as_crr lines" {
    var buf: [4096]u8 = undefined;
    const input =
        \\CREATE TABLE foo (a PRIMARY KEY);
        \\SELECT crsql_as_crr('foo');
        \\CREATE TABLE bar (b);
    ;
    const result = stripCrrStatements(input, &buf) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, result, "crsql_as_crr") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "CREATE TABLE foo") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "CREATE TABLE bar") != null);
}

test "toLower works correctly" {
    var buf: [256]u8 = undefined;
    const result = toLower("CRSQL_AS_CRR", &buf);
    try std.testing.expectEqualStrings("crsql_as_crr", result);
}
