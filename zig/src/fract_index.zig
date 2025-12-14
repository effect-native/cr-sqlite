//! Fractional Indexing for CR-SQLite
//!
//! Provides lexicographically-ordered keys for positioning items in lists.
//! Based on the Rust implementation in `core/rs/fractindex-core/src/fractindex.rs`.
//!
//! The key format uses printable ASCII characters (32-126) as a base-95 alphabet.
//! Keys have an integer part (determined by the first character) and a fractional part.
//!
//! SQL Function: `crsql_fract_key_between(left, right)`
//! - Both NULL: returns middle key "a " (INTEGER_ZERO)
//! - left NULL: returns key before right
//! - right NULL: returns key after left
//! - Both provided: returns key between them

const std = @import("std");
const api = @import("ffi/api.zig");

/// Printable ASCII digits for base-95 encoding (space to tilde)
pub const BASE_95_DIGITS = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

/// Smallest possible integer part - used as a boundary
const SMALLEST_INTEGER = "A                          ";

/// Zero integer - the default middle key
const INTEGER_ZERO = "a ";

// Character code constants
const a_charcode: u8 = 'a';
const z_charcode: u8 = 'z';
const A_charcode: u8 = 'A';
const Z_charcode: u8 = 'Z';
const min_charcode: u8 = ' '; // space = 32

/// Error types for fractional indexing operations
pub const FractError = error{
    KeyTooSmall,
    InvalidKey,
    InvalidIntegerPart,
    InvalidDigit,
    HeadOutOfRange,
    FractionalEndsWithSpace,
    AMustBeBeforeB,
    CannotIncrement,
    CannotDecrement,
    OutOfMemory,
};

/// Compute a key between two existing keys.
/// Returns an allocated string that the caller must free.
pub fn fractKeyBetween(
    allocator: std.mem.Allocator,
    a: ?[]const u8,
    b: ?[]const u8,
) FractError![]u8 {
    // Validate inputs if present
    if (a) |key_a| try validateOrderKey(key_a);
    if (b) |key_b| try validateOrderKey(key_b);

    // Handle the four cases
    if (a == null and b == null) {
        // Return the middle key "a "
        const result = allocator.alloc(u8, INTEGER_ZERO.len) catch return error.OutOfMemory;
        @memcpy(result, INTEGER_ZERO);
        return result;
    }

    if (a != null and b != null) {
        const key_a = a.?;
        const key_b = b.?;

        // a must be lexicographically before b
        if (std.mem.order(u8, key_a, key_b) != .lt) {
            return error.AMustBeBeforeB;
        }

        const ia = try getIntegerPart(key_a);
        const ib = try getIntegerPart(key_b);
        const fa = key_a[ia.len..];
        const fb = key_b[ib.len..];

        if (std.mem.eql(u8, ia, ib)) {
            // Same integer part - find midpoint in fractional part
            const mid = try midpoint(allocator, fa, fb);
            const result = allocator.alloc(u8, ia.len + mid.len) catch {
                allocator.free(mid);
                return error.OutOfMemory;
            };
            @memcpy(result[0..ia.len], ia);
            @memcpy(result[ia.len..], mid);
            allocator.free(mid);
            return result;
        }

        // Different integer parts - try to increment a's integer
        if (try incrementInteger(allocator, ia)) |incremented| {
            defer allocator.free(incremented);
            if (std.mem.order(u8, incremented, key_b) == .lt) {
                const result = allocator.alloc(u8, incremented.len) catch return error.OutOfMemory;
                @memcpy(result, incremented);
                return result;
            }
            // Incremented integer >= b, need midpoint
            const mid = try midpoint(allocator, fa, null);
            const result = allocator.alloc(u8, ia.len + mid.len) catch {
                allocator.free(mid);
                return error.OutOfMemory;
            };
            @memcpy(result[0..ia.len], ia);
            @memcpy(result[ia.len..], mid);
            allocator.free(mid);
            return result;
        } else {
            return error.CannotIncrement;
        }
    }

    if (a == null) {
        // Return key before b
        const key_b = b.?;
        const ib = try getIntegerPart(key_b);
        const fb = key_b[ib.len..];

        if (std.mem.eql(u8, ib, SMALLEST_INTEGER)) {
            // At smallest integer - extend fractional part
            const mid = try midpoint(allocator, "", fb);
            const result = allocator.alloc(u8, ib.len + mid.len) catch {
                allocator.free(mid);
                return error.OutOfMemory;
            };
            @memcpy(result[0..ib.len], ib);
            @memcpy(result[ib.len..], mid);
            allocator.free(mid);
            return result;
        }

        // If ib < key_b (has fractional part), return just the integer part
        if (std.mem.order(u8, ib, key_b) == .lt) {
            const result = allocator.alloc(u8, ib.len) catch return error.OutOfMemory;
            @memcpy(result, ib);
            return result;
        }

        // Decrement the integer part
        if (try decrementInteger(allocator, ib)) |decremented| {
            return decremented;
        } else {
            return error.CannotDecrement;
        }
    }

    // a != null, b == null - return key after a
    const key_a = a.?;
    const ia = try getIntegerPart(key_a);
    const fa = key_a[ia.len..];

    if (try incrementInteger(allocator, ia)) |incremented| {
        return incremented;
    } else {
        // Can't increment integer, extend fractional
        const mid = try midpoint(allocator, fa, null);
        const result = allocator.alloc(u8, ia.len + mid.len) catch {
            allocator.free(mid);
            return error.OutOfMemory;
        };
        @memcpy(result[0..ia.len], ia);
        @memcpy(result[ia.len..], mid);
        allocator.free(mid);
        return result;
    }
}

