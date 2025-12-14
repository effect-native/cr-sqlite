//! Merge semantics test oracle
//!
//! Defines the conflict resolution rules via concrete test cases extracted from
//! the C test suite and Python correctness tests.
//!
//! CR-SQLite merge semantics follow a hierarchical winner selection:
//! 1. Higher `cl` (causal length) wins unconditionally
//! 2. If `cl` tied, higher `col_version` wins
//! 3. If `col_version` tied, deterministic value comparison (larger wins)
//! 4. Optionally, site-id byte-wise comparison when `mergeEqualValues` is enabled
//!
//! Special semantics:
//! - Delete is indicated by even `cl` (cl % 2 == 0)
//! - Resurrection is indicated by odd `cl` > local even `cl`
//! - Tombstone sentinel: cid = "-1", value = NULL
//! - On resurrection, non-sentinel column clocks are zeroed

const std = @import("std");

/// Represents a single change record as it appears in crsql_changes virtual table.
/// This is the wire format for syncing changes between nodes.
pub const ChangeRecord = struct {
    /// Table name
    table: []const u8,
    /// Packed primary key blob (using crsql_pack_columns format)
    /// Format: type_tag (1 byte) + length prefix (varint) + value bytes
    pk: []const u8,
    /// Column name, or "-1" for insert/delete sentinel
    col_name: []const u8,
    /// Column version - increments on each local change to this column
    col_version: i64,
    /// Database version - logical timestamp for ordering changes
    db_version: i64,
    /// Site ID - 16-byte UUID identifying the originating node (empty for local)
    site_id: []const u8,
    /// Causal length - tracks create/delete cycles
    /// - odd cl = row exists (1=created, 3=resurrected after delete, etc)
    /// - even cl = row deleted (2=first delete, 4=second delete, etc)
    cl: i64,
    /// Column value (NULL represented as empty slice for tombstones)
    value: ?[]const u8,
};

/// Expected outcome of a merge operation
pub const MergeOutcome = enum {
    /// Local state wins - remote change is ignored
    local,
    /// Remote state wins - local state is updated
    remote,
};

/// A test case defining two competing changes and the expected winner
pub const MergeTestCase = struct {
    /// Human-readable test name
    name: []const u8,
    /// Source file and line number where this behavior is tested
    source: []const u8,
    /// Detailed description of the scenario
    description: []const u8,
    /// The local state (what the receiving node has)
    local: ChangeRecord,
    /// The remote change being merged in
    remote: ChangeRecord,
    /// Which side wins the merge
    expected_winner: MergeOutcome,
    /// Explanation of why this winner was chosen
    reason: []const u8,
};

/// Placeholder site IDs for test cases
const SITE_A: []const u8 = &[_]u8{ 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA };
const SITE_B: []const u8 = &[_]u8{ 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB };

/// Packed PK for integer value 1: type=integer(0x09), varint length, value
const PK_1: []const u8 = &[_]u8{ 0x01, 0x09, 0x01 };

/// Insert/delete sentinel column name
const SENTINEL: []const u8 = "-1";

