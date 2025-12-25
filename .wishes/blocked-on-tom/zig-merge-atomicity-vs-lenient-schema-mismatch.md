# Wish: Decide behavior for batch apply when some incoming changes are ignorable

## Context
We recently decided **unknown columns during sync are ignored** (lenient behavior) to support rolling upgrades.

That decision interacts with our existing **merge atomicity** expectations.

Today:
- `zig/harness/test-merge-atomicity.sh` reports **2 failing checks**
- Those failures are caused by using “unknown column” as the error injection mechanism, but unknown columns are now **ignored**, so the batch doesn’t fail and the first row legitimately persists.

## Repro
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-merge-atomicity.sh
```

Failing checks:
- Test 2: “Invalid column in batch causes entire statement to fail”
- Test 7: “Base table integrity after failed batch”

## What’s the actual decision point?
When applying a batch of incoming changes (often shipped in a single SQL statement with multiple VALUES rows):

If some rows are **ignored by policy** (unknown column), do we want:

1) **Apply the valid subset** (current behavior)
   - “best effort apply”
   - matches lenient schema mismatch policy

2) **Fail the statement / rollback entire batch** if *any* row is unapplicable
   - stricter atomicity semantics
   - but conflicts with “ignore unknown columns” unless we special-case

## Recommendation
**Keep applying the valid subset** when the “failure” is an ignorable policy case (unknown column).

Then update `test-merge-atomicity.sh` to inject errors using something that remains a hard error even under lenient schema mismatch, e.g.
- invalid table name
- invalid PK blob / malformed pk encoding
- invalid site_id length (if we decide to add validation)

This maintains a useful atomicity guarantee:
- real errors rollback
- intentionally ignored changes don’t poison the whole batch

## Likely follow-up work (if approved)
- Update `zig/harness/test-merge-atomicity.sh` to align with the chosen policy
- Possibly add a new test that explicitly validates “unknown column rows are ignored but known columns still apply” (this is now part of the contract)

## Cross-links
- Related decision already implemented: `.tasks/done/TASK-186-schema-mismatch-unknown-column-behavior.md`
- Existing spec task: `.tasks/done/TASK-087-spec-merge-atomicity.md`
- Test: `zig/harness/test-merge-atomicity.sh`

## Decision requested from Tom
- Confirm that “unknown columns ignored” implies “best effort apply” within a batch (recommended)
- Or require strict all-or-nothing batch failure semantics even for unknown columns
