# Wish: Decide empty BLOB PK encoding parity (WF-028)

## Context
Our Zig extension currently diverges from the Rust/C oracle for **empty BLOB primary keys** (PK value `X''`) in the **encoded `pk` blob** emitted by `crsql_changes`.

This shows up in the parity suite as:
- `zig/harness/test-pk-blob-parity.sh` → **WF-028 FAIL**

## Repro
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-pk-blob-parity.sh
```

Current observed output:
- Zig: `0105`
- Rust/C: `0104`

## Why this matters
The `pk` encoding is part of the sync wire format. Divergence means:
- Zig↔Rust/C cross-impl sync might mis-address rows for this edge case
- future tooling/tests that assume byte-identical PK encoding will keep failing

## Recommendation
**Fix Zig to match Rust/C**.

Even though empty BLOB PKs are rare, this is an encoding-level contract, and it’s cheap to keep deterministic parity.

## Likely implementation scope (if approved)
- Investigate `zig/src/pack_columns.zig` handling of empty BLOBs
- Compare to `core/rs/core/src/pack_columns.rs` behavior
- Ensure `X''` is distinguished from `NULL` and matches oracle’s tag/length encoding

## Cross-links
- Existing triage task: `.tasks/triage/TASK-203-empty-blob-pk-encoding-divergence.md`
- Test: `zig/harness/test-pk-blob-parity.sh` (WF-028)

## Completion Notes
- 2025-12-26: WF-028 now passes; Zig encodes empty BLOB PK as `0104`.
- Verification: `bash zig/harness/test-pk-blob-parity.sh`
- Fix commit: `5bfeb9ac` (Round 77)
