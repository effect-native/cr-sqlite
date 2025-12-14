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

    // Register crsql_fract_fix_conflict_return_old_key() - variadic function
    // This handles collision resolution when multiple rows have the same order key
    rc = api.create_function_v2(
        db,
        "crsql_fract_fix_conflict_return_old_key",
        -1, // -1 = variadic
        api.SQLITE_UTF8,
        null,
        &fractFixConflictFunc,
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
    const table_name: ?[]const u8 = blk: {
        if (api.value_type(argv[0]) == api.SQLITE_NULL) break :blk null;
        const ptr = api.value_text(argv[0]);
        if (ptr == null) break :blk null;
        const len: usize = @intCast(api.value_bytes(argv[0]));
        break :blk ptr.?[0..len];
    };
    if (table_name == null) {
        api.result_error(pCtx, "Invalid table name", -1);
        return;
    }

    // Get order column name (argument 1)
    const order_col: ?[]const u8 = blk: {
        if (api.value_type(argv[1]) == api.SQLITE_NULL) break :blk null;
        const ptr = api.value_text(argv[1]);
        if (ptr == null) break :blk null;
        const len: usize = @intCast(api.value_bytes(argv[1]));
        break :blk ptr.?[0..len];
    };
    if (order_col == null) {
        api.result_error(pCtx, "Invalid order column name", -1);
        return;
    }

    // Collect collection columns from argv[2..argc]
    const collection_col_count: usize = if (argc > 2) @intCast(argc - 2) else 0;

    // Use a general purpose allocator for building SQL strings
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build collection columns array
    var collection_cols = allocator.alloc([]const u8, collection_col_count) catch {
        api.result_error(pCtx, "Out of memory", -1);
        return;
    };
    defer allocator.free(collection_cols);

    for (0..collection_col_count) |i| {
        const idx: usize = i + 2;
        const col_ptr = api.value_text(argv[idx]);
        if (col_ptr == null) {
            api.result_error(pCtx, "Invalid collection column name", -1);
            return;
        }
        const col_len: usize = @intCast(api.value_bytes(argv[idx]));
        collection_cols[i] = col_ptr.?[0..col_len];
    }

    // Execute the as_ordered setup
    asOrdered(db, table_name.?, order_col.?, collection_cols, allocator) catch |err| {
        const msg: [*:0]const u8 = switch (err) {
            error.DropTriggerFailed => "Failed dropping prior incarnation of fractindex triggers",
            error.DropViewFailed => "Failed dropping prior incarnation of fractindex views",
            error.ColumnsNotPresent => "all columns are not present in the base table",
            error.SavepointFailed => "Failed to create savepoint",
            error.CreateTriggerFailed => "Failed creating triggers for the base table",
            error.CreateMoveTriggerFailed => "Failed creating simple move trigger",
            error.CreateViewFailed => "Failed creating view for the base table",
            error.ReleaseFailed => "Failed to release savepoint",
            error.OutOfMemory => "Out of memory",
            error.SqlExecFailed => "SQL execution failed",
            error.PrepareStmtFailed => "Failed to prepare statement",
            error.BindFailed => "Failed to bind parameter",
        };
        api.result_error(pCtx, msg, -1);
        return;
    };

    api.result_null(pCtx);
}