/// All test cases defining merge semantics
pub const test_cases = [_]MergeTestCase{
    // =========================================================================
    // Rule 1: Higher causal length (cl) wins unconditionally
    // =========================================================================
    .{
        .name = "higher_cl_wins_over_higher_col_version",
        .source = "test_cl_merging.py:test_larger_cl_wins_all",
        .description =
        \\Remote has cl=3 (resurrected) with col_version=1.
        \\Local has cl=1 with col_version=3 (multiple updates).
        \\Remote wins because cl=3 > cl=1, despite lower col_version.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 3, // higher col_version
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1, // lower causal length
            .value = "4",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1, // lower col_version
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 3, // higher causal length (resurrected)
            .value = "1",
        },
        .expected_winner = .remote,
        .reason = "cl dominates: remote cl=3 > local cl=1",
    },

    .{
        .name = "lower_cl_loses_all",
        .source = "test_cl_merging.py:test_smaller_cl_loses_all",
        .description =
        \\Remote has cl=1 with high col_version and value.
        \\Local has cl=3 (resurrected).
        \\Local wins because cl=3 > cl=1.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 3, // higher causal length
            .value = "1",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 2, // higher col_version
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 1, // lower causal length
            .value = "123",
        },
        .expected_winner = .local,
        .reason = "cl dominates: local cl=3 > remote cl=1",
    },

    // =========================================================================
    // Rule 2: Delete handling (even cl indicates deletion)
    // =========================================================================
    .{
        .name = "higher_cl_delete_wins",
        .source = "test_cl_merging.py:test_larger_cl_delete_deletes_all",
        .description =
        \\Remote has cl=2 (deleted).
        \\Local has cl=1 with data.
        \\Remote wins - row gets deleted.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 3,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1, // alive
            .value = "4",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = SENTINEL,
            .col_version = 2,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 2, // deleted (even)
            .value = null,
        },
        .expected_winner = .remote,
        .reason = "cl dominates: remote cl=2 > local cl=1; delete wins",
    },

    .{
        .name = "smaller_delete_does_not_win",
        .source = "test_cl_merging.py:test_smaller_delete_does_not_delete_larger_cl",
        .description =
        \\Remote has cl=2 (deleted).
        \\Local has cl=3 (resurrected after delete).
        \\Local wins - row stays alive.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 3, // resurrected
            .value = "1",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = SENTINEL,
            .col_version = 2,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 2, // deleted
            .value = null,
        },
        .expected_winner = .local,
        .reason = "cl dominates: local cl=3 > remote cl=2; resurrection beats older delete",
    },

    .{
        .name = "equivalent_delete_cls_is_noop",
        .source = "test_cl_merging.py:test_equivalent_delete_cls_is_noop",
        .description =
        \\Both sides have cl=2 (both deleted).
        \\Equal delete CLs result in no-op.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = SENTINEL,
            .col_version = 2,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 2,
            .value = null,
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = SENTINEL,
            .col_version = 2,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 2,
            .value = null,
        },
        .expected_winner = .local, // no-op, local state unchanged
        .reason = "equal delete cl is a no-op; local state preserved",
    },

    // =========================================================================
    // Rule 3: Resurrection (odd cl > even cl)
    // =========================================================================
    .{
        .name = "resurrection_wins_over_delete",
        .source = "test_cl_merging.py:test_resurrection_of_dead_thing_via_sentinel",
        .description =
        \\Local is deleted (cl=2).
        \\Remote is resurrected (cl=3).
        \\Remote wins - row comes back.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = SENTINEL,
            .col_version = 2,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 2, // deleted
            .value = null,
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = SENTINEL,
            .col_version = 3,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 3, // resurrected
            .value = null,
        },
        .expected_winner = .remote,
        .reason = "cl dominates: remote cl=3 > local cl=2; resurrection wins",
    },

    // =========================================================================
    // Rule 4: Same cl - col_version tie-break
    // =========================================================================
    .{
        .name = "higher_col_version_wins_when_cl_tied",
        .source = "test_cl_merging.py:test_larger_col_version_same_cl",
        .description =
        \\Both have cl=1.
        \\Remote has col_version=2, local has col_version=1.
        \\Remote wins on col_version.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1, // lower
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1,
            .value = "1",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 2, // higher
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 1,
            .value = "0",
        },
        .expected_winner = .remote,
        .reason = "col_version tie-break: remote col_version=2 > local col_version=1",
    },

    .{
        .name = "lower_col_version_loses_when_cl_tied",
        .source = "rows-impacted.test.c:testUpdateThatDoesNotChangeAnything:214",
        .description =
        \\Both have cl=1.
        \\Remote has col_version=0, local has col_version=1.
        \\Local wins on col_version.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1, // higher (from initial insert)
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1,
            .value = "2",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 0, // lower
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 1,
            .value = "2",
        },
        .expected_winner = .local,
        .reason = "col_version tie-break: local col_version=1 > remote col_version=0",
    },

    // =========================================================================
    // Rule 5: Same cl and col_version - value comparison
    // =========================================================================
    .{
        .name = "higher_value_wins_when_versions_tied",
        .source = "test_cl_merging.py:test_larger_col_value_same_cl_and_col_version",
        .description =
        \\Both have cl=1 and col_version=1.
        \\Remote value=4, local value=1.
        \\Remote wins because 4 > 1 in value comparison.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1,
            .value = "1", // lower value
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 1,
            .value = "4", // higher value
        },
        .expected_winner = .remote,
        .reason = "value comparison: remote value 4 > local value 1",
    },

    .{
        .name = "value_win_recorded_as_change",
        .source = "rows-impacted.test.c:testValueWin:317",
        .description =
        \\Local has value=2, remote has value=3.
        \\Same cl and col_version.
        \\Remote wins and change is recorded.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1,
            .value = "2",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = &[_]u8{0} ** 16, // zeroed site ID from test
            .cl = 1,
            .value = "3",
        },
        .expected_winner = .remote,
        .reason = "value comparison: remote value 3 > local value 2",
    },

    // =========================================================================
    // Additional edge cases
    // =========================================================================
    .{
        .name = "clock_win_higher_db_version",
        .source = "rows-impacted.test.c:testClockWin:342",
        .description =
        \\Remote has higher col_version (db_version=2, col_version=2).
        \\This represents a "clock win" scenario.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1,
            .value = "2",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 2,
            .db_version = 2,
            .site_id = SITE_B,
            .cl = 1,
            .value = "2", // same value but higher version
        },
        .expected_winner = .remote,
        .reason = "col_version tie-break: remote col_version=2 > local col_version=1",
    },

    .{
        .name = "no_row_locally_remote_wins",
        .source = "changes_vtab_write.rs:did_cid_win:65",
        .description =
        \\No local row exists (col_version query returns no rows).
        \\Remote change wins by default.
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 0, // represents "no local data"
            .db_version = 0,
            .site_id = &[_]u8{},
            .cl = 0, // no local CL
            .value = null,
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 1,
            .value = "42",
        },
        .expected_winner = .remote,
        .reason = "no local row exists; remote wins by default",
    },

    .{
        .name = "same_value_same_versions_local_wins",
        .source = "rows-impacted.test.c:testUpdateThatDoesNotChangeAnything:196",
        .description =
        \\Exact same cl, col_version, and value.
        \\Local wins (no-op merge).
        ,
        .local = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_A,
            .cl = 1,
            .value = "2",
        },
        .remote = .{
            .table = "foo",
            .pk = PK_1,
            .col_name = "b",
            .col_version = 1,
            .db_version = 1,
            .site_id = SITE_B,
            .cl = 1,
            .value = "2", // identical value
        },
        .expected_winner = .local,
        .reason = "identical values; local wins (no-op, unless mergeEqualValues enabled)",
    },
};

