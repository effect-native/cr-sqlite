# TASK-200 — Zig Input Validation Gaps (More Permissive Than Rust)

## Goal
Align Zig input validation with Rust/C to ensure identical error handling for malformed inputs.

## Status
- State: triage
- Priority: LOW (Zig is more robust, not less)
- Discovered: 2025-12-23 (TASK-195 adversarial input fuzzing)

## Problem

TASK-195 adversarial testing found that Zig accepts inputs that Rust/C rejects:

| Input | Rust/C | Zig |
|-------|--------|-----|
| Negative col_version | ERROR | ACCEPTS |
| Negative db_version | ERROR | ACCEPTS |
| Non-16-byte site_id | ERROR | ACCEPTS |
| Float for integer field | ERROR | ACCEPTS |
| String for integer field | ERROR | ACCEPTS |
| Non-NULL sentinel value | ERROR | ACCEPTS |

## Context

This is a LOW priority issue because:
1. Zig handles all inputs gracefully (no crashes)
2. Rust/C actually CRASHES on some inputs (empty PK blob, NULL PK blob)
3. Being more permissive is safer than being less robust

However, for strict parity, Zig should reject the same inputs as Rust/C.

## Rust/C Crashes (For Reference)

The adversarial testing found that Rust/C crashes on:
- Empty PK blob (SIGTRAP assertion failure)
- NULL PK blob (SIGTRAP assertion failure)

Zig handles both gracefully with proper error messages.

## Files to Modify

- `zig/src/changes_vtab.zig` — Add validation for:
  - `site_id` length (must be 16 bytes)
  - `col_version` >= 0
  - `db_version` >= 0
  - Type checking for metadata fields

## Acceptance Criteria

1. [ ] Zig rejects negative col_version with same error as Rust
2. [ ] Zig rejects negative db_version with same error as Rust
3. [ ] Zig rejects non-16-byte site_id with same error as Rust
4. [ ] Zig rejects wrong types for metadata fields
5. [ ] All existing tests still pass

## Parent Docs / Cross-links

- Discovery: `.tasks/triage/TASK-195-adversarial-input-fuzzing.md`
- Test script: `zig/harness/test-adversarial-input.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from TASK-195 findings.

## Completion Notes
(Empty until done.)
