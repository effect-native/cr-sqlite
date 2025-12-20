//! crsql_unpack_columns Virtual Table Module
//!
//! A read-only (INNOCUOUS) virtual table that unpacks binary blob format
//! produced by crsql_pack_columns() into individual rows.
//!
//! Schema: CREATE TABLE x(cell ANY, package BLOB hidden)
//!
//! Usage:
//! ```sql
//! SELECT cell FROM crsql_unpack_columns WHERE package = crsql_pack_columns(1, 'hello', x'DEAD');
//! -- Returns 3 rows: 1, 'hello', X'DEAD'
//! ```
//!
//! Reference: core/rs/core/src/unpack_columns_vtab.rs

const std = @import("std");
const vtab = @import("sqlite/vtab.zig");
const api = @import("ffi/api.zig");
const codec = @import("codec.zig");

/// Column indices for the virtual table schema
const Columns = enum(c_int) {
    cell = 0,
    package = 1,
};

// =============================================================================
// Virtual Table Structure
// =============================================================================

/// unpack_columns virtual table instance
const UnpackColumnsVTab = extern struct {
    base: vtab.VTab,
};

// =============================================================================
// Cursor Structure
// =============================================================================

/// Maximum number of unpacked values we support
/// (matches codec's 255 max columns, but we use fixed buffer to avoid allocation)
const MAX_UNPACK_VALUES = 255;

/// unpack_columns cursor - holds unpacked values during iteration
const UnpackColumnsCursor = extern struct {
    base: vtab.VTabCursor,
    /// Current position in the unpacked values array
    current_index: usize,
    /// Number of unpacked values
    num_values: usize,
    /// Storage for the unpacked values (fixed-size array to avoid allocation)
    /// We store type tags and pointers to the data in the original blob
    value_types: [MAX_UNPACK_VALUES]ValueType,
    /// For integers
    int_values: [MAX_UNPACK_VALUES]i64,
    /// For floats
    float_values: [MAX_UNPACK_VALUES]f64,
    /// Pointer to the original package blob (kept alive by SQLite during query)
    package_ptr: ?[*]const u8,
    package_len: usize,
    /// For text/blob values, we store offsets into the package
    data_offsets: [MAX_UNPACK_VALUES]usize,
    data_lengths: [MAX_UNPACK_VALUES]usize,
    /// Did decoding fail?
    decode_error: bool,
};

/// Type tag for unpacked values
const ValueType = enum(u8) {
    null = 0,
    integer = 1,
    float = 2,
    text = 3,
    blob = 4,
};

// =============================================================================
// SQLite API Wrappers
// =============================================================================

fn declareVtab(db: ?*api.sqlite3, schema: [*:0]const u8) c_int {
    return api.declare_vtab(@ptrCast(db), schema);
}

fn sqliteMalloc(n: c_int) ?*anyopaque {
    return api.malloc(n);
}

fn sqliteFree(ptr: ?*anyopaque) void {
    api.free(ptr);
}

fn toApiDb(db: ?*vtab.sqlite3) ?*api.sqlite3 {
    return @ptrCast(db);
}

fn setVtabError(pVTab: ?*vtab.VTab, msg: []const u8) void {
    if (pVTab) |vt| {
        // Free any existing error message
        if (vt.zErrMsg != null) {
            sqliteFree(vt.zErrMsg);
        }
        // Allocate and set new error message
        const alloc = sqliteMalloc(@intCast(msg.len + 1));
        if (alloc) |ptr| {
            const err_ptr: [*]u8 = @ptrCast(ptr);
            @memcpy(err_ptr[0..msg.len], msg);
            err_ptr[msg.len] = 0;
            vt.zErrMsg = err_ptr;
        }
    }
}

// =============================================================================
// Value Decoding (from packed format)
// =============================================================================

