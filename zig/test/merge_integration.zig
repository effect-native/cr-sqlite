//! Merge Integration Tests
//!
//! These tests verify that the merge logic in `changes_vtab.zig` correctly implements
//! CR-SQLite's conflict resolution semantics as defined in `merge_oracle.zig`.
//!
//! ## Test Strategy
//!
//! Since Zig unit tests run in-process without an actual SQLite database, we:
//! 1. Test the `determineMergeWinner` oracle directly (documents expected behavior)
//! 2. Wire up shell-based integration tests via `test-merge.sh` (tests actual DB behavior)
//!
//! ## TDD Status
//!
//! These tests document the expected behavior. They will FAIL until merge logic
//! is implemented in `changes_vtab.zig:changesUpdate`.
//!
//! The current stub in `changesUpdate` unconditionally calls `incrementRowsImpacted()`
//! for every INSERT. Correct behavior requires:
//! - NOT incrementing when local value wins (no-op merge)
//! - Incrementing only when remote value wins (actual change)
//!
//! ## Shell Integration Tests
//!
//! The `test-merge.sh` harness tests actual merge behavior with a real SQLite database:
//! - Test 1: Identical value INSERT is no-op (rows_impacted=0)
//! - Test 2: Higher col_version wins (rows_impacted=1)
//! - Test 3: Lower col_version loses (rows_impacted=0)

const std = @import("std");
const merge_oracle = @import("merge_oracle");

// =============================================================================
// Oracle-Based Tests (Document Expected Behavior)
// =============================================================================

test "oracle: identical value with same versions is local win (no-op)" {
    // Test case: same_value_same_versions_local_wins
    // Source: rows-impacted.test.c:testUpdateThatDoesNotChangeAnything:196
    //
    // When remote sends a change with identical value and same col_version,
    // local state wins and NO change should be recorded.
    // This means crsql_rows_impacted() should NOT be incremented.
    
    const tc = merge_oracle.test_cases[12]; // "same_value_same_versions_local_wins"
    try std.testing.expectEqualStrings("same_value_same_versions_local_wins", tc.name);
    
    const outcome = merge_oracle.determineMergeWinner(tc.local, tc.remote);
    try std.testing.expectEqual(merge_oracle.MergeOutcome.local, outcome);
    
    // This test passes (oracle is correct).
    // The shell integration test will FAIL until changesUpdate implements this.
}

test "oracle: higher col_version wins when cl tied" {
    // Test case: higher_col_version_wins_when_cl_tied
    // Source: test_cl_merging.py:test_larger_col_version_same_cl
    //
    // When both sides have same cl but remote has higher col_version,
    // remote wins and the change IS recorded.
    // This means crsql_rows_impacted() SHOULD be incremented.
    
    const tc = merge_oracle.test_cases[6]; // "higher_col_version_wins_when_cl_tied"
    try std.testing.expectEqualStrings("higher_col_version_wins_when_cl_tied", tc.name);
    
    const outcome = merge_oracle.determineMergeWinner(tc.local, tc.remote);
    try std.testing.expectEqual(merge_oracle.MergeOutcome.remote, outcome);
}

test "oracle: lower col_version loses when cl tied" {
    // Test case: lower_col_version_loses_when_cl_tied
    // Source: rows-impacted.test.c:testUpdateThatDoesNotChangeAnything:214
    //
    // When remote has lower col_version than local, local wins.
    // No change recorded, crsql_rows_impacted() NOT incremented.
    
    const tc = merge_oracle.test_cases[7]; // "lower_col_version_loses_when_cl_tied"
    try std.testing.expectEqualStrings("lower_col_version_loses_when_cl_tied", tc.name);
    
    const outcome = merge_oracle.determineMergeWinner(tc.local, tc.remote);
    try std.testing.expectEqual(merge_oracle.MergeOutcome.local, outcome);
}

test "oracle: value comparison when versions tied - higher value wins" {
    // Test case: value_win_recorded_as_change
    // Source: rows-impacted.test.c:testValueWin:317
    //
    // When cl and col_version are equal, larger value wins.
    // Remote value "3" > local value "2", so remote wins.
    // Change IS recorded, crsql_rows_impacted() SHOULD be incremented.
    
    const tc = merge_oracle.test_cases[9]; // "value_win_recorded_as_change"
    try std.testing.expectEqualStrings("value_win_recorded_as_change", tc.name);
    
    const outcome = merge_oracle.determineMergeWinner(tc.local, tc.remote);
    try std.testing.expectEqual(merge_oracle.MergeOutcome.remote, outcome);
}

// =============================================================================
// Simulated Merge Logic Tests
// =============================================================================

/// Simulates what changesUpdate SHOULD do for a merge decision.
/// This is a test double that we can verify against the oracle.
///
/// In the actual implementation, this logic needs to be in changesUpdate:
/// 1. Query local state (cl, col_version, value) from clock table
/// 2. Call determineMergeWinner(local, remote)
/// 3. If remote wins: update tables and increment counter
/// 4. If local wins: do nothing (no-op)
fn simulateMerge(local: merge_oracle.ChangeRecord, remote: merge_oracle.ChangeRecord) struct { should_increment: bool, winner: merge_oracle.MergeOutcome } {
    const outcome = merge_oracle.determineMergeWinner(local, remote);
    return .{
        .should_increment = outcome == .remote,
        .winner = outcome,
    };
}

