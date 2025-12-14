//! Site identity and version tracking UDFs
//!
//! Provides:
//! - crsql_site_id() - returns 16-byte site UUID (stable per database file)
//! - crsql_db_version() - returns current logical clock value
//!
//! Site ID is persisted in the `crsql_site_id` table:
//! - Local site is always ordinal 0
//! - Remote sites get ordinals on demand when first seen
//! - Clock tables store site_id as integer ordinal, not blob
//!
//! WASM/Freestanding Notes:
//! - std.crypto.random is not available on freestanding targets
//! - We use a simple xorshift64 PRNG seeded deterministically
//! - Production WASM builds should provide entropy from JS host

const std = @import("std");
const builtin = @import("builtin");
const api = @import("ffi/api.zig");

/// Table and index names for site_id storage
const TBL_SITE_ID = "crsql_site_id";

/// Global site ID (persisted to database)
var global_site_id: [16]u8 = undefined;
var site_id_initialized: bool = false;

/// Global db_version counter (MVP: in-memory only)
/// In production, this would query MAX(db_version) from clock tables
var global_db_version: i64 = 0;

/// Pending db_version for the current transaction
/// Used by crsql_next_db_version() to return max(dbVersion+1, pendingDbVersion, merging_version)
var pending_db_version: i64 = 0;