/// Value comparison function matching CR-SQLite semantics.
/// Returns negative if a < b, 0 if equal, positive if a > b.
/// Type ordering (from compare_values.rs): NULL < INTEGER < FLOAT < TEXT < BLOB
pub fn compareValues(a: ?[]const u8, b: ?[]const u8) i32 {
    // NULL handling: NULL is less than all non-NULL values
    if (a == null and b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    // For non-null values, compare lexicographically
    // In actual implementation, type tags would be compared first
    const a_val = a.?;
    const b_val = b.?;

    return switch (std.mem.order(u8, a_val, b_val)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

/// Determines the winner of a merge based on CR-SQLite semantics.
/// This is a reference implementation for testing purposes.
pub fn determineMergeWinner(local: ChangeRecord, remote: ChangeRecord) MergeOutcome {
    // Rule 1: Higher causal length wins unconditionally
    if (remote.cl > local.cl) return .remote;
    if (remote.cl < local.cl) return .local;

    // CL is equal from here on

    // Special case: equal delete CLs are no-ops
    if (@rem(remote.cl, 2) == 0 and @rem(local.cl, 2) == 0) {
        return .local; // no-op
    }

    // Rule 2: Higher col_version wins
    if (remote.col_version > local.col_version) return .remote;
    if (remote.col_version < local.col_version) return .local;

    // Rule 3: Value comparison (larger wins)
    const cmp = compareValues(remote.value, local.value);
    if (cmp > 0) return .remote;
    if (cmp < 0) return .local;

    // Rule 4: If mergeEqualValues is enabled, site_id comparison would happen here
    // For now, equal values = local wins (no-op)
    return .local;
}

test "merge oracle test cases validate correctly" {
    for (test_cases) |tc| {
        const actual = determineMergeWinner(tc.local, tc.remote);
        if (actual != tc.expected_winner) {
            std.debug.print(
                \\
                \\FAILED: {s}
                \\  Source: {s}
                \\  Expected: {s}, Got: {s}
                \\  Reason: {s}
                \\
            , .{
                tc.name,
                tc.source,
                @tagName(tc.expected_winner),
                @tagName(actual),
                tc.reason,
            });
            return error.TestFailed;
        }
    }
}

test "compare_values null handling" {
    try std.testing.expectEqual(@as(i32, 0), compareValues(null, null));
    try std.testing.expectEqual(@as(i32, -1), compareValues(null, "x"));
    try std.testing.expectEqual(@as(i32, 1), compareValues("x", null));
}

test "compare_values ordering" {
    try std.testing.expectEqual(@as(i32, -1), compareValues("1", "4"));
    try std.testing.expectEqual(@as(i32, 0), compareValues("abc", "abc"));
    try std.testing.expectEqual(@as(i32, 1), compareValues("z", "a"));
}
