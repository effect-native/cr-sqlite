# TASK-058: Ensure All Zig Functionality is Fully Implemented

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Feature matrix: `research/zig-cr/90-feature-matrix.md`
- MVP roadmap: `research/zig-cr/91-mvp-roadmap.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Phased execution proposal: `research/zig-cr/93-phased-execution-proposal.md`
- Zig implementation: `zig/`
- Core C implementation (reference): `core/`

## Description
Systematically verify that all cr-sqlite functionality documented in the feature matrix and research docs is fully implemented in the Zig port. This includes:

1. All core replication surfaces (init, as_crr/as_table, write capture, crsql_changes vtab, merge semantics)
2. Serialization and wire formats (PK blob format, pack_columns)
3. All SQLite extension APIs (UDFs, writable virtual tables, hooks, triggers)
4. Clock versioning and ordering semantics
5. Fractindex support (currently stubbed: crsql_fract_as_ordered)
6. Any other functionality identified in the feature matrix

Cross-reference the Zig implementation against the C/Rust reference implementation to identify any missing or incomplete features.

## Files to Modify
- `zig/src/` (implement missing functionality)
- `research/zig-cr/90-feature-matrix.md` (update status)
- `research/zig-cr/92-gap-backlog.md` (update completion status)

## Acceptance Criteria
- [ ] Complete audit of all features in `research/zig-cr/90-feature-matrix.md` against Zig implementation
- [ ] Identify all missing or incomplete features
- [ ] Implement missing functionality or create separate task cards for complex features
- [ ] All core replication features are fully functional
- [ ] All C oracle tests pass (including fract suite if implemented)
- [ ] Documentation updated to reflect implementation status
- [ ] Completion notes include a comprehensive list of what was implemented or deferred

## Progress Log
### 2025-12-17
- Task created to ensure Zig parity with C/Rust implementation
- Known gap: crsql_fract_as_ordered is currently a stub (causes 1/20 C oracle tests to fail)
- Reference: Round 20 notes indicate 153/154 tests passing (99.4%)

## Completion Notes
[fill in when done]
