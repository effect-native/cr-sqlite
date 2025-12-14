//! Wire format codec for packed column blobs
//! See research/zig-cr/09-storage-serialization.md for specification

const std = @import("std");

pub const ColumnType = enum(u3) {
    integer = 1,
    float = 2,
    text = 3,
    blob = 4,
    null = 5,
};

// TODO: implement pack/unpack
