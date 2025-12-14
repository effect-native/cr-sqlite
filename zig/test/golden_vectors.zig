//! Golden test vectors extracted from C/Rust tests
//! These define the byte-level contract for crsql_pack_columns
//!
//! Wire format (from core/rs/core/src/pack_columns.rs:33-44):
//!   [num_columns:u8, ...columns]
//!
//! Each column is encoded as:
//!   [type_byte:u8, length?:varint, data:bytes]
//!
//! type_byte layout (bits):
//!   - bits 0-2 (low 3 bits): column type (1=int, 2=float, 3=text, 4=blob, 5=null)
//!   - bits 3-7 (high 5 bits): intlen - number of bytes used for the following integer
//!     (for integers: the value itself; for text/blob: the length prefix)
//!
//! Special cases:
//!   - NULL: type_byte = 5, no following data
//!   - Float: type_byte = 2, followed by 8 bytes (f64 big-endian)
//!   - Integer: type_byte = (intlen << 3) | 1, followed by intlen bytes (big-endian signed)
//!   - Text: type_byte = (intlen << 3) | 3, followed by intlen bytes for length, then UTF-8 bytes
//!   - Blob: type_byte = (intlen << 3) | 4, followed by intlen bytes for length, then raw bytes

const std = @import("std");

/// SQLite column types as used in the pack_columns wire format
/// Values match sqlite_nostd::ColumnType from core/rs/sqlite-rs-embedded/sqlite_nostd/src/nostd.rs:223-228
pub const ColumnType = enum(u3) {
    integer = 1,
    float = 2,
    text = 3,
    blob = 4,
    null = 5,
};

/// Expected value after decoding a column
pub const ExpectedColumn = struct {
    col_type: ColumnType,
    int_value: ?i64 = null,
    float_value: ?f64 = null,
    text_value: ?[]const u8 = null,
    blob_value: ?[]const u8 = null,
};

/// A test vector with packed bytes and expected decoded values
pub const TestVector = struct {
    name: []const u8,
    source: []const u8,
    packed_bytes: []const u8,
    expected_columns: []const ExpectedColumn,
};