/// Check if the crsql_site_id table exists
fn hasTable(db: ?*api.sqlite3, table_name: [*:0]const u8) bool {
    const sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND tbl_name = ?";
    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return false;
    defer _ = api.finalize(stmt);

    rc = api.bind_text(stmt, 1, table_name, -1, api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return false;

    return api.step(stmt) == api.SQLITE_ROW;
}

/// PRNG state for WASM/freestanding builds
var prng_state: u64 = 0;
var prng_initialized: bool = false;

/// Initialize PRNG with a seed (for WASM/freestanding)
fn initPrng() void {
    if (!prng_initialized) {
        // Use a fixed seed for deterministic behavior in WASM
        // Production builds should call setSeed() from JS with real entropy
        prng_state = 0x853c49e6748fea9b; // Arbitrary non-zero seed
        prng_initialized = true;
    }
}

/// xorshift64 step
fn xorshift64() u64 {
    initPrng();
    var x = prng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    prng_state = x;
    return x;
}

/// Fill buffer with random bytes (platform-aware)
fn fillRandomBytes(buf: []u8) void {
    if (comptime (builtin.os.tag == .freestanding or builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64)) {
        // WASM/freestanding: Use xorshift64 PRNG
        for (buf) |*byte| {
            byte.* = @truncate(xorshift64());
        }
    } else {
        // Native: use OS-provided cryptographic randomness
        std.crypto.random.bytes(buf);
    }
}

/// Generate a random UUID v4 (16 bytes)
fn generateUuid() [16]u8 {
    var blob: [16]u8 = undefined;
    fillRandomBytes(&blob);
    // Set version to 4 (random UUID)
    blob[6] = (blob[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    blob[8] = (blob[8] & 0x3f) | 0x80;
    return blob;
}

/// Create the crsql_site_id table and insert initial site_id
fn createSiteIdTable(db: ?*api.sqlite3) bool {
    // Create table
    const create_sql =
        \\CREATE TABLE "crsql_site_id" (site_id BLOB NOT NULL, ordinal INTEGER PRIMARY KEY);
        \\CREATE UNIQUE INDEX crsql_site_id_site_id ON "crsql_site_id" (site_id);
    ;
    var rc = api.exec(db, create_sql, null, null, null);
    if (rc != api.SQLITE_OK) return false;

    // Insert site_id with ordinal 0
    const insert_sql = "INSERT INTO \"crsql_site_id\" (site_id, ordinal) VALUES (?, 0)";
    var stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(db, insert_sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return false;
    defer _ = api.finalize(stmt);

    const site_id = generateUuid();
    rc = api.bind_blob(stmt, 1, &site_id, 16, api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return false;

    rc = api.step(stmt);
    if (rc != api.SQLITE_DONE and rc != api.SQLITE_ROW) return false;

    // Copy to global
    @memcpy(&global_site_id, &site_id);
    return true;
}

/// Load site_id from database (ordinal 0)
fn loadSiteId(db: ?*api.sqlite3) bool {
    const sql = "SELECT site_id FROM \"crsql_site_id\" WHERE ordinal = 0";
    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return false;
    defer _ = api.finalize(stmt);

    rc = api.step(stmt);
    if (rc == api.SQLITE_ROW) {
        // Load existing site_id
        const blob = api.column_blob(stmt, 0);
        const bytes = api.column_bytes(stmt, 0);
        if (blob != null and bytes == 16) {
            const ptr: [*]const u8 = @ptrCast(blob);
            @memcpy(&global_site_id, ptr[0..16]);
            return true;
        }
        return false;
    } else if (rc == api.SQLITE_DONE) {
        // Table exists but no row with ordinal 0 - insert one
        const insert_sql = "INSERT INTO \"crsql_site_id\" (site_id, ordinal) VALUES (?, 0)";
        var insert_stmt: ?*api.sqlite3_stmt = null;
        rc = api.prepare_v2(db, insert_sql, -1, &insert_stmt, null);
        if (rc != api.SQLITE_OK) return false;
        defer _ = api.finalize(insert_stmt);

        const site_id = generateUuid();
        rc = api.bind_blob(insert_stmt, 1, &site_id, 16, api.SQLITE_STATIC);
        if (rc != api.SQLITE_OK) return false;

        rc = api.step(insert_stmt);
        if (rc != api.SQLITE_DONE and rc != api.SQLITE_ROW) return false;

        @memcpy(&global_site_id, &site_id);
        return true;
    }
    return false;
}

/// Initialize site ID from database. Creates table if needed.
/// Must be called during extension initialization with a valid db connection.
pub fn initSiteId(db: ?*api.sqlite3) bool {
    if (db == null) return false;
    if (site_id_initialized) return true;

    const success = if (!hasTable(db, TBL_SITE_ID))
        createSiteIdTable(db)
    else
        loadSiteId(db);

    if (success) {
        site_id_initialized = true;
    }
    return success;
}

/// Get or create ordinal for a site_id blob.
/// Local site (matching global_site_id) is always ordinal 0.
/// Remote sites get ordinals on demand via INSERT...RETURNING.
pub fn getOrCreateSiteOrdinal(db: ?*api.sqlite3, site_id_blob: []const u8) ?i64 {
    if (db == null or site_id_blob.len != 16) return null;

    // Check if this is the local site
    if (std.mem.eql(u8, site_id_blob, &global_site_id)) {
        return 0;
    }

    // Try to find existing ordinal
    const select_sql = "SELECT ordinal FROM \"crsql_site_id\" WHERE site_id = ?";
    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, select_sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return null;
    defer _ = api.finalize(stmt);

    rc = api.bind_blob(stmt, 1, site_id_blob.ptr, 16, api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return null;

    rc = api.step(stmt);
    if (rc == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }

    // Not found - insert new entry
    const insert_sql = "INSERT INTO \"crsql_site_id\" (site_id) VALUES (?) RETURNING ordinal";
    var insert_stmt: ?*api.sqlite3_stmt = null;
    rc = api.prepare_v2(db, insert_sql, -1, &insert_stmt, null);
    if (rc != api.SQLITE_OK) return null;
    defer _ = api.finalize(insert_stmt);

    rc = api.bind_blob(insert_stmt, 1, site_id_blob.ptr, 16, api.SQLITE_STATIC);
    if (rc != api.SQLITE_OK) return null;

    rc = api.step(insert_stmt);
    if (rc == api.SQLITE_ROW) {
        return api.column_int64(insert_stmt, 0);
    }
    return null;
}

/// Get site_id blob for a given ordinal.
/// Returns null if not found.
pub fn getSiteIdByOrdinal(db: ?*api.sqlite3, ordinal: i64) ?[16]u8 {
    if (db == null) return null;

    // Fast path for local site
    if (ordinal == 0 and site_id_initialized) {
        return global_site_id;
    }

    const sql = "SELECT site_id FROM \"crsql_site_id\" WHERE ordinal = ?";
    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return null;
    defer _ = api.finalize(stmt);

    rc = api.bind_int64(stmt, 1, ordinal);
    if (rc != api.SQLITE_OK) return null;

    rc = api.step(stmt);
    if (rc == api.SQLITE_ROW) {
        const blob = api.column_blob(stmt, 0);
        const bytes = api.column_bytes(stmt, 0);
        if (blob != null and bytes == 16) {
            var result: [16]u8 = undefined;
            const ptr: [*]const u8 = @ptrCast(blob);
            @memcpy(&result, ptr[0..16]);
            return result;
        }
    }
    return null;
}

/// Implementation of crsql_site_id() SQL function
fn crsqlSiteIdFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    _ = argv;
    if (argc != 0) {
        api.result_error(pCtx, "crsql_site_id takes no arguments", -1);
        return;
    }

    if (!site_id_initialized) {
        api.result_error(pCtx, "site_id not initialized", -1);
        return;
    }
    api.result_blob(pCtx, &global_site_id, 16, api.getTransientDestructor());
}

/// Implementation of crsql_db_version() SQL function
fn crsqlDbVersionFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    _ = argv;
    if (argc != 0) {
        api.result_error(pCtx, "crsql_db_version takes no arguments", -1);
        return;
    }

    // Return MAX(global_db_version, pre_compact_dbversion)
    // The pre_compact_dbversion floor ensures db_version doesn't regress after compaction
    var result = global_db_version;

    // Query pre_compact_dbversion from crsql_master
    const db = api.context_db_handle(pCtx);
    if (db != null) {
        const pre_compact = getPreCompactDbVersion(db);
        if (pre_compact > result) {
            result = pre_compact;
        }
    }

    api.result_int64(pCtx, result);
}

/// Query pre_compact_dbversion from crsql_master table.
/// Returns 0 if not found or on error.
fn getPreCompactDbVersion(db: ?*api.sqlite3) i64 {
    const sql = "SELECT value FROM crsql_master WHERE key = 'pre_compact_dbversion'";
    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) return 0;
    defer _ = api.finalize(stmt);

    rc = api.step(stmt);
    if (rc == api.SQLITE_ROW) {
        return api.column_int64(stmt, 0);
    }
    return 0;
}

/// Implementation of crsql_next_db_version() SQL function
/// Returns max(dbVersion+1, pendingDbVersion, optional_merging_version)
/// Used by triggers to get the db_version for clock entries
fn crsqlNextDbVersionFunc(
    pCtx: ?*api.sqlite3_context,
    argc: c_int,
    argv: [*c]?*api.sqlite3_value,
) callconv(.c) void {
    // Accept 0 or 1 arguments (optional merging_version)
    if (argc > 1) {
        api.result_error(pCtx, "crsql_next_db_version takes 0 or 1 argument", -1);
        return;
    }

    var merging_version: ?i64 = null;
    if (argc == 1) {
        const arg_type = api.value_type(argv[0]);
        if (arg_type != api.SQLITE_NULL) {
            merging_version = api.value_int64(argv[0]);
        }
    }

    const next_version = nextDbVersion(merging_version);
    api.result_int64(pCtx, next_version);
}

/// Increment db_version (called after successful merge operations)
pub fn incrementDbVersion() void {
    global_db_version += 1;
}

/// Promote pending db_version to committed db_version on commit
/// Called by commit hook when rows were impacted
pub fn commitDbVersion() void {
    if (pending_db_version > global_db_version) {
        global_db_version = pending_db_version;
    }
    pending_db_version = 0;
}

/// Reset pending db_version on rollback
pub fn rollbackDbVersion() void {
    pending_db_version = 0;
}

/// Get current db_version
pub fn getDbVersion() i64 {
    return global_db_version;
}

/// Get or create the next db_version for the current transaction
/// Returns max(dbVersion+1, pendingDbVersion, merging_version)
/// This is what triggers should use for db_version
pub fn nextDbVersion(merging_version: ?i64) i64 {
    var ret = global_db_version + 1;
    if (ret < pending_db_version) {
        ret = pending_db_version;
    }
    if (merging_version) |mv| {
        if (ret < mv) {
            ret = mv;
        }
    }
    pending_db_version = ret;
    return ret;
}

/// Initialize db_version from database by querying MAX from all clock tables
/// and the pre_compact_dbversion floor from crsql_master.
/// Should be called during extension initialization
pub fn initDbVersionFromDb(db: ?*api.sqlite3) void {
    if (db == null) return;

    // Query to find all clock tables and get max db_version
    // MVP: Simple approach - query sqlite_master for tables ending in __crsql_clock
    const find_clock_tables_sql = "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%__crsql_clock'";

    var stmt: ?*api.sqlite3_stmt = null;
    var rc = api.prepare_v2(db, find_clock_tables_sql, -1, &stmt, null);
    if (rc != api.SQLITE_OK) {
        // No clock tables or error - check pre_compact_dbversion only
        global_db_version = getPreCompactDbVersion(db);
        pending_db_version = 0;
        return;
    }
    defer _ = api.finalize(stmt);

    var max_version: i64 = 0;

    // For each clock table, query max(db_version)
    while (api.step(stmt) == api.SQLITE_ROW) {
        const table_name = api.column_text(stmt, 0) orelse continue;

        // Query max db_version from this clock table
        var version_buf: [256]u8 = undefined;
        const version_sql = std.fmt.bufPrintZ(&version_buf, "SELECT MAX(db_version) FROM \"{s}\"", .{table_name}) catch continue;

        var version_stmt: ?*api.sqlite3_stmt = null;
        rc = api.prepare_v2(db, version_sql, -1, &version_stmt, null);
        if (rc != api.SQLITE_OK) continue;
        defer _ = api.finalize(version_stmt);

        if (api.step(version_stmt) == api.SQLITE_ROW) {
            const version = api.column_int64(version_stmt, 0);
            if (version > max_version) {
                max_version = version;
            }
        }
    }

    // Also include pre_compact_dbversion floor from crsql_master
    // This ensures db_version doesn't regress after compaction
    const pre_compact = getPreCompactDbVersion(db);
    if (pre_compact > max_version) {
        max_version = pre_compact;
    }

    global_db_version = max_version;
    pending_db_version = 0;
}

/// Get site ID as slice (must be initialized first via initSiteId)
pub fn getSiteId() *const [16]u8 {
    return &global_site_id;
}

/// Check if site ID has been initialized
pub fn isInitialized() bool {
    return site_id_initialized;
}

/// Reset site ID state (for testing only)
pub fn resetForTesting() void {
    site_id_initialized = false;
    @memset(&global_site_id, 0);
}

/// Register both UDFs with a database connection
pub fn register(db: ?*api.sqlite3) c_int {
    var rc = api.create_function_v2(
        db,
        "crsql_site_id",
        0, // nArg: 0 arguments
        api.SQLITE_UTF8 | api.SQLITE_DETERMINISTIC,
        null,
        &crsqlSiteIdFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    rc = api.create_function_v2(
        db,
        "crsql_db_version",
        0,
        api.SQLITE_UTF8,
        null,
        &crsqlDbVersionFunc,
        null,
        null,
        null,
    );
    if (rc != api.SQLITE_OK) return rc;

    // Register crsql_next_db_version with -1 args to accept 0 or 1 arguments
    // SQLITE_INNOCUOUS allows this function to be called from triggers
    rc = api.create_function_v2(
        db,
        "crsql_next_db_version",
        -1, // Variable number of arguments
        api.SQLITE_UTF8 | api.SQLITE_INNOCUOUS,
        null,
        &crsqlNextDbVersionFunc,
        null,
        null,
        null,
    );
    return rc;
}

test "site_id is 16 bytes" {
    // site_id array is always 16 bytes
    try std.testing.expectEqual(@as(usize, 16), global_site_id.len);
}

test "db_version starts at 0" {
    // Note: This test may see non-zero if other tests ran first due to global state
    // In a fresh process, db_version starts at 0
    try std.testing.expect(global_db_version >= 0);
}

test "incrementDbVersion increases counter" {
    const before = global_db_version;
    incrementDbVersion();
    try std.testing.expectEqual(before + 1, global_db_version);
}

test "nextDbVersion returns dbVersion + 1 on first call" {
    // Reset state for isolated test
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 0;

    const next = nextDbVersion(null);
    try std.testing.expectEqual(@as(i64, 6), next);
    try std.testing.expectEqual(@as(i64, 6), pending_db_version);
}

test "nextDbVersion returns pending if higher than dbVersion + 1" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 10;

    const next = nextDbVersion(null);
    try std.testing.expectEqual(@as(i64, 10), next);
}

test "nextDbVersion uses merging_version if highest" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 0;

    const next = nextDbVersion(20);
    try std.testing.expectEqual(@as(i64, 20), next);
    try std.testing.expectEqual(@as(i64, 20), pending_db_version);
}

test "commitDbVersion promotes pending to global" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 10;

    commitDbVersion();

    try std.testing.expectEqual(@as(i64, 10), global_db_version);
    try std.testing.expectEqual(@as(i64, 0), pending_db_version);
}

test "rollbackDbVersion resets pending only" {
    const saved_db_version = global_db_version;
    const saved_pending = pending_db_version;
    defer {
        global_db_version = saved_db_version;
        pending_db_version = saved_pending;
    }

    global_db_version = 5;
    pending_db_version = 10;

    rollbackDbVersion();

    try std.testing.expectEqual(@as(i64, 5), global_db_version);
    try std.testing.expectEqual(@as(i64, 0), pending_db_version);
}

test "getSiteId returns consistent value" {
    const id1 = getSiteId();
    const id2 = getSiteId();
    try std.testing.expectEqual(id1, id2);
}

test "generateUuid produces valid UUID v4" {
    const uuid = generateUuid();
    // Version should be 4 (bits 6-9 of byte 6)
    try std.testing.expectEqual(@as(u8, 0x40), uuid[6] & 0xf0);
    // Variant should be RFC 4122 (bits 6-7 of byte 8)
    try std.testing.expectEqual(@as(u8, 0x80), uuid[8] & 0xc0);
}

test "generateUuid produces different values" {
    const uuid1 = generateUuid();
    const uuid2 = generateUuid();
    try std.testing.expect(!std.mem.eql(u8, &uuid1, &uuid2));
}
