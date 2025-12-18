# TASK-091: Oracle Parity — Fractional index algorithm

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust fract implementation: `core/rs/fractindex-core/src/fractindex.rs`
- Zig fract implementation: `zig/src/fract_index.zig`
- Existing fract tests: `zig/harness/test-fract.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_fract_key_between(a, b)` produces identical output in both Rust/C and Zig for the same inputs.

This is an **oracle test**: The fractional index algorithm must be deterministic and produce the same lexicographically-sortable string in both implementations.

## Files to Modify
- `zig/harness/test-fract-parity.sh` (new or extend `test-fract.sh`)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Test calls `crsql_fract_key_between(a, b)` with identical inputs on both implementations.
- [x] Test cases include:
  - `(NULL, NULL)` — first key: returns `'a '` (hex: 6120)
  - `('a ', NULL)` — key after 'a ': returns `'a!'` (hex: 6121)
  - `(NULL, 'a ')` — key before 'a ': returns `'Z~'` (hex: 5A7E)
  - `('a0', 'a1')` — key between: returns `'a0P'` (hex: 613050)
  - `('aaa', 'aab')` — key between close values: returns `'aaaP'` (hex: 61616150)
  - `('', 'a ')` — edge case with empty string: both reject as invalid
  - Long strings (101 chars) to test: returns `'aQ'` (hex: 6151)
- [x] Outputs are **byte-identical** (not just semantically equivalent).
- [x] Test fails if any output differs.
- [x] Results maintain lexicographic ordering: `a < result < b` when both are non-NULL.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

### 2025-12-18
- Created `zig/harness/test-fract-parity.sh` with 12 test cases
- Wired into `zig/harness/test-parity.sh`
- All 12 parity tests pass - Zig and Rust/C produce byte-identical output

## Completion Notes

### Commands Run
```bash
# Direct test run
./zig/harness/test-fract-parity.sh

# Via make target
make -C zig test-parity
```

### Full Test Output
```
╔═══════════════════════════════════════════════════════════════════════╗
║       Fractional Index Oracle Parity Test                            ║
║  Compares Rust/C vs Zig implementation of crsql_fract_key_between    ║
╚═══════════════════════════════════════════════════════════════════════╝

Rust/C extension: lib/crsqlite.dylib
Zig extension:    lib/crsqlite-zig-darwin-aarch64.dylib

Test: (NULL, NULL) — first key
  Rust/C: 'a ' (hex: 6120)
  Zig:    'a ' (hex: 6120)
  ✓ Byte-identical: YES
  PASS

Test: ('a ', NULL) — key after 'a '
  Rust/C: 'a!' (hex: 6121)
  Zig:    'a!' (hex: 6121)
  ✓ Byte-identical: YES
  PASS

Test: (NULL, 'a ') — key before 'a '
  Rust/C: 'Z~' (hex: 5A7E)
  Zig:    'Z~' (hex: 5A7E)
  ✓ Byte-identical: YES
  PASS

Test: ('a0', 'a1') — key between
  Rust/C: 'a0P' (hex: 613050)
  Zig:    'a0P' (hex: 613050)
  ✓ Byte-identical: YES
  ✓ Ordering: a < result < b
  PASS

Test: ('aaa', 'aab') — close values
  Rust/C: 'aaaP' (hex: 61616150)
  Zig:    'aaaP' (hex: 61616150)
  ✓ Byte-identical: YES
  ✓ Ordering: a < result < b
  PASS

Test: ('a0P', 'a0Q') — very close values
  Rust/C: 'a0PP' (hex: 61305050)
  Zig:    'a0PP' (hex: 61305050)
  ✓ Byte-identical: YES
  ✓ Ordering: a < result < b
  PASS

Test: Long string (101 chars)
  Rust/C: 'aQ' (hex: 6151)
  Zig:    'aQ' (hex: 6151)
  ✓ Byte-identical: YES
  PASS

Test: (NULL, 'Z~') — negative integer
  Rust/C: 'Z}' (hex: 5A7D)
  Zig:    'Z}' (hex: 5A7D)
  ✓ Byte-identical: YES
  PASS

Test: ('Z}', 'Z~') — between negative integers
  Rust/C: 'Z}P' (hex: 5A7D50)
  Zig:    'Z}P' (hex: 5A7D50)
  ✓ Byte-identical: YES
  ✓ Ordering: a < result < b
  PASS

Test: Sequential key generation maintains ordering
  Rust/C sequence (hex): 6120,6121,6122,6123,6124
  Zig sequence (hex):    6120,6121,6122,6123,6124
  ✓ Byte-identical: YES
  PASS

Test: Error case parity - empty string
  Rust/C value: ERROR (rejects invalid input)
  Zig value:    ERROR (rejects invalid input)
  ✓ Both reject invalid input (empty string)
  PASS

Test: Error case parity - a > b (invalid order)
  Rust/C: Error (must be before)
  Zig:    Error (left key must be before right key)
  ✓ Both produce error on invalid order
  PASS

╔═══════════════════════════════════════════════════════════════════════╗
║                     PARITY TEST SUMMARY                              ║
╠═══════════════════════════════════════════════════════════════════════╣
║  PASSED:  12                                                         ║
║  FAILED:  0                                                          ║
╚═══════════════════════════════════════════════════════════════════════╝

✓ All parity tests PASSED - Zig and Rust/C are byte-identical
```

### Divergences Discovered
None - all outputs are byte-identical between Zig and Rust/C implementations.

### Notes on Test Input Format
The fractional index algorithm uses a specific key format with an "integer part" prefix. Valid keys must:
- Start with a letter A-Z (negative integers) or a-z (positive integers)
- Have a fractional part using base-95 digits (space to tilde)

Invalid inputs like `'a'` (missing fractional part) or `''` (empty string) are rejected by both implementations.
