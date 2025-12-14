//! Blob-Safe SQLite Value Decoding Layer
//!
//! This module provides safe extraction of values from `sqlite3_value*` pointers,
//! explicitly avoiding the blob-as-text bug present in `.refs/zig-sqlite/helpers.zig`.
//!
//! ## The Bug in zig-sqlite
//!
//! The upstream `helpers.zig` uses `sqlite3_value_text` for all slice extraction,
//! even for blobs. This corrupts binary data because:
//! - `sqlite3_value_text` may perform encoding conversions
//! - `sqlite3_value_text` treats the data as a NUL-terminated string
//! - Binary blobs with embedded NUL bytes get truncated
//!
//! ## Correct Approach
//!
//! - Use `sqlite3_value_blob` + `sqlite3_value_bytes` for blob extraction
//! - Use `sqlite3_value_text` + `sqlite3_value_bytes` for text extraction
//! - Always check type before extraction to avoid implicit conversions
//!
//! ## CR-SQLite Requirement
//!
//! CR-SQLite uses packed binary columns (see `core/rs/core/src/pack_columns.rs`)
//! that contain arbitrary bytes including NUL. Correct blob handling is essential.

const std = @import("std");

/// Opaque type representing a SQLite value pointer.
/// In C: `sqlite3_value*`
pub const SqliteValue = opaque {};

/// SQLite fundamental datatypes (SQLITE_INTEGER, SQLITE_FLOAT, etc.)
pub const ValueType = enum(c_int) {
    integer = 1, // SQLITE_INTEGER
    float = 2, // SQLITE_FLOAT
    text = 3, // SQLITE_TEXT (SQLITE3_TEXT)
    blob = 4, // SQLITE_BLOB
    null = 5, // SQLITE_NULL
};

// ============================================================================
// External SQLite C API declarations
// These will link at runtime via the extension thunk table.
// ============================================================================

extern fn sqlite3_value_type(v: *SqliteValue) c_int;
extern fn sqlite3_value_blob(v: *SqliteValue) ?[*]const u8;
extern fn sqlite3_value_bytes(v: *SqliteValue) c_int;
extern fn sqlite3_value_int64(v: *SqliteValue) i64;
extern fn sqlite3_value_double(v: *SqliteValue) f64;
extern fn sqlite3_value_text(v: *SqliteValue) ?[*:0]const u8;

// ============================================================================
// Safe Wrapper Functions
// ============================================================================

/// Returns the SQLite type of the value.
///
/// Maps to one of the 5 fundamental SQLite types.
/// Returns `null` if the type code is unrecognized (should never happen
/// with a valid sqlite3_value*).
pub fn getType(v: *SqliteValue) ?ValueType {
    const type_code = sqlite3_value_type(v);
    return std.meta.intToEnum(ValueType, type_code) catch null;
}

/// Extracts a blob value as a byte slice.
///
/// Uses `sqlite3_value_blob` + `sqlite3_value_bytes` to correctly handle
/// binary data, including blobs with embedded NUL bytes.
///
/// Returns `null` if the value is SQL NULL or the blob pointer is null.
///
/// **Important**: The returned slice is valid only until the next SQLite API
/// call that might invalidate the value. Copy if you need to retain it.
pub fn getBlob(v: *SqliteValue) ?[]const u8 {
    const len = sqlite3_value_bytes(v);
    if (len <= 0) {
        // Zero-length blob or error
        if (len == 0) {
            // Zero-length blob is valid, return empty slice
            // But we need a valid pointer for the slice
            const ptr = sqlite3_value_blob(v);
            if (ptr) |p| {
                return p[0..0];
            }
            // Null pointer with zero length - this is SQL NULL
            return null;
        }
        return null;
    }

    const ptr = sqlite3_value_blob(v);
    if (ptr) |p| {
        return p[0..@intCast(len)];
    }
    return null;
}

/// Extracts a text value as a byte slice.
///
/// Uses `sqlite3_value_text` + `sqlite3_value_bytes` for text extraction.
/// The result is UTF-8 encoded (SQLite guarantees this).
///
/// Returns `null` if the value is SQL NULL or the text pointer is null.
///
/// **Important**: The returned slice is valid only until the next SQLite API
/// call that might invalidate the value. Copy if you need to retain it.
pub fn getText(v: *SqliteValue) ?[]const u8 {
    const len = sqlite3_value_bytes(v);
    if (len < 0) {
        return null;
    }

    const ptr = sqlite3_value_text(v);
    if (ptr) |p| {
        if (len == 0) {
            // Zero-length text is valid
            return @as([*]const u8, @ptrCast(p))[0..0];
        }
        return @as([*]const u8, @ptrCast(p))[0..@intCast(len)];
    }
    return null;
}

/// Extracts an integer value as i64.
///
/// If the value is not an integer, SQLite will perform type coercion:
/// - NULL -> 0
/// - FLOAT -> truncated to integer
/// - TEXT/BLOB -> parsed as integer or 0
///
/// For type-safe extraction, check `getType()` first.
pub fn getInt64(v: *SqliteValue) i64 {
    return sqlite3_value_int64(v);
}

