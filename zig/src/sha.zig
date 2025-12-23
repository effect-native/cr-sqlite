//! Git SHA reporting function
//!
//! Provides crsql_sha() that returns the git commit hash of the build.
//! This is useful for debugging to identify which version is running.

const std = @import("std");
const api = @import("ffi/api.zig");

/// Build-time git SHA (injected by build.zig or defaults to "unknown")
/// In production, this should be set via build options from `git rev-parse HEAD`
pub const GIT_SHA: [:0]const u8 = "unknown";

/// Implementation of crsql_sha() SQL function
/// Returns the git commit SHA of the build.
fn crsqlShaFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    _ = argv;
    if (argc != 0) {
        api.result_error(pCtx, "crsql_sha takes no arguments", -1);
        return;
    }

    // Return the git SHA as a string
    api.result_text(pCtx, GIT_SHA.ptr, @intCast(GIT_SHA.len), api.SQLITE_STATIC);
}

/// Register crsql_sha() with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    return api.create_function_v2(
        db,
        "crsql_sha",
        0, // nArg: 0 arguments
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC,
        null,
        &crsqlShaFunc,
        null,
        null,
        null,
    );
}

test "GIT_SHA is valid string" {
    try std.testing.expect(GIT_SHA.len > 0);
}