/// Decode packed blob into cursor's value arrays
/// Returns true on success, false on error
fn decodePackage(cursor: *UnpackColumnsCursor, package: []const u8) bool {
    cursor.num_values = 0;
    cursor.decode_error = false;

    if (package.len == 0) {
        // Empty package = no values
        return true;
    }

    if (package.len < 1) {
        cursor.decode_error = true;
        return false;
    }

    var idx: usize = 0;
    const num_columns: usize = package[idx];
    idx += 1;

    if (num_columns > MAX_UNPACK_VALUES) {
        cursor.decode_error = true;
        return false;
    }

    var produced: usize = 0;
    while (produced < num_columns) : (produced += 1) {
        if (idx >= package.len) {
            cursor.decode_error = true;
            return false;
        }

        const type_byte = package[idx];
        idx += 1;

        const tag: u8 = type_byte & 0x07;
        const intlen: usize = type_byte >> 3;

        switch (tag) {
            @intFromEnum(codec.ColumnType.integer) => {
                if (intlen > 8) {
                    cursor.decode_error = true;
                    return false;
                }
                if (package.len - idx < intlen) {
                    cursor.decode_error = true;
                    return false;
                }

                const nbytes = package[idx .. idx + intlen];
                idx += intlen;
                cursor.value_types[produced] = .integer;
                cursor.int_values[produced] = readIntBig(nbytes);
            },
            @intFromEnum(codec.ColumnType.float) => {
                if (package.len - idx < 8) {
                    cursor.decode_error = true;
                    return false;
                }

                const buf_ptr: *const [8]u8 = @ptrCast(package[idx .. idx + 8].ptr);
                const bits = std.mem.readInt(u64, buf_ptr, .big);
                idx += 8;
                cursor.value_types[produced] = .float;
                cursor.float_values[produced] = @bitCast(bits);
            },
            @intFromEnum(codec.ColumnType.text) => {
                if (intlen > 4) {
                    cursor.decode_error = true;
                    return false;
                }
                if (package.len - idx < intlen) {
                    cursor.decode_error = true;
                    return false;
                }

                const len_i64 = readIntBig(package[idx .. idx + intlen]);
                idx += intlen;
                if (len_i64 < 0) {
                    cursor.decode_error = true;
                    return false;
                }

                const len: usize = std.math.cast(usize, len_i64) orelse {
                    cursor.decode_error = true;
                    return false;
                };
                if (package.len - idx < len) {
                    cursor.decode_error = true;
                    return false;
                }

                cursor.value_types[produced] = .text;
                cursor.data_offsets[produced] = idx;
                cursor.data_lengths[produced] = len;
                idx += len;
            },
            @intFromEnum(codec.ColumnType.blob) => {
                if (intlen > 4) {
                    cursor.decode_error = true;
                    return false;
                }
                if (package.len - idx < intlen) {
                    cursor.decode_error = true;
                    return false;
                }

                const len_i64 = readIntBig(package[idx .. idx + intlen]);
                idx += intlen;
                if (len_i64 < 0) {
                    cursor.decode_error = true;
                    return false;
                }

                const len: usize = std.math.cast(usize, len_i64) orelse {
                    cursor.decode_error = true;
                    return false;
                };
                if (package.len - idx < len) {
                    cursor.decode_error = true;
                    return false;
                }

                cursor.value_types[produced] = .blob;
                cursor.data_offsets[produced] = idx;
                cursor.data_lengths[produced] = len;
                idx += len;
            },
            @intFromEnum(codec.ColumnType.null) => {
                cursor.value_types[produced] = .null;
            },
            else => {
                cursor.decode_error = true;
                return false;
            },
        }
    }

    cursor.num_values = num_columns;
    return true;
}

/// Read big-endian integer (same as codec.zig)
fn readIntBig(bytes: []const u8) i64 {
    if (bytes.len == 0) return 0;

    var buf: [8]u8 = .{0} ** 8;
    @memcpy(buf[8 - bytes.len ..], bytes);

    const unsigned = std.mem.readInt(u64, &buf, .big);
    return @bitCast(unsigned);
}

// =============================================================================
// Virtual Table Callbacks
// =============================================================================