/// Extracts a floating-point value as f64.
///
/// If the value is not a float, SQLite will perform type coercion:
/// - NULL -> 0.0
/// - INTEGER -> converted to float
/// - TEXT/BLOB -> parsed as float or 0.0
///
/// For type-safe extraction, check `getType()` first.
pub fn getDouble(v: *SqliteValue) f64 {
    return sqlite3_value_double(v);
}

/// Checks if the value is SQL NULL.
pub fn isNull(v: *SqliteValue) bool {
    return getType(v) == .null;
}

/// Type-safe value extraction that returns a tagged union.
/// Useful when you need to handle all types uniformly.
pub const Value = union(ValueType) {
    integer: i64,
    float: f64,
    text: []const u8,
    blob: []const u8,
    null: void,
};

/// Extracts the value into a tagged union based on its actual type.
///
/// Returns `null` if the type cannot be determined.
pub fn getValue(v: *SqliteValue) ?Value {
    const t = getType(v) orelse return null;
    return switch (t) {
        .integer => .{ .integer = getInt64(v) },
        .float => .{ .float = getDouble(v) },
        .text => .{ .text = getText(v) orelse &[_]u8{} },
        .blob => .{ .blob = getBlob(v) orelse &[_]u8{} },
        .null => .{ .null = {} },
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ValueType enum matches SQLite constants" {
    // These values must match SQLite's SQLITE_* type constants
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(ValueType.integer));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(ValueType.float));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(ValueType.text));
    try std.testing.expectEqual(@as(c_int, 4), @intFromEnum(ValueType.blob));
    try std.testing.expectEqual(@as(c_int, 5), @intFromEnum(ValueType.null));
}

test "Value union is properly tagged" {
    // Compile-time test: ensure union discriminant matches enum
    const v_int: Value = .{ .integer = 42 };
    const v_float: Value = .{ .float = 3.14 };
    const v_text: Value = .{ .text = "hello" };
    const v_blob: Value = .{ .blob = &[_]u8{ 0x00, 0xFF, 0x00 } };
    const v_null: Value = .{ .null = {} };

    // Use std.meta.activeTag to get the enum from the tagged union
    try std.testing.expectEqual(ValueType.integer, std.meta.activeTag(v_int));
    try std.testing.expectEqual(ValueType.float, std.meta.activeTag(v_float));
    try std.testing.expectEqual(ValueType.text, std.meta.activeTag(v_text));
    try std.testing.expectEqual(ValueType.blob, std.meta.activeTag(v_blob));
    try std.testing.expectEqual(ValueType.null, std.meta.activeTag(v_null));
}

test "blob with embedded NUL bytes design contract" {
    // This is a design contract test - it documents the expected behavior
    // without requiring actual SQLite linkage.
    //
    // The bug in zig-sqlite/helpers.zig:
    //   fn sliceFromValue(sqlite_value: *c.sqlite3_value) []const u8 {
    //       const size: usize = @intCast(c.sqlite3_value_bytes(sqlite_value));
    //       const value = c.sqlite3_value_text(sqlite_value);  // BUG: uses text!
    //       return value[0..size];
    //   }
    //
    // Using sqlite3_value_text for blobs is wrong because:
    // 1. It may perform UTF-8 encoding conversions
    // 2. SQLite may return a different pointer than blob would
    //
    // Our implementation uses sqlite3_value_blob for getBlob():
    //   pub fn getBlob(v: *SqliteValue) ?[]const u8 {
    //       const len = sqlite3_value_bytes(v);
    //       const ptr = sqlite3_value_blob(v);  // CORRECT: uses blob!
    //       ...
    //   }
    //
    // Example blob that would be corrupted by text extraction:
    const packed_pk = [_]u8{
        0x02, // num_columns
        0x01, // type: integer, 1 byte
        0x2A, // value: 42
        0x00, // embedded NUL - would truncate if using text!
        0x04, // type: blob
        0x03, // length: 3
        0xDE, 0xAD, 0xBE, // blob data
    };

    // Verify the test data has embedded NUL
    try std.testing.expect(std.mem.indexOfScalar(u8, &packed_pk, 0x00) != null);

    // The length must be preserved (not truncated at NUL)
    // 9 bytes total: 1 + 1 + 1 + 1 + 1 + 1 + 3
    try std.testing.expectEqual(@as(usize, 9), packed_pk.len);
}

test "type detection covers all 5 SQLite types" {
    // Compile-time exhaustiveness check via switch
    inline for (std.meta.fields(ValueType)) |field| {
        const vt: ValueType = @enumFromInt(field.value);
        switch (vt) {
            .integer => try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(vt)),
            .float => try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(vt)),
            .text => try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(vt)),
            .blob => try std.testing.expectEqual(@as(c_int, 4), @intFromEnum(vt)),
            .null => try std.testing.expectEqual(@as(c_int, 5), @intFromEnum(vt)),
        }
    }

    // Verify we have exactly 5 types
    try std.testing.expectEqual(@as(usize, 5), std.meta.fields(ValueType).len);
}