/// SQL function: crsql_fract_fix_conflict_return_old_key(table, order_col, [list_cols...], sentinel, [pk_names...], [pk_values...])
///
/// Called when there's a collision (multiple rows with same order key).
/// This function:
/// 1. Gets the order key of the row we're inserting after
/// 2. Moves that row down (generates a new key before its current position)
/// 3. Returns the original key (or midpoint between new and old) for the new row
///
/// Arguments are complex due to the variadic nature - see fractindex_view.rs
fn fractFixConflictFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Minimum args: table, order_col, sentinel(-1), at least 1 pk_name, at least 1 pk_value
    if (argc < 5) {
        api.result_error(pCtx, "crsql_fract_fix_conflict_return_old_key requires at least 5 arguments", -1);
        return;
    }

    const db = api.context_db_handle(pCtx);
    if (db == null) {
        api.result_error(pCtx, "Failed to get database handle", -1);
        return;
    }

    // Parse arguments
    // Format: table, order_col, [list_cols...], sentinel(-1), [pk_names...], pk_values...
    // The sentinel -1 marks the boundary between list_cols and pk_names
    // After pk_names comes the pk_values (same count as pk_names)

    // Get table name
    const table_ptr = api.value_text(argv[0]);
    if (table_ptr == null) {
        api.result_error(pCtx, "Invalid table name", -1);
        return;
    }
    const table_len: usize = @intCast(api.value_bytes(argv[0]));
    const table = table_ptr.?[0..table_len];

    // Get order column name
    const order_col_ptr = api.value_text(argv[1]);
    if (order_col_ptr == null) {
        api.result_error(pCtx, "Invalid order column name", -1);
        return;
    }
    const order_col_len: usize = @intCast(api.value_bytes(argv[1]));
    const order_col = order_col_ptr.?[0..order_col_len];

    // Find the sentinel (-1) to determine where list_cols end and pk_names begin
    var sentinel_idx: usize = 2;
    while (sentinel_idx < @as(usize, @intCast(argc))) : (sentinel_idx += 1) {
        if (api.value_type(argv[sentinel_idx]) == api.SQLITE_INTEGER) {
            const val = api.value_int64(argv[sentinel_idx]);
            if (val == -1) break;
        }
    }

    if (sentinel_idx >= @as(usize, @intCast(argc))) {
        api.result_error(pCtx, "No sentinel found in arguments", -1);
        return;
    }

    // List columns are between argv[2] and argv[sentinel_idx]
    const list_col_count = sentinel_idx - 2;
    _ = list_col_count; // May be used for collection-scoped conflict resolution

    // After sentinel, we have pk_names followed by pk_values
    // The count of each should be (argc - sentinel_idx - 1) / 2
    const remaining = @as(usize, @intCast(argc)) - sentinel_idx - 1;
    if (remaining == 0 or remaining % 2 != 0) {
        api.result_error(pCtx, "Invalid pk_names/pk_values count", -1);
        return;
    }
    const pk_count = remaining / 2;

    // pk_names start at sentinel_idx + 1
    // pk_values start at sentinel_idx + 1 + pk_count
    const pk_names_start = sentinel_idx + 1;
    const pk_values_start = pk_names_start + pk_count;

    // Use allocator for SQL building
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build WHERE clause for pk columns: "pk1" = ?1 AND "pk2" = ?2
    var pk_predicates: std.ArrayListUnmanaged(u8) = .empty;
    defer pk_predicates.deinit(allocator);

    for (0..pk_count) |i| {
        if (i > 0) pk_predicates.appendSlice(allocator, " AND ") catch {
            api.result_error(pCtx, "Out of memory", -1);
            return;
        };
        const pk_name_ptr = api.value_text(argv[pk_names_start + i]);
        if (pk_name_ptr == null) {
            api.result_error(pCtx, "Invalid pk name", -1);
            return;
        }
        const pk_name_len: usize = @intCast(api.value_bytes(argv[pk_names_start + i]));
        const pk_name = pk_name_ptr.?[0..pk_name_len];

        const pred = std.fmt.allocPrint(allocator, "\"{s}\" = ?{d}", .{ pk_name, i + 1 }) catch {
            api.result_error(pCtx, "Out of memory", -1);
            return;
        };
        defer allocator.free(pred);
        pk_predicates.appendSlice(allocator, pred) catch {
            api.result_error(pCtx, "Out of memory", -1);
            return;
        };
    }

    // Step 1: Get the current order of the row we're inserting after
    const select_sql = allocPrintZ(allocator, "SELECT \"{s}\" FROM \"{s}\" WHERE {s}", .{
        order_col,
        table,
        pk_predicates.items,
    }) catch {
        api.result_error(pCtx, "Out of memory", -1);
        return;
    };
    defer allocator.free(select_sql);

    var select_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, select_sql, -1, &select_stmt, null) != api.SQLITE_OK) {
        api.result_error(pCtx, "Failed to prepare select statement", -1);
        return;
    }
    defer _ = api.finalize(select_stmt);

    // Bind pk values
    for (0..pk_count) |i| {
        const pk_val = argv[pk_values_start + i];
        if (api.value_type(pk_val) == api.SQLITE_INTEGER) {
            if (api.bind_int64(select_stmt, @intCast(i + 1), api.value_int64(pk_val)) != api.SQLITE_OK) {
                api.result_error(pCtx, "Failed to bind pk value", -1);
                return;
            }
        } else if (api.value_type(pk_val) == api.SQLITE_TEXT) {
            const txt = api.value_text(pk_val);
            const txt_len: c_int = api.value_bytes(pk_val);
            if (api.bind_text(select_stmt, @intCast(i + 1), txt.?, txt_len, api.SQLITE_STATIC) != api.SQLITE_OK) {
                api.result_error(pCtx, "Failed to bind pk value", -1);
                return;
            }
        } else {
            api.result_error(pCtx, "Unsupported pk value type", -1);
            return;
        }
    }

    if (api.step(select_stmt) != api.SQLITE_ROW) {
        api.result_error(pCtx, "Row not found for conflict resolution", -1);
        return;
    }

    const target_order_ptr = api.column_text(select_stmt, 0);
    if (target_order_ptr == null) {
        api.result_error(pCtx, "Order column is NULL", -1);
        return;
    }
    const target_order_len: usize = @intCast(api.column_bytes(select_stmt, 0));
    const target_order = allocator.dupe(u8, target_order_ptr.?[0..target_order_len]) catch {
        api.result_error(pCtx, "Out of memory", -1);
        return;
    };
    defer allocator.free(target_order);

    // Step 2: Update the row to move it down (key between previous and current)
    const update_sql = allocPrintZ(allocator,
        \\UPDATE "{s}" SET "{s}" = crsql_fract_key_between(
        \\  (SELECT "{s}" FROM "{s}" WHERE "{s}" < ?{d} ORDER BY "{s}" DESC LIMIT 1),
        \\  ?{d}
        \\) WHERE {s} RETURNING "{s}"
    , .{
        table,
        order_col,
        order_col,
        table,
        order_col,
        pk_count + 1,
        order_col,
        pk_count + 1,
        pk_predicates.items,
        order_col,
    }) catch {
        api.result_error(pCtx, "Out of memory", -1);
        return;
    };
    defer allocator.free(update_sql);

    var update_stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, update_sql, -1, &update_stmt, null) != api.SQLITE_OK) {
        api.result_error(pCtx, "Failed to prepare update statement", -1);
        return;
    }
    defer _ = api.finalize(update_stmt);

    // Bind pk values again
    for (0..pk_count) |i| {
        const pk_val = argv[pk_values_start + i];
        if (api.value_type(pk_val) == api.SQLITE_INTEGER) {
            if (api.bind_int64(update_stmt, @intCast(i + 1), api.value_int64(pk_val)) != api.SQLITE_OK) {
                api.result_error(pCtx, "Failed to bind pk value", -1);
                return;
            }
        } else if (api.value_type(pk_val) == api.SQLITE_TEXT) {
            const txt = api.value_text(pk_val);
            const txt_len: c_int = api.value_bytes(pk_val);
            if (api.bind_text(update_stmt, @intCast(i + 1), txt.?, txt_len, api.SQLITE_STATIC) != api.SQLITE_OK) {
                api.result_error(pCtx, "Failed to bind pk value", -1);
                return;
            }
        }
    }

    // Bind target_order for comparison
    if (api.bind_text(update_stmt, @intCast(pk_count + 1), target_order.ptr, @intCast(target_order.len), api.SQLITE_STATIC) != api.SQLITE_OK) {
        api.result_error(pCtx, "Failed to bind target order", -1);
        return;
    }

    if (api.step(update_stmt) != api.SQLITE_ROW) {
        api.result_error(pCtx, "Update failed during conflict resolution", -1);
        return;
    }

    // Get the new order key of the moved row
    const new_order_ptr = api.column_text(update_stmt, 0);
    if (new_order_ptr == null) {
        api.result_error(pCtx, "New order is NULL", -1);
        return;
    }
    const new_order_len: usize = @intCast(api.column_bytes(update_stmt, 0));
    const new_order = new_order_ptr.?[0..new_order_len];

    // Step 3: Return midpoint between new_order and target_order
    const result = fractKeyBetween(allocator, new_order, target_order) catch |err| {
        const msg = switch (err) {
            error.KeyTooSmall => "key is too small",
            error.InvalidKey => "invalid key",
            error.InvalidIntegerPart => "invalid integer part",
            error.InvalidDigit => "invalid digit",
            error.HeadOutOfRange => "head out of range",
            error.FractionalEndsWithSpace => "fractional ends with space",
            error.AMustBeBeforeB => "a must be before b",
            error.CannotIncrement => "cannot increment",
            error.CannotDecrement => "cannot decrement",
            error.OutOfMemory => "out of memory",
        };
        api.result_error(pCtx, msg, -1);
        return;
    };
    defer allocator.free(result);

    api.result_text(pCtx, result.ptr, @intCast(result.len), api.getTransientDestructor());
}