/// Golden test vectors extracted from the C and Rust test suites
pub const vectors = [_]TestVector{
    // =========================================================================
    // Vector 1: Two small positive integers (from C test)
    // Source: core/src/changes-vtab.test.c:34-42
    // Input: INSERT INTO foo VALUES (4,5,6) with pk=(a,b) -> packed pk is (4,5)
    // =========================================================================
    .{
        .name = "two_small_integers",
        .source = "changes-vtab.test.c:42",
        .packed_bytes = &[_]u8{
            0x02, // num_columns = 2
            0x09, // type_byte: (1 << 3) | 1 = 9 -> intlen=1, type=integer
            0x04, // value = 4
            0x09, // type_byte: (1 << 3) | 1 = 9 -> intlen=1, type=integer
            0x05, // value = 5
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .integer, .int_value = 4 },
            .{ .col_type = .integer, .int_value = 5 },
        },
    },

    // =========================================================================
    // Vector 2: Integer, Text, Blob (from Rust test)
    // Source: core/rs/integration_check/src/t/pack_columns.rs:25
    // Input: (12, "str", blob[1,2,3])
    // =========================================================================
    .{
        .name = "integer_text_blob",
        .source = "pack_columns.rs:25",
        .packed_bytes = &[_]u8{
            0x03, // num_columns = 3
            0x09, // type_byte: (1 << 3) | 1 = 9 -> intlen=1, type=integer
            0x0C, // value = 12
            0x0B, // type_byte: (1 << 3) | 3 = 11 -> intlen=1, type=text
            0x03, // length = 3
            0x73, 0x74, 0x72, // "str" in ASCII
            0x0C, // type_byte: (1 << 3) | 4 = 12 -> intlen=1, type=blob
            0x03, // length = 3
            0x01, 0x02, 0x03, // blob bytes
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .integer, .int_value = 12 },
            .{ .col_type = .text, .text_value = "str" },
            .{ .col_type = .blob, .blob_value = &[_]u8{ 1, 2, 3 } },
        },
    },

    // =========================================================================
    // Vector 3: NULL value
    // Source: Derived from core/rs/core/src/pack_columns.rs:58-60
    // NULL is encoded as just the type byte with no following data
    // =========================================================================
    .{
        .name = "single_null",
        .source = "pack_columns.rs:58-60",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x05, // type_byte: 5 = null (no intlen component)
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .null },
        },
    },

    // =========================================================================
    // Vector 4: Float value
    // Source: Derived from core/rs/core/src/pack_columns.rs:61-64
    // Float is encoded as type byte 2 followed by 8-byte big-endian f64
    // Using 1.5 which has exact binary representation: 0x3FF8000000000000
    // =========================================================================
    .{
        .name = "single_float",
        .source = "pack_columns.rs:61-64",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x02, // type_byte: 2 = float (no intlen component)
            0x3F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 1.5 as big-endian f64
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .float, .float_value = 1.5 },
        },
    },

    // =========================================================================
    // Vector 5: Zero integer (edge case for intlen calculation)
    // Source: core/rs/integration_check/src/t/pack_columns.rs:85,98-101
    // Zero requires special handling - num_bytes_needed returns 0 for val=0
    // per pack_columns.rs:97-98
    // =========================================================================
    .{
        .name = "zero_integer",
        .source = "pack_columns.rs:85",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x01, // type_byte: (0 << 3) | 1 = 1 -> intlen=0, type=integer
            // no value bytes when intlen=0
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .integer, .int_value = 0 },
        },
    },

    // =========================================================================
    // Vector 6: Large positive integer (multi-byte)
    // Source: core/rs/integration_check/src/t/pack_columns.rs:86,103-106
    // 10000000 = 0x989680, needs 3 bytes
    // =========================================================================
    .{
        .name = "large_positive_integer",
        .source = "pack_columns.rs:86",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x19, // type_byte: (3 << 3) | 1 = 25 -> intlen=3, type=integer
            0x98, 0x96, 0x80, // 10000000 as big-endian (3 bytes)
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .integer, .int_value = 10000000 },
        },
    },

    // =========================================================================
    // Vector 7: Negative integer
    // Source: core/rs/integration_check/src/t/pack_columns.rs:87,108-111
    // -2500000 = 0xFFD9F3C0 in i32, needs 4 bytes for signed representation
    // In two's complement: -2500000 as i64 = 0xFFFFFFFFFFD9F3C0
    // But bytes needed depends on sign-extension - checking high bytes
    // -2500000 = 0xFFD9F3C0, high byte is 0xFF -> 4 bytes needed
    // =========================================================================
    .{
        .name = "negative_integer",
        .source = "pack_columns.rs:87",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x21, // type_byte: (4 << 3) | 1 = 33 -> intlen=4, type=integer
            0xFF, 0xD9, 0xF3, 0xC0, // -2500000 as big-endian signed (4 bytes)
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .integer, .int_value = -2500000 },
        },
    },

    // =========================================================================
    // Vector 8: Empty text string
    // Edge case: length=0 text
    // =========================================================================
    .{
        .name = "empty_text",
        .source = "pack_columns.rs:72-78 (derived)",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x03, // type_byte: (0 << 3) | 3 = 3 -> intlen=0, type=text (length encoded as 0 bytes means length=0)
            // no length bytes when intlen=0 implies length=0
            // no content bytes
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .text, .text_value = "" },
        },
    },

    // =========================================================================
    // Vector 9: Mixed types including NULL
    // Comprehensive test of all types in one packet
    // =========================================================================
    .{
        .name = "all_types_mixed",
        .source = "pack_columns.rs (synthesized)",
        .packed_bytes = &[_]u8{
            0x05, // num_columns = 5
            0x05, // NULL
            0x09, 0x2A, // integer 42 (intlen=1)
            0x02, 0x40, 0x09, 0x21, 0xFB, 0x54, 0x44, 0x2D, 0x18, // float 3.141592653589793 (pi)
            0x0B, 0x02, 0x68, 0x69, // text "hi" (intlen=1, len=2)
            0x0C, 0x01, 0xFF, // blob [0xFF] (intlen=1, len=1)
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .null },
            .{ .col_type = .integer, .int_value = 42 },
            .{ .col_type = .float, .float_value = 3.141592653589793 },
            .{ .col_type = .text, .text_value = "hi" },
            .{ .col_type = .blob, .blob_value = &[_]u8{0xFF} },
        },
    },

    // =========================================================================
    // Vector 10: Small negative integer (-1)
    // Edge case: -1 = 0xFF in single byte, but sign extension matters
    // -1 as i64 = 0xFFFFFFFFFFFFFFFF, all bytes are 0xFF
    // num_bytes_needed_i64 checks from high byte down; 0xFF in high byte -> 8 bytes
    // =========================================================================
    .{
        .name = "negative_one",
        .source = "pack_columns.rs:102-114 (derived)",
        .packed_bytes = &[_]u8{
            0x01, // num_columns = 1
            0x41, // type_byte: (8 << 3) | 1 = 65 -> intlen=8, type=integer
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // -1 as big-endian signed (8 bytes)
        },
        .expected_columns = &[_]ExpectedColumn{
            .{ .col_type = .integer, .int_value = -1 },
        },
    },
};

// Compile-time validation that the vectors are well-formed
comptime {
    for (vectors) |v| {
        if (v.packed_bytes.len == 0) {
            @compileError("Vector has empty packed_bytes");
        }
        if (v.expected_columns.len == 0) {
            @compileError("Vector has no expected columns");
        }
        // First byte should be column count
        if (v.packed_bytes[0] != v.expected_columns.len) {
            @compileError("Column count mismatch in vector");
        }
    }
}

test "golden vectors are valid" {
    // This test just ensures the vectors compile and have consistent metadata
    for (vectors) |v| {
        try std.testing.expect(v.packed_bytes.len > 0);
        try std.testing.expect(v.expected_columns.len > 0);
        try std.testing.expectEqual(v.packed_bytes[0], @as(u8, @intCast(v.expected_columns.len)));
    }
}