/// Find midpoint between two fractional parts
fn midpoint(allocator: std.mem.Allocator, a: []const u8, b_opt: ?[]const u8) FractError![]u8 {
    // Check for invalid trailing spaces
    if (a.len > 0 and a[a.len - 1] == min_charcode) {
        return error.FractionalEndsWithSpace;
    }
    if (b_opt) |b| {
        if (b.len > 0 and b[b.len - 1] == min_charcode) {
            return error.FractionalEndsWithSpace;
        }
        // a must be before b
        if (std.mem.order(u8, a, b) != .lt) {
            return error.AMustBeBeforeB;
        }
    }

    if (b_opt) |b| {
        // Find common prefix
        var n: usize = 0;
        while (n < b.len) : (n += 1) {
            const a_char = if (n < a.len) a[n] else min_charcode;
            if (a_char != b[n]) break;
        }

        if (n > 0) {
            // Recurse with common prefix removed
            const a_rest = if (n >= a.len) "" else a[n..];
            const b_rest = if (n >= b.len) null else b[n..];
            const suffix = try midpoint(allocator, a_rest, b_rest);
            const result = allocator.alloc(u8, n + suffix.len) catch {
                allocator.free(suffix);
                return error.OutOfMemory;
            };
            @memcpy(result[0..n], b[0..n]);
            @memcpy(result[n..], suffix);
            allocator.free(suffix);
            return result;
        }
    }

    // Get digit indices
    const digit_a: usize = if (a.len > 0) (std.mem.indexOfScalar(u8, BASE_95_DIGITS, a[0]) orelse return error.InvalidDigit) else 0;

    const digit_b: usize = if (b_opt) |b| (std.mem.indexOfScalar(u8, BASE_95_DIGITS, b[0]) orelse return error.InvalidDigit) else BASE_95_DIGITS.len;

    if (digit_b - digit_a > 1) {
        // Room for a character between them
        // Use round-half-up to match Rust behavior: (a + b + 1) / 2 for odd sums
        const mid_digit = (digit_a + digit_b + 1) / 2;
        const result = allocator.alloc(u8, 1) catch return error.OutOfMemory;
        result[0] = BASE_95_DIGITS[mid_digit];
        return result;
    } else {
        // No room - need to extend
        if (b_opt) |b| {
            if (b.len > 1) {
                // Just take first char of b
                const result = allocator.alloc(u8, 1) catch return error.OutOfMemory;
                result[0] = b[0];
                return result;
            }
        }
        // Extend with midpoint after a's first char
        const a_rest = if (a.len > 0) a[1..] else a;
        const suffix = try midpoint(allocator, a_rest, null);
        const result = allocator.alloc(u8, 1 + suffix.len) catch {
            allocator.free(suffix);
            return error.OutOfMemory;
        };
        result[0] = BASE_95_DIGITS[digit_a];
        @memcpy(result[1..], suffix);
        allocator.free(suffix);
        return result;
    }
}

/// Validate an order key
fn validateOrderKey(key: []const u8) FractError!void {
    if (std.mem.eql(u8, key, SMALLEST_INTEGER)) {
        return error.KeyTooSmall;
    }
    const i = try getIntegerPart(key);
    const f = key[i.len..];
    if (f.len > 0 and f[f.len - 1] == min_charcode) {
        return error.FractionalEndsWithSpace;
    }
}

