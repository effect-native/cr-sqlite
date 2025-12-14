//! Wire format codec for packed column blobs
//!
//! Bit-for-bit compatible with `core/rs/core/src/pack_columns.rs`.
//! Specification: `zig/src/codec.md`.

const std = @import("std");

pub const ColumnType = enum(u3) {
    integer = 1,
    float = 2,
    text = 3,
    blob = 4,
    null = 5,
};

pub const Value = union(enum) {
    Null,
    Integer: i64,
    Float: f64,
    Text: []const u8,
    Blob: []const u8,
};

pub const CodecError = error{
    TooManyColumns,
    LengthOverflow,
    InvalidTypeTag,
    InvalidIntLen,
    InvalidLength,
    TruncatedInput,
} || std.mem.Allocator.Error;

fn numBytesNeededI32(val: i32) u8 {
    // Keep identical behavior to `core/rs/core/src/pack_columns.rs:num_bytes_needed_i32`.
    if ((val & @as(i32, @bitCast(@as(u32, 0xFF000000)))) != 0) {
        return 4;
    } else if ((val & 0x00FF0000) != 0) {
        return 3;
    } else if ((val & 0x0000FF00) != 0) {
        return 2;
    } else if (val * 0x000000FF != 0) {
        // Bug-for-bug compatibility: multiplication instead of bitwise-and.
        return 1;
    } else {
        return 0;
    }
}

fn numBytesNeededI64(val: i64) u8 {
    // Keep identical behavior to `core/rs/core/src/pack_columns.rs:num_bytes_needed_i64`.
    if ((val & @as(i64, @bitCast(@as(u64, 0xFF00000000000000)))) != 0) {
        return 8;
    } else if ((val & 0x00FF000000000000) != 0) {
        return 7;
    } else if ((val & 0x0000FF0000000000) != 0) {
        return 6;
    } else if ((val & 0x000000FF00000000) != 0) {
        return 5;
    } else {
        // Rust uses `val as i32` here (wrapping/truncating cast).
        const lower: i32 = @bitCast(@as(u32, @truncate(@as(u64, @bitCast(val)))));
        return numBytesNeededI32(lower);
    }
}

fn lenToI32(len: usize) CodecError!i32 {
    return std.math.cast(i32, len) orelse error.LengthOverflow;
}

fn writeIntBig(dest: []u8, index: *usize, val: i64, num_bytes: u8) void {
    if (num_bytes == 0) return;

    // Equivalent to `bytes::BufMut::put_int(val, nbytes)`:
    // write last `nbytes` of `val.to_be_bytes()`.
    const unsigned: u64 = @bitCast(val);
    var be: [8]u8 = undefined;
    std.mem.writeInt(u64, &be, unsigned, .big);

    const start: usize = 8 - @as(usize, num_bytes);
    @memcpy(dest[index.* .. index.* + num_bytes], be[start..]);
    index.* += num_bytes;
}

fn readIntBig(bytes: []const u8) i64 {
    if (bytes.len == 0) return 0;

    // Match `bytes::Buf::get_int(nbytes)` for big-endian.
    // It right-aligns the bytes in an 8-byte buffer and then uses `i64::from_be_bytes`.
    // This is a sign-preserving decode when the buffer's MSB is set.
    var buf: [8]u8 = .{0} ** 8;
    @memcpy(buf[8 - bytes.len ..], bytes);

    const unsigned = std.mem.readInt(u64, &buf, .big);
    return @bitCast(unsigned);
}

pub fn pack(allocator: std.mem.Allocator, values: []const Value) CodecError![]u8 {
    if (values.len > std.math.maxInt(u8)) return error.TooManyColumns;

    var total: usize = 1; // column count
    for (values) |v| {
        switch (v) {
            .Null => total += 1,
            .Float => total += 1 + 8,
            .Integer => |i| total += 1 + numBytesNeededI64(i),
            .Text => |t| {
                const len_i32 = try lenToI32(t.len);
                total += 1 + numBytesNeededI32(len_i32) + t.len;
            },
            .Blob => |b| {
                const len_i32 = try lenToI32(b.len);
                total += 1 + numBytesNeededI32(len_i32) + b.len;
            },
        }
    }

    const out = try allocator.alloc(u8, total);
    errdefer allocator.free(out);

    var idx: usize = 0;
    out[idx] = @intCast(values.len);
    idx += 1;

    for (values) |v| {
        switch (v) {
            .Null => {
                out[idx] = @intFromEnum(ColumnType.null);
                idx += 1;
            },
            .Float => |f| {
                out[idx] = @intFromEnum(ColumnType.float);
                idx += 1;

                const bits: u64 = @bitCast(f);
                const buf_ptr: *[8]u8 = @ptrCast(out[idx .. idx + 8].ptr);
                std.mem.writeInt(u64, buf_ptr, bits, .big);
                idx += 8;
            },
            .Integer => |i| {
                const n = numBytesNeededI64(i);
                out[idx] = (n << 3) | @intFromEnum(ColumnType.integer);
                idx += 1;
                writeIntBig(out, &idx, i, n);
            },
            .Text => |t| {
                const len_i32 = try lenToI32(t.len);
                const n = numBytesNeededI32(len_i32);
                out[idx] = (n << 3) | @intFromEnum(ColumnType.text);
                idx += 1;

                writeIntBig(out, &idx, @intCast(len_i32), n);
                @memcpy(out[idx .. idx + t.len], t);
                idx += t.len;
            },
            .Blob => |b| {
                const len_i32 = try lenToI32(b.len);
                const n = numBytesNeededI32(len_i32);
                out[idx] = (n << 3) | @intFromEnum(ColumnType.blob);
                idx += 1;

                writeIntBig(out, &idx, @intCast(len_i32), n);
                @memcpy(out[idx .. idx + b.len], b);
                idx += b.len;
            },
        }
    }

    std.debug.assert(idx == total);
    return out;
}