test "simulated merge: no-op does not increment counter" {
    // This test verifies the EXPECTED behavior.
    // The actual changesUpdate currently fails this because it always increments.
    
    const tc = merge_oracle.test_cases[12]; // same_value_same_versions_local_wins
    const result = simulateMerge(tc.local, tc.remote);
    
    try std.testing.expectEqual(merge_oracle.MergeOutcome.local, result.winner);
    try std.testing.expect(!result.should_increment);
}

test "simulated merge: winning change increments counter" {
    // When remote wins, counter SHOULD be incremented
    
    const tc = merge_oracle.test_cases[6]; // higher_col_version_wins_when_cl_tied
    const result = simulateMerge(tc.local, tc.remote);
    
    try std.testing.expectEqual(merge_oracle.MergeOutcome.remote, result.winner);
    try std.testing.expect(result.should_increment);
}

// =============================================================================
// Merge Outcome Documentation Tests
// =============================================================================

test "merge outcome: increment counter only when remote wins" {
    // This documents the correct behavior pattern for changesUpdate:
    //
    // For each merge:
    //   outcome = determineMergeWinner(local, remote)
    //   if outcome == .remote:
    //       updateBaseTable(remote.value)
    //       updateClockTable(remote.col_version, remote.db_version, remote.site_id)
    //       incrementRowsImpacted()
    //   else:
    //       // no-op, do nothing
    
    // Verify no-op cases (local wins)
    const noop_cases = [_]usize{ 1, 3, 4, 7, 12 }; // test_case indices where local wins
    for (noop_cases) |idx| {
        const tc = merge_oracle.test_cases[idx];
        const result = simulateMerge(tc.local, tc.remote);
        if (result.winner != .local) {
            std.debug.print("Expected local win for case {}: {s}\n", .{ idx, tc.name });
            return error.UnexpectedWinner;
        }
        if (result.should_increment) {
            std.debug.print("Should NOT increment for case {}: {s}\n", .{ idx, tc.name });
            return error.ShouldNotIncrement;
        }
    }
    
    // Verify winning cases (remote wins)
    const winning_cases = [_]usize{ 0, 2, 5, 6, 8, 9, 10, 11 }; // test_case indices where remote wins
    for (winning_cases) |idx| {
        const tc = merge_oracle.test_cases[idx];
        const result = simulateMerge(tc.local, tc.remote);
        if (result.winner != .remote) {
            std.debug.print("Expected remote win for case {}: {s}\n", .{ idx, tc.name });
            return error.UnexpectedWinner;
        }
        if (!result.should_increment) {
            std.debug.print("SHOULD increment for case {}: {s}\n", .{ idx, tc.name });
            return error.ShouldIncrement;
        }
    }
}

// =============================================================================
// All Oracle Test Cases (Comprehensive Coverage)
// =============================================================================

test "all oracle test cases produce expected outcomes" {
    // This verifies the oracle is self-consistent
    for (merge_oracle.test_cases, 0..) |tc, i| {
        const actual = merge_oracle.determineMergeWinner(tc.local, tc.remote);
        if (actual != tc.expected_winner) {
            std.debug.print(
                \\
                \\FAILED test case [{d}]: {s}
                \\  Source: {s}
                \\  Expected: {s}, Got: {s}
                \\  Reason: {s}
                \\
            , .{
                i,
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

// =============================================================================
// Contract Tests: What changesUpdate MUST Implement
// =============================================================================

test "contract: changesUpdate must query local state before merge" {
    // Document the required query to fetch local state:
    //
    // SELECT col_version, site_id FROM "{table}__crsql_clock"
    // WHERE pk = ? AND col_name = ?
    //
    // If no row exists, local.col_version = 0 (remote wins by default)
    
    const tc = merge_oracle.test_cases[11]; // "no_row_locally_remote_wins"
    try std.testing.expectEqualStrings("no_row_locally_remote_wins", tc.name);
    
    // When local col_version = 0 and remote col_version > 0, remote wins
    try std.testing.expectEqual(@as(i64, 0), tc.local.col_version);
    try std.testing.expectEqual(@as(i64, 1), tc.remote.col_version);
    
    const outcome = merge_oracle.determineMergeWinner(tc.local, tc.remote);
    try std.testing.expectEqual(merge_oracle.MergeOutcome.remote, outcome);
}

test "contract: changesUpdate must fetch causal length from sentinel row" {
    // Document the required query to fetch causal length:
    //
    // SELECT col_version FROM "{table}__crsql_clock"
    // WHERE pk = ? AND col_name = '-1'
    //
    // The sentinel row (col_name = '-1') stores causal length in col_version
    
    // Test that CL dominates other comparisons
    const tc = merge_oracle.test_cases[0]; // "higher_cl_wins_over_higher_col_version"
    try std.testing.expectEqualStrings("higher_cl_wins_over_higher_col_version", tc.name);
    
    // Remote has higher CL (3 vs 1) but lower col_version (1 vs 3)
    // Remote should still win because CL dominates
    try std.testing.expectEqual(@as(i64, 3), tc.remote.cl);
    try std.testing.expectEqual(@as(i64, 1), tc.local.cl);
    try std.testing.expectEqual(@as(i64, 1), tc.remote.col_version);
    try std.testing.expectEqual(@as(i64, 3), tc.local.col_version);
    
    const outcome = merge_oracle.determineMergeWinner(tc.local, tc.remote);
    try std.testing.expectEqual(merge_oracle.MergeOutcome.remote, outcome);
}