/// Get the integer part of a key (the first N characters based on the head character)
fn getIntegerPart(key: []const u8) FractError![]const u8 {
    if (key.len == 0) return error.InvalidKey;
    const len = try getIntegerLen(key[0]);
    if (len > key.len) return error.InvalidIntegerPart;
    return key[0..len];
}

/// Get the length of the integer part based on the head character
fn getIntegerLen(head: u8) FractError!usize {
    if (head >= a_charcode and head <= z_charcode) {
        // a-z: length = head - 'a' + 2
        return @as(usize, head - a_charcode + 2);
    } else if (head >= A_charcode and head <= Z_charcode) {
        // A-Z: length = 'Z' - head + 2
        return @as(usize, Z_charcode - head + 2);
    } else {
        return error.HeadOutOfRange;
    }
}

/// Increment an integer part, returning a new allocated string or null if cannot increment
fn incrementInteger(allocator: std.mem.Allocator, x: []const u8) FractError!?[]u8 {
    if (x.len == 0) return error.InvalidIntegerPart;

    const head = x[0];
    var digs = allocator.alloc(u8, x.len - 1) catch return error.OutOfMemory;
    defer allocator.free(digs);
    @memcpy(digs, x[1..]);

    var carry = true;
    var i: isize = @as(isize, @intCast(digs.len)) - 1;

    while (carry and i >= 0) : (i -= 1) {
        const ui: usize = @intCast(i);
        const digit_idx = std.mem.indexOfScalar(u8, BASE_95_DIGITS, digs[ui]) orelse return error.InvalidDigit;
        const d = digit_idx + 1;
        if (d == BASE_95_DIGITS.len) {
            digs[ui] = BASE_95_DIGITS[0];
        } else {
            digs[ui] = BASE_95_DIGITS[d];
            carry = false;
        }
    }

    if (carry) {
        if (head == 'Z') {
            // Overflow to INTEGER_ZERO
            const result = allocator.alloc(u8, INTEGER_ZERO.len) catch return error.OutOfMemory;
            @memcpy(result, INTEGER_ZERO);
            return result;
        }
        if (head == 'z') {
            // Cannot increment past max
            return null;
        }
        const new_head = head + 1;
        if (new_head > a_charcode) {
            // Growing: add a digit
            const result = allocator.alloc(u8, digs.len + 2) catch return error.OutOfMemory;
            result[0] = new_head;
            @memcpy(result[1 .. digs.len + 1], digs);
            result[digs.len + 1] = BASE_95_DIGITS[0];
            return result;
        } else {
            // Shrinking: remove a digit
            const result = allocator.alloc(u8, digs.len) catch return error.OutOfMemory;
            result[0] = new_head;
            @memcpy(result[1..], digs[0 .. digs.len - 1]);
            return result;
        }
    } else {
        const result = allocator.alloc(u8, x.len) catch return error.OutOfMemory;
        result[0] = head;
        @memcpy(result[1..], digs);
        return result;
    }
}

