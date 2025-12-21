# TASK-153 — Sweep codebase for remaining base_rowid / pks blob references

## Goal
Systematically search and eliminate all remaining references to the old pks schema (`base_rowid` column, `pks BLOB` column) throughout the Zig codebase.

## Status
- State: triage
- Priority: medium (cleanup after main refactoring)

## Context
After completing TASK-149, TASK-150, and TASK-152, there may be residual references to the old schema scattered across:
- Comments and documentation
- Error messages and debug logging
- Dead code paths
- Test fixtures and helper functions
- SQL string literals in other modules

Known locations already refactored:
- `zig/src/merge_insert.zig` - refactored in TASK-149, 150, 152
- `zig/src/local_writes/after_write.zig` - uses new schema (getOrCreatePkKey)
- `zig/src/as_crr.zig` - creates new schema tables

Potential places with residual references:
- `zig/src/changes_vtab.zig` - may have comments or old code
- `zig/test/` - test helpers might reference old schema
- `zig/harness/` - test scripts might have stale SQL
- Error messages in merge_insert.zig mentioning "base_rowid" or "pks"

## Files to Modify
(To be determined by grep sweep; keep tight scope)
- Candidates: Any `.zig`, `.sh`, `.md` files with schema references
- Likely: `zig/src/changes_vtab.zig`, test files, harness scripts

## Acceptance Criteria
1. Code sweep (mandatory):
   ```bash
   cd zig
   grep -r "base_rowid" src/ test/ --include="*.zig" | grep -v ".swp"
   grep -r "pks BLOB" src/ test/ --include="*.zig" | grep -v ".swp"
   grep -r 'pks = ?' src/ test/ --include="*.zig" | grep -v ".swp"
   # All hits must be:
   # - False positives (e.g., "purpose_rowid" not "base_rowid")
   # - Historical comments explicitly marked OLD SCHEMA
   # - Or removed/refactored
   ```

2. Comment audit:
   - Any comment referencing old schema must be labeled `OLD SCHEMA (pre-TASK-147):`
   - Or replaced with accurate new schema description

3. Test fixture update:
   - If any test helper creates manual pks entries, update to new schema
   - Test data generators use new column structure

4. Error message clarity:
   - Any error mentioning "pks" should reference "__crsql_pks table" or "PK columns"
   - No references to "base_rowid lookup" in production error paths

5. Documentation sweep:
   - Check `zig/src/merge_insert.zig` top-level comments
   - Check `research/zig-cr/*.md` files for stale schema diagrams
   - Update or mark obsolete

## Parent Docs / Cross-links
- Parent: TASK-147 (Rust/C pks schema migration)
- Depends on: TASK-149, TASK-150, TASK-152 (main refactoring complete)
- Related: `.tasks/done/TASK-119` (had similar base_rowid confusion)
- Upstream: `research/zig-cr/04-schema-and-metadata.md` (may need updates)

## Progress Log
- 2025-12-21: Created from TASK-147 work. Cleanup task to ensure no stale references remain after major refactoring.

## Completion Notes
(Empty until done.)