/// xConnect - Connect to the virtual table
fn unpackColumnsConnect(
    db: ?*vtab.sqlite3,
    _: ?*anyopaque, // pAux
    _: c_int, // argc
    _: [*c]const [*c]const u8, // argv
    ppVTab: [*c]?*vtab.VTab,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int {
    _ = pzErr;

    // Declare the schema: cell ANY, package BLOB hidden
    const schema = "CREATE TABLE x(cell ANY, package BLOB hidden)";
    const rc = declareVtab(toApiDb(db), schema);
    if (rc != vtab.SQLITE_OK) {
        return rc;
    }

    // Allocate the vtab structure
    const pNew = sqliteMalloc(@sizeOf(UnpackColumnsVTab));
    if (pNew == null) {
        return vtab.SQLITE_NOMEM;
    }

    const pVTab: *UnpackColumnsVTab = @ptrCast(@alignCast(pNew));
    @memset(std.mem.asBytes(pVTab), 0);

    ppVTab.* = &pVTab.base;
    return vtab.SQLITE_OK;
}

/// xDisconnect - Disconnect from the virtual table
fn unpackColumnsDisconnect(pVTab: ?*vtab.VTab) callconv(.c) c_int {
    if (pVTab) |vt| {
        sqliteFree(vt);
    }
    return vtab.SQLITE_OK;
}

/// xBestIndex - Query planning
/// MUST require an EQ constraint on the hidden `package` column
fn unpackColumnsBestIndex(pVTab: ?*vtab.VTab, pIdxInfo: ?*vtab.IndexInfo) callconv(.c) c_int {
    if (pIdxInfo == null) return vtab.SQLITE_ERROR;
    const info = pIdxInfo.?;

    // Look for usable EQ constraint on package column (column 1)
    var found_package_constraint = false;
    var constraint_index: usize = 0;

    const n_constraint: usize = @intCast(info.nConstraint);
    for (0..n_constraint) |i| {
        const constraint = info.aConstraint[i];

        // Check if this is a usable EQ constraint on the package column
        if (constraint.usable != 0 and
            constraint.iColumn == @intFromEnum(Columns.package) and
            constraint.op == vtab.SQLITE_INDEX_CONSTRAINT_EQ)
        {
            found_package_constraint = true;
            constraint_index = i;
            break;
        }
    }

    if (!found_package_constraint) {
        // No usable package constraint - return SQLITE_CONSTRAINT
        // This tells SQLite that the query cannot be executed without the constraint
        setVtabError(pVTab, "crsql_unpack_columns requires WHERE package = ...");
        return vtab.SQLITE_CONSTRAINT;
    }

    // Mark the package constraint as consumed
    info.aConstraintUsage[constraint_index].argvIndex = 1; // Pass as first argument to xFilter
    info.aConstraintUsage[constraint_index].omit = 1; // SQLite doesn't need to check it again

    // Set cost estimates
    info.estimatedCost = 10.0;
    info.estimatedRows = 10;

    return vtab.SQLITE_OK;
}

/// xOpen - Create a cursor
fn unpackColumnsOpen(pVTab: ?*vtab.VTab, ppCursor: [*c]?*vtab.VTabCursor) callconv(.c) c_int {
    _ = pVTab;

    const pCur = sqliteMalloc(@sizeOf(UnpackColumnsCursor));
    if (pCur == null) {
        return vtab.SQLITE_NOMEM;
    }

    const cursor: *UnpackColumnsCursor = @ptrCast(@alignCast(pCur));
    @memset(std.mem.asBytes(cursor), 0);

    ppCursor.* = &cursor.base;
    return vtab.SQLITE_OK;
}

/// xClose - Close a cursor
fn unpackColumnsClose(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    if (pCursor) |cur| {
        sqliteFree(cur);
    }
    return vtab.SQLITE_OK;
}

/// xFilter - Begin a scan with the package blob constraint
fn unpackColumnsFilter(
    pCursor: ?*vtab.VTabCursor,
    _: c_int, // idxNum
    _: [*c]const u8, // idxStr
    argc: c_int,
    argv: [*c]?*vtab.sqlite3_value,
) callconv(.c) c_int {
    if (pCursor == null) return vtab.SQLITE_ERROR;

    const cursor: *UnpackColumnsCursor = @ptrCast(@alignCast(pCursor));

    // Reset cursor state
    cursor.current_index = 0;
    cursor.num_values = 0;
    cursor.package_ptr = null;
    cursor.package_len = 0;
    cursor.decode_error = false;

    // We should have exactly one argument: the package blob
    if (argc < 1) {
        // No package provided - this shouldn't happen if xBestIndex worked correctly
        setVtabError(cursor.base.pVtab, "Zero args passed to filter");
        return vtab.SQLITE_MISUSE;
    }

    // Get the package blob from argv[0]
    const package_val = argv[0];
    const blob_ptr = api.value_blob(@ptrCast(package_val));
    const blob_len: usize = @intCast(api.value_bytes(@ptrCast(package_val)));

    if (blob_ptr == null and blob_len > 0) {
        // Error getting blob
        cursor.decode_error = true;
        return vtab.SQLITE_ERROR;
    }

    // Store pointer to the original blob
    if (blob_ptr) |ptr| {
        cursor.package_ptr = @ptrCast(ptr);
        cursor.package_len = blob_len;
    } else {
        cursor.package_ptr = null;
        cursor.package_len = 0;
    }

    // Decode the package
    if (cursor.package_ptr) |pkg_ptr| {
        const package_slice = pkg_ptr[0..cursor.package_len];
        if (!decodePackage(cursor, package_slice)) {
            // Decode failed - return error
            setVtabError(cursor.base.pVtab, "Invalid package format");
            return vtab.SQLITE_ERROR;
        }
    }
    // If package_ptr is null, num_values stays 0 (empty package)

    return vtab.SQLITE_OK;
}

/// xNext - Advance to next row
fn unpackColumnsNext(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    if (pCursor == null) return vtab.SQLITE_ERROR;

    const cursor: *UnpackColumnsCursor = @ptrCast(@alignCast(pCursor));
    cursor.current_index += 1;

    return vtab.SQLITE_OK;
}

/// xEof - Check if at end of results
fn unpackColumnsEof(pCursor: ?*vtab.VTabCursor) callconv(.c) c_int {
    if (pCursor == null) return 1;

    const cursor: *UnpackColumnsCursor = @ptrCast(@alignCast(pCursor));

    // At EOF if we've passed all values or if there was a decode error
    if (cursor.decode_error or cursor.current_index >= cursor.num_values) {
        return 1;
    }
    return 0;
}

/// xColumn - Return column value
fn unpackColumnsColumn(
    pCursor: ?*vtab.VTabCursor,
    pCtx: ?*vtab.sqlite3_context,
    col: c_int,
) callconv(.c) c_int {
    if (pCursor == null) return vtab.SQLITE_ERROR;

    const cursor: *UnpackColumnsCursor = @ptrCast(@alignCast(pCursor));
    const ctx: ?*api.sqlite3_context = @ptrCast(pCtx);

    if (col == @intFromEnum(Columns.cell)) {
        // Return the current unpacked cell value
        if (cursor.current_index >= cursor.num_values) {
            api.result_null(ctx);
            return vtab.SQLITE_OK;
        }

        const idx = cursor.current_index;
        switch (cursor.value_types[idx]) {
            .null => {
                api.result_null(ctx);
            },
            .integer => {
                api.result_int64(ctx, cursor.int_values[idx]);
            },
            .float => {
                api.result_double(ctx, cursor.float_values[idx]);
            },
            .text => {
                // Get text from the original package blob
                if (cursor.package_ptr) |pkg_ptr| {
                    const offset = cursor.data_offsets[idx];
                    const len = cursor.data_lengths[idx];
                    const text_ptr: [*c]const u8 = @ptrCast(pkg_ptr + offset);
                    api.result_text(ctx, text_ptr, @intCast(len), api.getTransientDestructor());
                } else {
                    api.result_null(ctx);
                }
            },
            .blob => {
                // Get blob from the original package blob
                if (cursor.package_ptr) |pkg_ptr| {
                    const offset = cursor.data_offsets[idx];
                    const len = cursor.data_lengths[idx];
                    const blob_ptr: ?*const anyopaque = @ptrCast(pkg_ptr + offset);
                    api.result_blob(ctx, blob_ptr, @intCast(len), api.getTransientDestructor());
                } else {
                    api.result_null(ctx);
                }
            },
        }
    } else {
        // Package column (hidden) - shouldn't typically be requested
        api.result_null(ctx);
    }

    return vtab.SQLITE_OK;
}

/// xRowid - Return current row ID
fn unpackColumnsRowid(pCursor: ?*vtab.VTabCursor, pRowid: *i64) callconv(.c) c_int {
    if (pCursor == null) return vtab.SQLITE_ERROR;

    const cursor: *UnpackColumnsCursor = @ptrCast(@alignCast(pCursor));
    pRowid.* = @intCast(cursor.current_index);

    return vtab.SQLITE_OK;
}

// =============================================================================
// Module Definition
// =============================================================================

/// The crsql_unpack_columns module definition
/// Read-only (INNOCUOUS) - xUpdate is null
pub const unpack_columns_module = vtab.Module{
    .iVersion = 0,
    .xCreate = null, // Eponymous-only (no CREATE VIRTUAL TABLE support)
    .xConnect = unpackColumnsConnect,
    .xBestIndex = unpackColumnsBestIndex,
    .xDisconnect = unpackColumnsDisconnect,
    .xDestroy = null, // Eponymous-only
    .xOpen = unpackColumnsOpen,
    .xClose = unpackColumnsClose,
    .xFilter = unpackColumnsFilter,
    .xNext = unpackColumnsNext,
    .xEof = unpackColumnsEof,
    .xColumn = unpackColumnsColumn,
    .xRowid = unpackColumnsRowid,
    .xUpdate = null, // Read-only (INNOCUOUS)
    .xBegin = null,
    .xSync = null,
    .xCommit = null,
    .xRollback = null,
    .xFindFunction = null,
    .xRename = null,
    .xSavepoint = null,
    .xRelease = null,
    .xRollbackTo = null,
    .xShadowName = null,
    .xIntegrity = null,
};

/// Register the crsql_unpack_columns virtual table module with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_module_v2(db, "crsql_unpack_columns", @ptrCast(&unpack_columns_module), null, null);
}

