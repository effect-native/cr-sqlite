//! crsql_pack_columns UDF - packs SQLite values into wire format blob
//!
//! Implements `crsql_pack_columns(...)` as a variadic SQL function that
//! encodes 1+ SQLite values into the packed column wire format.
//!
//! Wire format: `[num_columns:u8, ...encoded_columns]`
//!
//! Example:
//! ```sql
//! SELECT quote(crsql_pack_columns(4, 5));  -- returns X'0209040905'
//! -- Breakdown: 02=2cols, 09=int1byte, 04=4, 09=int1byte, 05=5
//! ```

const std = @import("std");
const api = @import("ffi/api.zig");
const codec = @import("codec.zig");

/// Implementation of `crsql_pack_columns(...)` SQL function.
/// Takes 1+ SQLite values and returns a packed blob.
fn packColumnsFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Validate argument count
    if (argc < 1) {
        api.result_error(pCtx, "crsql_pack_columns requires at least 1 argument", -1);
        return;
    }

    // Use page_allocator for temporary allocation
    const allocator = std.heap.page_allocator;

    // Convert argc to usize for array operations
    const arg_count: usize = @intCast(argc);

    // Allocate temporary array for codec.Value
    const values = allocator.alloc(codec.Value, arg_count) catch {
        api.result_error_nomem(pCtx);
        return;
    };
    defer allocator.free(values);

    // Convert each SQLite value to codec.Value
    var i: usize = 0;
    while (i < arg_count) : (i += 1) {
        const val = argv[i];
        const val_type = api.value_type(val);

        values[i] = switch (val_type) {
            api.SQLITE_NULL => .Null,
            api.SQLITE_INTEGER => .{ .Integer = api.value_int64(val) },
            api.SQLITE_FLOAT => .{ .Float = api.value_double(val) },
            api.SQLITE_TEXT => blk: {
                const text_ptr = api.value_text(val);
                if (text_ptr == null) {
                    break :blk .Null;
                }
                const len: usize = @intCast(api.value_bytes(val));
                // Create a slice from the pointer and length
                const text_slice: []const u8 = text_ptr.?[0..len];
                break :blk .{ .Text = text_slice };
            },
            api.SQLITE_BLOB => blk: {
                const blob_ptr = api.value_blob(val);
                if (blob_ptr == null) {
                    // Zero-length blob
                    break :blk .{ .Blob = &[_]u8{} };
                }
                const len: usize = @intCast(api.value_bytes(val));
                const blob_bytes: [*]const u8 = @ptrCast(blob_ptr.?);
                break :blk .{ .Blob = blob_bytes[0..len] };
            },
            else => .Null,
        };
    }

    // Pack the values using codec
    const packed_blob = codec.pack(allocator, values) catch |err| {
        switch (err) {
            error.TooManyColumns => api.result_error(pCtx, "crsql_pack_columns: too many columns (max 255)", -1),
            error.LengthOverflow => api.result_error(pCtx, "crsql_pack_columns: value too large", -1),
            error.OutOfMemory => api.result_error_nomem(pCtx),
            else => api.result_error(pCtx, "crsql_pack_columns: encoding error", -1),
        }
        return;
    };
    defer allocator.free(packed_blob);

    // Return the blob using SQLITE_TRANSIENT so SQLite copies it
    // (we free the memory immediately after this call)
    const len: c_int = @intCast(packed_blob.len);
    api.result_blob(pCtx, packed_blob.ptr, len, api.getTransientDestructor());
}

/// Register the crsql_pack_columns function with a database connection.
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_function_v2(
        db,
        "crsql_pack_columns",
        -1, // variadic: accepts any number of arguments
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC | api.SQLITE_INNOCUOUS,
        null, // pApp: no user data
        &packColumnsFunc,
        null, // xStep: not an aggregate
        null, // xFinal: not an aggregate
        null, // xDestroy: no cleanup needed
    );
}

test "packColumnsFunc basic validation" {
    // Compile-time check that the function signature is correct
    const func: api.ScalarFn = &packColumnsFunc;
    _ = func;
}