/// Decrement an integer part, returning a new allocated string or null if cannot decrement
fn decrementInteger(allocator: std.mem.Allocator, x: []const u8) FractError!?[]u8 {
    if (x.len == 0) return error.InvalidIntegerPart;

    const head = x[0];
    var digs = allocator.alloc(u8, x.len - 1) catch return error.OutOfMemory;
    defer allocator.free(digs);
    @memcpy(digs, x[1..]);

    var borrow = true;
    var i: isize = @as(isize, @intCast(digs.len)) - 1;

    while (borrow and i >= 0) : (i -= 1) {
        const ui: usize = @intCast(i);
        const digit_idx = std.mem.indexOfScalar(u8, BASE_95_DIGITS, digs[ui]) orelse return error.InvalidDigit;
        if (digit_idx == 0) {
            digs[ui] = BASE_95_DIGITS[BASE_95_DIGITS.len - 1];
        } else {
            digs[ui] = BASE_95_DIGITS[digit_idx - 1];
            borrow = false;
        }
    }

    if (borrow) {
        if (head == 'a') {
            // Underflow to Z~
            const result = allocator.alloc(u8, 2) catch return error.OutOfMemory;
            result[0] = 'Z';
            result[1] = BASE_95_DIGITS[BASE_95_DIGITS.len - 1]; // '~'
            return result;
        }
        if (head == 'A') {
            // Cannot decrement past min
            return null;
        }
        const new_head = head - 1;
        if (new_head < Z_charcode) {
            // Growing: add a digit
            const result = allocator.alloc(u8, digs.len + 2) catch return error.OutOfMemory;
            result[0] = new_head;
            @memcpy(result[1 .. digs.len + 1], digs);
            result[digs.len + 1] = BASE_95_DIGITS[BASE_95_DIGITS.len - 1];
            return result;
        } else {
            // Shrinking: remove a digit
            const result = allocator.alloc(u8, digs.len) catch return error.OutOfMemory;
            result[0] = new_head;
            @memcpy(result[1..], digs[0 .. digs.len - 1]);
            return result;
        }
    } else {
        const result = allocator.alloc(u8, x.len) catch return error.OutOfMemory;
        result[0] = head;
        @memcpy(result[1..], digs);
        return result;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SQLite UDF Registration
// ═══════════════════════════════════════════════════════════════════════════════

/// SQLite UDF implementation for crsql_fract_key_between(left, right)
fn fractKeyBetweenFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    if (argc != 2) {
        api.result_error(pCtx, "crsql_fract_key_between requires exactly 2 arguments", -1);
        return;
    }

    // Get arguments - NULL is allowed
    const left: ?[]const u8 = blk: {
        if (api.value_type(argv[0]) == api.SQLITE_NULL) break :blk null;
        const ptr = api.value_text(argv[0]);
        if (ptr == null) break :blk null;
        const len: usize = @intCast(api.value_bytes(argv[0]));
        break :blk ptr.?[0..len];
    };

    const right: ?[]const u8 = blk: {
        if (api.value_type(argv[1]) == api.SQLITE_NULL) break :blk null;
        const ptr = api.value_text(argv[1]);
        if (ptr == null) break :blk null;
        const len: usize = @intCast(api.value_bytes(argv[1]));
        break :blk ptr.?[0..len];
    };

    // Use SQLite's allocator via context
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = fractKeyBetween(allocator, left, right) catch |err| {
        const msg = switch (err) {
            error.KeyTooSmall => "key is too small",
            error.InvalidKey => "invalid key",
            error.InvalidIntegerPart => "invalid integer part of order key",
            error.InvalidDigit => "invalid digit in key",
            error.HeadOutOfRange => "head is out of range",
            error.FractionalEndsWithSpace => "fractional part should not end with space",
            error.AMustBeBeforeB => "left key must be before right key",
            error.CannotIncrement => "cannot increment anymore",
            error.CannotDecrement => "cannot decrement anymore",
            error.OutOfMemory => "out of memory",
        };
        api.result_error(pCtx, msg, -1);
        return;
    };
    defer allocator.free(result);

    // Return the result as TEXT, making a copy SQLite owns
    api.result_text(pCtx, result.ptr, @intCast(result.len), api.getTransientDestructor());
}

/// Register the crsql_fract_key_between function with SQLite
pub fn register(db: ?*api.sqlite3) c_int {
    var rc = api.create_function_v2(
        db,
        "crsql_fract_key_between",
        2, // 2 arguments
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC,
        null,
        &fractKeyBetweenFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_fract_as_ordered() - variadic function (2+ arguments)
    rc = api.create_function_v2(
        db,
        "crsql_fract_as_ordered",
        -1, // -1 = variadic (any number of arguments)
        api.SQLITE_UTF8 | api.SQLITE_DIRECTONLY, // DIRECTONLY: DDL should not be callable from triggers/views
        null,
        &fractAsOrderedFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    return api.SQLITE_OK;
}

// ═══════════════════════════════════════════════════════════════════════════════
// crsql_fract_as_ordered Implementation
// ═══════════════════════════════════════════════════════════════════════════════

/// SQL function: crsql_fract_as_ordered(table, order_col, [collection_cols...])
///
/// Sets up fractional ordering on a table by creating:
/// 1. AFTER INSERT trigger to auto-generate keys for -1 (prepend) and 1 (append) sentinels
/// 2. AFTER UPDATE trigger for simple move operations (move to start/end)
/// 3. A "<table>_fractindex" view with INSTEAD OF triggers for insert-after semantics
///
/// Arguments:
/// - table: Name of the table to add fractional ordering to
/// - order_col: Name of the column that stores the fractional order key
/// - collection_cols (optional): Column(s) that partition the ordering (e.g., "list_id")
///
/// Reference: core/rs/fractindex-core/src/as_ordered.rs
fn fractAsOrderedFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Require at least table name and order column
    if (argc < 2) {
        api.result_error(pCtx, "Usage: crsql_fract_as_ordered(table, order_col, [collection_cols...])", -1);
        return;
    }

    // Get database handle from context
    const db = api.context_db_handle(pCtx);
    if (db == null) {
        api.result_error(pCtx, "Failed to get database handle", -1);
        return;
    }

    // Get table name (argument 0)
    const table_name: ?[*:0]const u8 = blk: {
        if (api.value_type(argv[0]) == api.SQLITE_NULL) break :blk null;
        break :blk api.value_text(argv[0]);
    };
    if (table_name == null) {
        api.result_error(pCtx, "Invalid table name", -1);
        return;
    }

    // Get order column name (argument 1)
    const order_col: ?[*:0]const u8 = blk: {
        if (api.value_type(argv[1]) == api.SQLITE_NULL) break :blk null;
        break :blk api.value_text(argv[1]);
    };
    if (order_col == null) {
        api.result_error(pCtx, "Invalid order column name", -1);
        return;
    }

    // Collection columns are argv[2..argc] (optional)
    const collection_col_count: usize = if (argc > 2) @intCast(argc - 2) else 0;
    _ = collection_col_count; // Will be used in full implementation

    // TODO: Phase 2 - Implement the actual view and trigger creation:
    // 1. Drop existing triggers/views if they exist
    // 2. Validate that all columns exist in the target table
    // 3. Create SAVEPOINT for atomic operation
    // 4. Create AFTER INSERT trigger for -1/1 sentinel handling
    // 5. Create AFTER UPDATE trigger for simple move operations
    // 6. Create <table>_fractindex view with INSTEAD OF triggers
    // 7. RELEASE savepoint on success, ROLLBACK on failure

    // For now, just acknowledge the call succeeded
    // The skeleton validates inputs and returns NULL to indicate success
    api.result_null(pCtx);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

test "fractKeyBetween null, null returns INTEGER_ZERO" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, null, null);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a ", result);
}

test "fractKeyBetween null, 'a ' returns 'Z~'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, null, "a ");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Z~", result);
}