pub fn unpack(allocator: std.mem.Allocator, data: []const u8) CodecError![]Value {
    if (data.len < 1) return error.TruncatedInput;

    var idx: usize = 0;
    const num_columns: usize = data[idx];
    idx += 1;

    const values = try allocator.alloc(Value, num_columns);
    errdefer allocator.free(values);

    var produced: usize = 0;
    errdefer {
        var j: usize = 0;
        while (j < produced) : (j += 1) {
            switch (values[j]) {
                .Text => |s| allocator.free(s),
                .Blob => |b| allocator.free(b),
                else => {},
            }
        }
        allocator.free(values);
    }

    while (produced < num_columns) : (produced += 1) {
        if (idx >= data.len) return error.TruncatedInput;
        const type_byte = data[idx];
        idx += 1;

        const tag: u8 = type_byte & 0x07;
        const intlen: usize = type_byte >> 3;

        switch (tag) {
            @intFromEnum(ColumnType.integer) => {
                if (intlen > 8) return error.InvalidIntLen;
                if (data.len - idx < intlen) return error.TruncatedInput;

                const nbytes = data[idx .. idx + intlen];
                idx += intlen;
                values[produced] = .{ .Integer = readIntBig(nbytes) };
            },
            @intFromEnum(ColumnType.float) => {
                if (data.len - idx < 8) return error.TruncatedInput;

                const buf_ptr: *const [8]u8 = @ptrCast(data[idx .. idx + 8].ptr);
                const bits = std.mem.readInt(u64, buf_ptr, .big);
                idx += 8;
                values[produced] = .{ .Float = @bitCast(bits) };
            },
            @intFromEnum(ColumnType.text) => {
                if (intlen > 4) return error.InvalidIntLen;
                if (data.len - idx < intlen) return error.TruncatedInput;

                const len_i64 = readIntBig(data[idx .. idx + intlen]);
                idx += intlen;
                if (len_i64 < 0) return error.InvalidLength;

                const len: usize = std.math.cast(usize, len_i64) orelse return error.InvalidLength;
                if (data.len - idx < len) return error.TruncatedInput;

                const payload = data[idx .. idx + len];
                idx += len;

                // No UTF-8 validation.
                values[produced] = .{ .Text = try allocator.dupe(u8, payload) };
            },
            @intFromEnum(ColumnType.blob) => {
                if (intlen > 4) return error.InvalidIntLen;
                if (data.len - idx < intlen) return error.TruncatedInput;

                const len_i64 = readIntBig(data[idx .. idx + intlen]);
                idx += intlen;
                if (len_i64 < 0) return error.InvalidLength;

                const len: usize = std.math.cast(usize, len_i64) orelse return error.InvalidLength;
                if (data.len - idx < len) return error.TruncatedInput;

                const payload = data[idx .. idx + len];
                idx += len;

                values[produced] = .{ .Blob = try allocator.dupe(u8, payload) };
            },
            @intFromEnum(ColumnType.null) => {
                values[produced] = .Null;
            },
            else => return error.InvalidTypeTag,
        }
    }

    return values;
}

fn freeUnpacked(allocator: std.mem.Allocator, values: []Value) void {
    for (values) |v| {
        switch (v) {
            .Text => |s| allocator.free(s),
            .Blob => |b| allocator.free(b),
            else => {},
        }
    }
    allocator.free(values);
}

test "pack matches golden vectors" {
    const alloc = std.testing.allocator;
    const golden = @import("golden_vectors");

    for (golden.vectors) |v| {
        const cols = try alloc.alloc(Value, v.expected_columns.len);
        defer alloc.free(cols);

        for (v.expected_columns, 0..) |col, i| {
            cols[i] = switch (col.col_type) {
                .null => .Null,
                .integer => .{ .Integer = col.int_value.? },
                .float => .{ .Float = col.float_value.? },
                .text => .{ .Text = col.text_value.? },
                .blob => .{ .Blob = col.blob_value.? },
            };
        }

        const got = try pack(alloc, cols);
        defer alloc.free(got);

        try std.testing.expectEqualSlices(u8, v.packed_bytes, got);
    }
}

test "unpack matches golden vectors" {
    const alloc = std.testing.allocator;
    const golden = @import("golden_vectors");

    for (golden.vectors) |v| {
        const got = try unpack(alloc, v.packed_bytes);
        defer freeUnpacked(alloc, got);

        try std.testing.expectEqual(v.expected_columns.len, got.len);

        for (v.expected_columns, 0..) |col, i| {
            switch (col.col_type) {
                .null => try std.testing.expect(got[i] == .Null),
                .integer => {
                    try std.testing.expect(got[i] == .Integer);
                    try std.testing.expectEqual(col.int_value.?, got[i].Integer);
                },
                .float => {
                    try std.testing.expect(got[i] == .Float);
                    const got_bits: u64 = @bitCast(got[i].Float);
                    const expected_bits: u64 = @bitCast(col.float_value.?);
                    try std.testing.expectEqual(expected_bits, got_bits);
                },
                .text => {
                    try std.testing.expect(got[i] == .Text);
                    try std.testing.expectEqualSlices(u8, col.text_value.?, got[i].Text);
                },
                .blob => {
                    try std.testing.expect(got[i] == .Blob);
                    try std.testing.expectEqualSlices(u8, col.blob_value.?, got[i].Blob);
                },
            }
        }
    }
}