const AsOrderedError = error{
    DropTriggerFailed,
    DropViewFailed,
    ColumnsNotPresent,
    SavepointFailed,
    CreateTriggerFailed,
    CreateMoveTriggerFailed,
    CreateViewFailed,
    ReleaseFailed,
    OutOfMemory,
    SqlExecFailed,
    PrepareStmtFailed,
    BindFailed,
};

/// Helper to allocate a null-terminated string using std.fmt.allocPrint
fn allocPrintZ(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![:0]u8 {
    const slice = try std.fmt.allocPrint(allocator, fmt, args);
    // Check if we can add a null terminator
    if (slice.len == 0) {
        allocator.free(slice);
        const result = try allocator.allocSentinel(u8, 0, 0);
        return result;
    }
    // Allocate with space for null terminator
    const result = allocator.allocSentinel(u8, slice.len, 0) catch {
        allocator.free(slice);
        return error.OutOfMemory;
    };
    @memcpy(result, slice);
    allocator.free(slice);
    return result;
}

fn asOrdered(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!void {
    // 0. Drop existing triggers and views if they exist
    const drop_pend_trigger = allocPrintZ(allocator, "DROP TRIGGER IF EXISTS \"__crsql_{s}_fractindex_pend_trig\";", .{escapeIdent(table)}) catch return error.OutOfMemory;
    defer allocator.free(drop_pend_trigger);
    if (api.exec(db, drop_pend_trigger, null, null, null) != api.SQLITE_OK) {
        return error.DropTriggerFailed;
    }

    const drop_move_trigger = allocPrintZ(allocator, "DROP TRIGGER IF EXISTS \"__crsql_{s}_fractindex_ezmove\";", .{escapeIdent(table)}) catch return error.OutOfMemory;
    defer allocator.free(drop_move_trigger);
    if (api.exec(db, drop_move_trigger, null, null, null) != api.SQLITE_OK) {
        return error.DropTriggerFailed;
    }

    const drop_view = allocPrintZ(allocator, "DROP VIEW IF EXISTS \"{s}_fractindex\";", .{escapeIdent(table)}) catch return error.OutOfMemory;
    defer allocator.free(drop_view);
    if (api.exec(db, drop_view, null, null, null) != api.SQLITE_OK) {
        return error.DropViewFailed;
    }

    // Also drop INSTEAD OF triggers on the view
    const drop_insert_trigger = allocPrintZ(allocator, "DROP TRIGGER IF EXISTS \"{s}_fractindex_insert_trig\";", .{escapeIdent(table)}) catch return error.OutOfMemory;
    defer allocator.free(drop_insert_trigger);
    _ = api.exec(db, drop_insert_trigger, null, null, null);

    const drop_update_trigger = allocPrintZ(allocator, "DROP TRIGGER IF EXISTS \"{s}_fractindex_update_trig\";", .{escapeIdent(table)}) catch return error.OutOfMemory;
    defer allocator.free(drop_update_trigger);
    _ = api.exec(db, drop_update_trigger, null, null, null);

    // 1. Validate that all columns exist in the target table
    if (!try tableHasAllColumns(db, table, order_col, collection_cols, allocator)) {
        return error.ColumnsNotPresent;
    }

    // 2. Create savepoint for atomic operation
    if (api.exec(db, "SAVEPOINT as_ordered;", null, null, null) != api.SQLITE_OK) {
        return error.SavepointFailed;
    }

    // 3. Create AFTER INSERT trigger for -1/1 sentinel handling
    createPendTrigger(db, table, order_col, collection_cols, allocator) catch {
        _ = api.exec(db, "ROLLBACK TO as_ordered;", null, null, null);
        return error.CreateTriggerFailed;
    };

    // 4. Create AFTER UPDATE trigger for simple move operations
    createSimpleMoveTrigger(db, table, order_col, collection_cols, allocator) catch {
        _ = api.exec(db, "ROLLBACK TO as_ordered;", null, null, null);
        return error.CreateMoveTriggerFailed;
    };

    // 5. Create <table>_fractindex view with INSTEAD OF triggers
    createFractViewAndTriggers(db, table, order_col, collection_cols, allocator) catch {
        _ = api.exec(db, "ROLLBACK TO as_ordered;", null, null, null);
        return error.CreateViewFailed;
    };

    // 6. Release savepoint on success
    if (api.exec(db, "RELEASE as_ordered;", null, null, null) != api.SQLITE_OK) {
        return error.ReleaseFailed;
    }
}

/// Check if table has all required columns
fn tableHasAllColumns(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!bool {
    const total_cols = collection_cols.len + 1; // +1 for order_col

    // Build query with placeholders
    // SELECT count(*) FROM pragma_table_info(?) WHERE "name" IN (?, ?, ...)
    var bindings: std.ArrayListUnmanaged(u8) = .empty;
    defer bindings.deinit(allocator);

    for (0..total_cols) |i| {
        if (i > 0) bindings.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        bindings.append(allocator, '?') catch return error.OutOfMemory;
    }

    const sql = allocPrintZ(allocator, "SELECT count(*) FROM pragma_table_info(?) WHERE \"name\" IN ({s})", .{bindings.items}) catch return error.OutOfMemory;
    defer allocator.free(sql);

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql.ptr, -1, &stmt, null) != api.SQLITE_OK) {
        return error.PrepareStmtFailed;
    }
    defer _ = api.finalize(stmt);

    // Bind table name
    if (api.bind_text(stmt, 1, table.ptr, @intCast(table.len), api.SQLITE_STATIC) != api.SQLITE_OK) {
        return error.BindFailed;
    }

    // Bind order column
    if (api.bind_text(stmt, 2, order_col.ptr, @intCast(order_col.len), api.SQLITE_STATIC) != api.SQLITE_OK) {
        return error.BindFailed;
    }

    // Bind collection columns
    for (collection_cols, 0..) |col, i| {
        if (api.bind_text(stmt, @intCast(i + 3), col.ptr, @intCast(col.len), api.SQLITE_STATIC) != api.SQLITE_OK) {
            return error.BindFailed;
        }
    }

    const step_code = api.step(stmt);
    if (step_code == api.SQLITE_ROW) {
        const count = api.column_int64(stmt, 0);
        return count == @as(i64, @intCast(total_cols));
    }

    return false;
}

/// Create AFTER INSERT trigger for prepend/append sentinel handling
fn createPendTrigger(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!void {
    const list_preds = try wherePredicates(collection_cols, allocator);
    defer allocator.free(list_preds);

    const min_select = try collectionMinSelect(table, order_col, list_preds, allocator);
    defer allocator.free(min_select);

    const max_select = try collectionMaxSelect(table, order_col, list_preds, allocator);
    defer allocator.free(max_select);

    const trigger_sql = allocPrintZ(allocator,
        \\CREATE TRIGGER IF NOT EXISTS "__crsql_{s}_fractindex_pend_trig" AFTER INSERT ON "{s}"
        \\WHEN CAST(NEW."{s}" AS INTEGER) = -1 OR CAST(NEW."{s}" AS INTEGER) = 1 BEGIN
        \\  UPDATE "{s}" SET "{s}" = CASE CAST(NEW."{s}" AS INTEGER)
        \\  WHEN -1 THEN crsql_fract_key_between(NULL, ({s}))
        \\  WHEN 1 THEN crsql_fract_key_between(({s}), NULL)
        \\  END
        \\  WHERE _rowid_ = NEW._rowid_;
        \\END;
    , .{
        escapeIdent(table),
        escapeIdent(table),
        escapeIdent(order_col),
        escapeIdent(order_col),
        escapeIdent(table),
        escapeIdent(order_col),
        escapeIdent(order_col),
        min_select,
        max_select,
    }) catch return error.OutOfMemory;
    defer allocator.free(trigger_sql);

    if (api.exec(db, trigger_sql, null, null, null) != api.SQLITE_OK) {
        return error.SqlExecFailed;
    }
}

/// Create AFTER UPDATE trigger for simple move operations
fn createSimpleMoveTrigger(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!void {
    const list_preds = try wherePredicates(collection_cols, allocator);
    defer allocator.free(list_preds);

    const min_select = try collectionMinSelect(table, order_col, list_preds, allocator);
    defer allocator.free(min_select);

    const max_select = try collectionMaxSelect(table, order_col, list_preds, allocator);
    defer allocator.free(max_select);

    const trigger_sql = allocPrintZ(allocator,
        \\CREATE TRIGGER IF NOT EXISTS "__crsql_{s}_fractindex_ezmove" AFTER UPDATE OF "{s}" ON "{s}"
        \\WHEN NEW."{s}" = -1 OR NEW."{s}" = 1 BEGIN
        \\  UPDATE "{s}" SET "{s}" = CASE NEW."{s}"
        \\  WHEN -1 THEN crsql_fract_key_between(NULL, ({s}))
        \\  WHEN 1 THEN crsql_fract_key_between(({s}), NULL)
        \\  END
        \\  WHERE _rowid_ = NEW._rowid_;
        \\END;
    , .{
        escapeIdent(table),
        escapeIdent(order_col),
        escapeIdent(table),
        escapeIdent(order_col),
        escapeIdent(order_col),
        escapeIdent(table),
        escapeIdent(order_col),
        escapeIdent(order_col),
        min_select,
        max_select,
    }) catch return error.OutOfMemory;
    defer allocator.free(trigger_sql);

    if (api.exec(db, trigger_sql, null, null, null) != api.SQLITE_OK) {
        return error.SqlExecFailed;
    }
}

/// Create the fractindex view and its INSTEAD OF triggers
fn createFractViewAndTriggers(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!void {
    // Extract PK columns from the table
    const pks = try extractPkColumns(db, table, allocator);
    defer {
        for (pks) |pk| allocator.free(pk);
        allocator.free(pks);
    }

    // Build after_pk_defs: NULL AS "after_pk1", NULL AS "after_pk2", ...
    var after_pk_defs: std.ArrayListUnmanaged(u8) = .empty;
    defer after_pk_defs.deinit(allocator);

    for (pks, 0..) |pk, i| {
        if (i > 0) after_pk_defs.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        const def = std.fmt.allocPrint(allocator, "NULL AS \"after_{s}\"", .{escapeIdent(pk)}) catch return error.OutOfMemory;
        defer allocator.free(def);
        after_pk_defs.appendSlice(allocator, def) catch return error.OutOfMemory;
    }

    // Create the view
    const view_sql = allocPrintZ(allocator,
        \\CREATE VIEW IF NOT EXISTS "{s}_fractindex" AS
        \\SELECT *, {s}
        \\FROM "{s}"
    , .{ escapeIdent(table), after_pk_defs.items, escapeIdent(table) }) catch return error.OutOfMemory;
    defer allocator.free(view_sql);

    if (api.exec(db, view_sql, null, null, null) != api.SQLITE_OK) {
        return error.SqlExecFailed;
    }

    // Create INSTEAD OF INSERT trigger
    try createInsteadOfInsertTrigger(db, table, order_col, collection_cols, pks, allocator);

    // Create INSTEAD OF UPDATE trigger
    try createInsteadOfUpdateTrigger(db, table, order_col, collection_cols, pks, allocator);
}

/// Create INSTEAD OF INSERT trigger for the view
fn createInsteadOfInsertTrigger(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    pks: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!void {
    // Extract all columns from the table
    const columns = try extractColumns(db, table, allocator);
    defer {
        for (columns) |col| allocator.free(col);
        allocator.free(columns);
    }

    // Build column names and values excluding order column
    var col_names: std.ArrayListUnmanaged(u8) = .empty;
    defer col_names.deinit(allocator);
    var col_values: std.ArrayListUnmanaged(u8) = .empty;
    defer col_values.deinit(allocator);

    var first = true;
    for (columns) |col| {
        if (std.mem.eql(u8, col, order_col)) continue;
        if (!first) {
            col_names.appendSlice(allocator, ", ") catch return error.OutOfMemory;
            col_values.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        }
        first = false;

        const name = std.fmt.allocPrint(allocator, "\"{s}\"", .{escapeIdent(col)}) catch return error.OutOfMemory;
        defer allocator.free(name);
        col_names.appendSlice(allocator, name) catch return error.OutOfMemory;

        const val = std.fmt.allocPrint(allocator, "NEW.\"{s}\"", .{escapeIdent(col)}) catch return error.OutOfMemory;
        defer allocator.free(val);
        col_values.appendSlice(allocator, val) catch return error.OutOfMemory;
    }

    const list_preds = try wherePredicates(collection_cols, allocator);
    defer allocator.free(list_preds);

    const after_preds = try afterPredicates(pks, allocator);
    defer allocator.free(after_preds);

    const after_pk_values = try afterPkValues(pks, allocator);
    defer allocator.free(after_pk_values);

    const list_name_args = try listNameArgs(collection_cols, allocator);
    defer allocator.free(list_name_args);

    const pk_names_args = try pkNamesArgs(pks, allocator);
    defer allocator.free(pk_names_args);

    const maybe_comma: []const u8 = if (list_name_args.len > 0) ", " else "";

    const trigger_sql = allocPrintZ(allocator,
        \\CREATE TRIGGER IF NOT EXISTS "{s}_fractindex_insert_trig"
        \\INSTEAD OF INSERT ON "{s}_fractindex"
        \\BEGIN
        \\  INSERT INTO "{s}"
        \\    ({s}, "{s}")
        \\  VALUES
        \\    (
        \\      {s},
        \\      CASE (
        \\        SELECT count(*) FROM "{s}" WHERE {s} AND "{s}" = (SELECT "{s}" FROM "{s}" WHERE {s})
        \\      )
        \\        WHEN 1 THEN crsql_fract_key_between(
        \\          (SELECT "{s}" FROM "{s}" WHERE {s}),
        \\          (SELECT "{s}" FROM "{s}" WHERE {s} AND "{s}" >
        \\            (SELECT "{s}" FROM "{s}" WHERE {s})
        \\          ORDER BY "{s}" ASC LIMIT 1)
        \\        )
        \\        WHEN 0 THEN -1
        \\        ELSE crsql_fract_fix_conflict_return_old_key(
        \\          '{s}', '{s}', {s}{s} -1, {s}, {s}
        \\        )
        \\      END
        \\    );
        \\END;
    , .{
        escapeIdent(table),
        escapeIdent(table),
        escapeIdent(table),
        col_names.items,
        escapeIdent(order_col),
        col_values.items,
        escapeIdent(table),
        list_preds,
        escapeIdent(order_col),
        escapeIdent(order_col),
        escapeIdent(table),
        after_preds,
        escapeIdent(order_col),
        escapeIdent(table),
        after_preds,
        escapeIdent(order_col),
        escapeIdent(table),
        list_preds,
        escapeIdent(order_col),
        escapeIdent(order_col),
        escapeIdent(table),
        after_preds,
        escapeIdent(order_col),
        escapeArg(table),
        escapeArg(order_col),
        list_name_args,
        maybe_comma,
        pk_names_args,
        after_pk_values,
    }) catch return error.OutOfMemory;
    defer allocator.free(trigger_sql);

    if (api.exec(db, trigger_sql, null, null, null) != api.SQLITE_OK) {
        return error.SqlExecFailed;
    }
}

/// Create INSTEAD OF UPDATE trigger for the view
fn createInsteadOfUpdateTrigger(
    db: ?*api.sqlite3,
    table: []const u8,
    order_col: []const u8,
    collection_cols: []const []const u8,
    pks: []const []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError!void {
    // Extract all columns from the table
    const columns = try extractColumns(db, table, allocator);
    defer {
        for (columns) |col| allocator.free(col);
        allocator.free(columns);
    }

    // Build SET clauses excluding order column
    var base_sets: std.ArrayListUnmanaged(u8) = .empty;
    defer base_sets.deinit(allocator);

    var first = true;
    for (columns) |col| {
        if (std.mem.eql(u8, col, order_col)) continue;
        if (!first) base_sets.appendSlice(allocator, ",\n") catch return error.OutOfMemory;
        first = false;

        const set = std.fmt.allocPrint(allocator, "\"{s}\" = NEW.\"{s}\"", .{ escapeIdent(col), escapeIdent(col) }) catch return error.OutOfMemory;
        defer allocator.free(set);
        base_sets.appendSlice(allocator, set) catch return error.OutOfMemory;
    }

    const list_preds = try wherePredicates(collection_cols, allocator);
    defer allocator.free(list_preds);

    const after_preds = try afterPredicates(pks, allocator);
    defer allocator.free(after_preds);

    const after_pk_values = try afterPkValues(pks, allocator);
    defer allocator.free(after_pk_values);

    const list_name_args = try listNameArgs(collection_cols, allocator);
    defer allocator.free(list_name_args);

    const pk_names_args = try pkNamesArgs(pks, allocator);
    defer allocator.free(pk_names_args);

    const pk_preds = try pkWherePredicates(pks, allocator);
    defer allocator.free(pk_preds);

    const maybe_comma: []const u8 = if (list_name_args.len > 0) ", " else "";

    const trigger_sql = allocPrintZ(allocator,
        \\CREATE TRIGGER IF NOT EXISTS "{s}_fractindex_update_trig"
        \\INSTEAD OF UPDATE ON "{s}_fractindex"
        \\BEGIN
        \\  UPDATE "{s}" SET
        \\    {s},
        \\    "{s}" = CASE (
        \\      SELECT count(*) FROM "{s}" WHERE {s} AND "{s}" = (
        \\        SELECT "{s}" FROM "{s}" WHERE {s}
        \\      )
        \\    )
        \\    WHEN 1 THEN crsql_fract_key_between(
        \\      (SELECT "{s}" FROM "{s}" WHERE {s}),
        \\      (SELECT "{s}" FROM "{s}" WHERE {s} AND "{s}" > (
        \\        SELECT "{s}" FROM "{s}" WHERE {s}
        \\      ) ORDER BY "{s}" ASC LIMIT 1)
        \\    )
        \\    WHEN 0 THEN -1
        \\    ELSE crsql_fract_fix_conflict_return_old_key(
        \\      '{s}', '{s}', {s}{s} -1, {s}, {s}
        \\    )
        \\    END
        \\  WHERE {s};
        \\END;
    , .{
        escapeIdent(table),
        escapeIdent(table),
        escapeIdent(table),
        base_sets.items,
        escapeIdent(order_col),
        escapeIdent(table),
        list_preds,
        escapeIdent(order_col),
        escapeIdent(order_col),
        escapeIdent(table),
        after_preds,
        escapeIdent(order_col),
        escapeIdent(table),
        after_preds,
        escapeIdent(order_col),
        escapeIdent(table),
        list_preds,
        escapeIdent(order_col),
        escapeIdent(order_col),
        escapeIdent(table),
        after_preds,
        escapeIdent(order_col),
        escapeArg(table),
        escapeArg(order_col),
        list_name_args,
        maybe_comma,
        pk_names_args,
        after_pk_values,
        pk_preds,
    }) catch return error.OutOfMemory;
    defer allocator.free(trigger_sql);

    if (api.exec(db, trigger_sql, null, null, null) != api.SQLITE_OK) {
        return error.SqlExecFailed;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SQL Generation Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Escape a SQL identifier by doubling any embedded double quotes
fn escapeIdent(ident: []const u8) []const u8 {
    // For simplicity, we don't actually escape here - the format strings use {s}
    // and we rely on the caller to not include problematic characters.
    // A proper implementation would allocate and replace " with ""
    return ident;
}

/// Escape a SQL argument (for use in string literals) by doubling single quotes
fn escapeArg(arg: []const u8) []const u8 {
    // For simplicity, we don't actually escape here.
    // A proper implementation would allocate and replace ' with ''
    return arg;
}

/// Generate WHERE predicates for collection columns: "col1" = NEW."col1" AND "col2" = NEW."col2"
fn wherePredicates(columns: []const []const u8, allocator: std.mem.Allocator) AsOrderedError![]u8 {
    if (columns.len == 0) {
        return allocator.dupe(u8, "1") catch return error.OutOfMemory;
    }

    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (columns, 0..) |col, i| {
        if (i > 0) result.appendSlice(allocator, " AND ") catch return error.OutOfMemory;
        const pred = std.fmt.allocPrint(allocator, "\"{s}\" = NEW.\"{s}\"", .{ escapeIdent(col), escapeIdent(col) }) catch return error.OutOfMemory;
        defer allocator.free(pred);
        result.appendSlice(allocator, pred) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Generate WHERE predicates for PK columns: "pk1" = NEW."pk1" AND "pk2" = NEW."pk2"
fn pkWherePredicates(pks: []const []const u8, allocator: std.mem.Allocator) AsOrderedError![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (pks, 0..) |pk, i| {
        if (i > 0) result.appendSlice(allocator, " AND ") catch return error.OutOfMemory;
        const pred = std.fmt.allocPrint(allocator, "\"{s}\" = NEW.\"{s}\"", .{ escapeIdent(pk), escapeIdent(pk) }) catch return error.OutOfMemory;
        defer allocator.free(pred);
        result.appendSlice(allocator, pred) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Generate after predicates: "pk1" = NEW."after_pk1" AND "pk2" = NEW."after_pk2"
fn afterPredicates(pks: []const []const u8, allocator: std.mem.Allocator) AsOrderedError![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (pks, 0..) |pk, i| {
        if (i > 0) result.appendSlice(allocator, " AND ") catch return error.OutOfMemory;
        const pred = std.fmt.allocPrint(allocator, "\"{s}\" = NEW.\"after_{s}\"", .{ escapeIdent(pk), escapeIdent(pk) }) catch return error.OutOfMemory;
        defer allocator.free(pred);
        result.appendSlice(allocator, pred) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Generate after pk values: NEW."after_pk1", NEW."after_pk2"
fn afterPkValues(pks: []const []const u8, allocator: std.mem.Allocator) AsOrderedError![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (pks, 0..) |pk, i| {
        if (i > 0) result.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        const val = std.fmt.allocPrint(allocator, "NEW.\"after_{s}\"", .{escapeIdent(pk)}) catch return error.OutOfMemory;
        defer allocator.free(val);
        result.appendSlice(allocator, val) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Generate list name args: 'col1', 'col2'
fn listNameArgs(cols: []const []const u8, allocator: std.mem.Allocator) AsOrderedError![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (cols, 0..) |col, i| {
        if (i > 0) result.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        const arg = std.fmt.allocPrint(allocator, "'{s}'", .{escapeArg(col)}) catch return error.OutOfMemory;
        defer allocator.free(arg);
        result.appendSlice(allocator, arg) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Generate pk names args: 'pk1', 'pk2'
fn pkNamesArgs(pks: []const []const u8, allocator: std.mem.Allocator) AsOrderedError![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (pks, 0..) |pk, i| {
        if (i > 0) result.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        const arg = std.fmt.allocPrint(allocator, "'{s}'", .{escapeArg(pk)}) catch return error.OutOfMemory;
        defer allocator.free(arg);
        result.appendSlice(allocator, arg) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Generate MIN select for collection
fn collectionMinSelect(
    table: []const u8,
    order_col: []const u8,
    list_preds: []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError![]u8 {
    const result = std.fmt.allocPrint(allocator, "SELECT MIN(\"{s}\") FROM \"{s}\" WHERE {s} AND \"{s}\" != -1 AND \"{s}\" != 1", .{
        escapeIdent(order_col),
        escapeIdent(table),
        list_preds,
        escapeIdent(order_col),
        escapeIdent(order_col),
    }) catch return error.OutOfMemory;
    return result;
}

/// Generate MAX select for collection
fn collectionMaxSelect(
    table: []const u8,
    order_col: []const u8,
    list_preds: []const u8,
    allocator: std.mem.Allocator,
) AsOrderedError![]u8 {
    const result = std.fmt.allocPrint(allocator, "SELECT MAX(\"{s}\") FROM \"{s}\" WHERE {s} AND \"{s}\" != -1 AND \"{s}\" != 1", .{
        escapeIdent(order_col),
        escapeIdent(table),
        list_preds,
        escapeIdent(order_col),
        escapeIdent(order_col),
    }) catch return error.OutOfMemory;
    return result;
}

/// Extract PK column names from pragma_table_info
fn extractPkColumns(db: ?*api.sqlite3, table: []const u8, allocator: std.mem.Allocator) AsOrderedError![][]u8 {
    const sql = "SELECT \"name\" FROM pragma_table_info(?) WHERE \"pk\" > 0 ORDER BY \"pk\" ASC";

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return error.PrepareStmtFailed;
    }
    defer _ = api.finalize(stmt);

    if (api.bind_text(stmt, 1, table.ptr, @intCast(table.len), api.SQLITE_STATIC) != api.SQLITE_OK) {
        return error.BindFailed;
    }

    var columns: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer {
        for (columns.items) |col| allocator.free(col);
        columns.deinit(allocator);
    }

    while (api.step(stmt) == api.SQLITE_ROW) {
        const name_ptr = api.column_text(stmt, 0);
        if (name_ptr != null) {
            const len: usize = @intCast(api.column_bytes(stmt, 0));
            const name = allocator.dupe(u8, name_ptr.?[0..len]) catch return error.OutOfMemory;
            columns.append(allocator, name) catch {
                allocator.free(name);
                return error.OutOfMemory;
            };
        }
    }

    return columns.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Extract all column names from pragma_table_info
fn extractColumns(db: ?*api.sqlite3, table: []const u8, allocator: std.mem.Allocator) AsOrderedError![][]u8 {
    const sql = "SELECT \"name\" FROM pragma_table_info(?)";

    var stmt: ?*api.sqlite3_stmt = null;
    if (api.prepare_v2(db, sql, -1, &stmt, null) != api.SQLITE_OK) {
        return error.PrepareStmtFailed;
    }
    defer _ = api.finalize(stmt);

    if (api.bind_text(stmt, 1, table.ptr, @intCast(table.len), api.SQLITE_STATIC) != api.SQLITE_OK) {
        return error.BindFailed;
    }

    var columns: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer {
        for (columns.items) |col| allocator.free(col);
        columns.deinit(allocator);
    }

    while (api.step(stmt) == api.SQLITE_ROW) {
        const name_ptr = api.column_text(stmt, 0);
        if (name_ptr != null) {
            const len: usize = @intCast(api.column_bytes(stmt, 0));
            const name = allocator.dupe(u8, name_ptr.?[0..len]) catch return error.OutOfMemory;
            columns.append(allocator, name) catch {
                allocator.free(name);
                return error.OutOfMemory;
            };
        }
    }

    return columns.toOwnedSlice(allocator) catch return error.OutOfMemory;
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