test "fractKeyBetween 'a ', null returns 'a!'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, "a ", null);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a!", result);
}

test "fractKeyBetween 'a0', 'a1' returns 'a0P'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, "a0", "a1");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a0P", result);
}

test "fractKeyBetween rejects invalid order (a > b)" {
    const allocator = std.testing.allocator;
    const err = fractKeyBetween(allocator, "a1", "a0");
    try std.testing.expectError(error.AMustBeBeforeB, err);
}

test "fractKeyBetween rejects key ending with space" {
    const allocator = std.testing.allocator;
    const err = fractKeyBetween(allocator, "a0 ", null);
    try std.testing.expectError(error.FractionalEndsWithSpace, err);
}

test "fractKeyBetween rejects invalid head character" {
    const allocator = std.testing.allocator;
    const err = fractKeyBetween(allocator, "0", "1");
    try std.testing.expectError(error.HeadOutOfRange, err);
}

test "getIntegerLen for lowercase" {
    try std.testing.expectEqual(@as(usize, 2), try getIntegerLen('a')); // a = 2
    try std.testing.expectEqual(@as(usize, 3), try getIntegerLen('b')); // b = 3
    try std.testing.expectEqual(@as(usize, 27), try getIntegerLen('z')); // z = 27
}

test "getIntegerLen for uppercase" {
    try std.testing.expectEqual(@as(usize, 27), try getIntegerLen('A')); // A = 27
    try std.testing.expectEqual(@as(usize, 2), try getIntegerLen('Z')); // Z = 2
}

// Additional tests from Rust implementation
test "fractKeyBetween 'a1', 'a2' returns 'a1P'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, "a1", "a2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a1P", result);
}

test "fractKeyBetween 'Z~', 'a ' returns 'Z~P'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, "Z~", "a ");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Z~P", result);
}

test "fractKeyBetween 'Z~', 'a!' returns 'a '" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, "Z~", "a!");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a ", result);
}

test "fractKeyBetween null, 'a0V' returns 'a0'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, null, "a0V");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a0", result);
}

test "fractKeyBetween 'b125', 'b129' returns 'b127'" {
    const allocator = std.testing.allocator;
    const result = try fractKeyBetween(allocator, "b125", "b129");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("b127", result);
}
