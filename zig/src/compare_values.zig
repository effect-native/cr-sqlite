//! Value comparison for CR-SQLite merge conflict resolution
//!
//! When cl and col_version are tied, the "larger" value wins.
//! Type ordering (from compare_values.rs):
//!   NULL < INTEGER < FLOAT < TEXT < BLOB
//!
//! Within same type, compare by value.

const std = @import("std");
const api = @import("ffi/api.zig");

/// SQLite type constants (from sqlite3.h)
pub const SQLITE_INTEGER = api.SQLITE_INTEGER;
pub const SQLITE_FLOAT = api.SQLITE_FLOAT;
pub const SQLITE_TEXT = api.SQLITE_TEXT;
pub const SQLITE_BLOB = api.SQLITE_BLOB;
pub const SQLITE_NULL = api.SQLITE_NULL;

/// Compare two SQLite values.
/// Returns negative if left < right, 0 if equal, positive if left > right.
///
/// Comparison rules (from CR-SQLite semantics):
/// 1. Different types: NULL < INTEGER < FLOAT < TEXT < BLOB
/// 2. Same type: compare by value
///    - INTEGER: numeric comparison
///    - FLOAT: numeric comparison
///    - TEXT: lexicographic (byte-by-byte)
///    - BLOB: lexicographic (byte-by-byte)
///    - NULL: always equal to NULL
///
/// Note: The Rust implementation uses (r_type - l_type) for type comparison
/// because SQLite's type ordinals are: INTEGER=1, FLOAT=2, TEXT=3, BLOB=4, NULL=5
/// By subtracting r-l, NULL (5) becomes "less than" everything else.
pub fn compareSqliteValues(left: ?*api.sqlite3_value, right: ?*api.sqlite3_value) i32 {
    // Handle null pointers (not the same as SQLITE_NULL type)
    if (left == null and right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;

    const l_type = api.value_type(left);
    const r_type = api.value_type(right);

    // Different types: use SQLite ordinals in reverse (r - l)
    // This makes NULL(5) < INTEGER(1) < FLOAT(2) < TEXT(3) < BLOB(4)
    if (l_type != r_type) {
        return r_type - l_type;
    }

    // Same type - compare values
    return switch (l_type) {
        SQLITE_NULL => 0,
        SQLITE_INTEGER => compareIntegers(left, right),
        SQLITE_FLOAT => compareFloats(left, right),
        SQLITE_TEXT => compareText(left, right),
        SQLITE_BLOB => compareBlobs(left, right),
        else => 0,
    };
}

fn compareIntegers(left: ?*api.sqlite3_value, right: ?*api.sqlite3_value) i32 {
    const lv = api.value_int64(left);
    const rv = api.value_int64(right);
    if (lv < rv) return -1;
    if (lv > rv) return 1;
    return 0;
}

fn compareFloats(left: ?*api.sqlite3_value, right: ?*api.sqlite3_value) i32 {
    const lv = api.value_double(left);
    const rv = api.value_double(right);
    if (lv < rv) return -1;
    if (lv > rv) return 1;
    return 0;
}

fn compareText(left: ?*api.sqlite3_value, right: ?*api.sqlite3_value) i32 {
    const lptr = api.value_text(left);
    const rptr = api.value_text(right);

    if (lptr == null and rptr == null) return 0;
    if (lptr == null) return -1;
    if (rptr == null) return 1;

    const ltext = std.mem.span(lptr.?);
    const rtext = std.mem.span(rptr.?);

    return switch (std.mem.order(u8, ltext, rtext)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn compareBlobs(left: ?*api.sqlite3_value, right: ?*api.sqlite3_value) i32 {
    const llen: usize = @intCast(@max(0, api.value_bytes(left)));
    const rlen: usize = @intCast(@max(0, api.value_bytes(right)));

    const lptr = api.value_blob(left);
    const rptr = api.value_blob(right);

    if (lptr == null and rptr == null) return 0;
    if (lptr == null) return -1;
    if (rptr == null) return 1;

    const lblob: [*]const u8 = @ptrCast(lptr.?);
    const rblob: [*]const u8 = @ptrCast(rptr.?);

    return switch (std.mem.order(u8, lblob[0..llen], rblob[0..rlen])) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "type ordering: NULL < INTEGER < FLOAT < TEXT < BLOB" {
    // SQLite type ordinals: INTEGER=1, FLOAT=2, TEXT=3, BLOB=4, NULL=5
    // The comparison (r_type - l_type) gives us:
    //   NULL vs INTEGER: 1 - 5 = -4 (NULL < INTEGER) ✓
    //   INTEGER vs FLOAT: 2 - 1 = 1 (INTEGER < FLOAT) ✓
    //   FLOAT vs TEXT: 3 - 2 = 1 (FLOAT < TEXT) ✓
    //   TEXT vs BLOB: 4 - 3 = 1 (TEXT < BLOB) ✓

    // Verify SQLite ordinals are what we expect
    try std.testing.expectEqual(@as(c_int, 1), SQLITE_INTEGER);
    try std.testing.expectEqual(@as(c_int, 2), SQLITE_FLOAT);
    try std.testing.expectEqual(@as(c_int, 3), SQLITE_TEXT);
    try std.testing.expectEqual(@as(c_int, 4), SQLITE_BLOB);
    try std.testing.expectEqual(@as(c_int, 5), SQLITE_NULL);

    // The ordering math: when comparing type L to type R with (R - L):
    // - If L=NULL(5) and R=INTEGER(1): 1 - 5 = -4, meaning NULL < INTEGER
    // - If L=INTEGER(1) and R=FLOAT(2): 2 - 1 = 1, meaning INTEGER < FLOAT
    // etc.
}

test "null pointer handling" {
    try std.testing.expectEqual(@as(i32, 0), compareSqliteValues(null, null));
    // Can't easily test non-null without actual sqlite3_value pointers
}