// =============================================================================
// Tests
// =============================================================================

test "module struct is properly configured" {
    try std.testing.expect(unpack_columns_module.xCreate == null); // Eponymous-only
    try std.testing.expect(unpack_columns_module.xConnect != null);
    try std.testing.expect(unpack_columns_module.xBestIndex != null);
    try std.testing.expect(unpack_columns_module.xDisconnect != null);
    try std.testing.expect(unpack_columns_module.xOpen != null);
    try std.testing.expect(unpack_columns_module.xClose != null);
    try std.testing.expect(unpack_columns_module.xFilter != null);
    try std.testing.expect(unpack_columns_module.xNext != null);
    try std.testing.expect(unpack_columns_module.xEof != null);
    try std.testing.expect(unpack_columns_module.xColumn != null);
    try std.testing.expect(unpack_columns_module.xRowid != null);
    // xUpdate is null for read-only (INNOCUOUS) vtab
    try std.testing.expect(unpack_columns_module.xUpdate == null);
}

test "decodePackage handles empty package" {
    var cursor: UnpackColumnsCursor = undefined;
    @memset(std.mem.asBytes(&cursor), 0);

    // Empty package should return true with 0 values
    const result = decodePackage(&cursor, &[_]u8{});
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(usize, 0), cursor.num_values);
}

test "decodePackage handles single null value" {
    var cursor: UnpackColumnsCursor = undefined;
    @memset(std.mem.asBytes(&cursor), 0);

    // Package with 1 null value: [1, 5] (1 column, null type)
    const package = [_]u8{ 1, @intFromEnum(codec.ColumnType.null) };
    const result = decodePackage(&cursor, &package);
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(usize, 1), cursor.num_values);
    try std.testing.expectEqual(ValueType.null, cursor.value_types[0]);
}

test "readIntBig handles various byte lengths" {
    // 0 bytes -> 0
    try std.testing.expectEqual(@as(i64, 0), readIntBig(&[_]u8{}));

    // 1 byte -> value
    try std.testing.expectEqual(@as(i64, 42), readIntBig(&[_]u8{42}));

    // 2 bytes big-endian
    try std.testing.expectEqual(@as(i64, 0x0102), readIntBig(&[_]u8{ 0x01, 0x02 }));
}
