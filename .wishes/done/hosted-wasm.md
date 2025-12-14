# ✅ Hosted WASM Proposal

> **Status**: DONE — Proposal written

I wish there was a single hosted wasm thing I could just `import(multi-tab-sqlite-url)` and it all Just works
we need browser ESM js to Just Work™ for quick prototypes
don't do it yet, just write up a proposal for what needs to exist for this to be true

---

## Completion Notes

**Date**: 2025-12-14

**What was done**:
- Wrote comprehensive hosted ESM proposal in `zig/browser-dist/README.md`
- Proposal covers:
  - What files need to be hosted (5 files: crsql-multitab.js, coordinator.js, provider.js, sql-wasm.js, sql-wasm.wasm)
  - Versioning & cache busting strategy (immutable versions, @latest alias, git SHA)
  - Public API surface (DbClient + createDbClient as stable exports)
  - Minimal working example (copy-paste HTML demo)
  - Browser constraints (Chrome 86+, Firefox 114+, Safari 15.4+)
  - No COOP/COEP required
  - Cross-origin considerations and blob URL wrapper solution
  - Implementation checklist for what's still needed

**Where the proposal lives**: `zig/browser-dist/README.md` (under "Hosted ESM Distribution (Proposal)" section)

**Task card**: `.tasks/active/TASK-035-hosted-wasm-proposal.md`

**Open questions for Tom**:
1. Package name: `@effect-native/libcrsql-browser` vs alternatives?
2. CDN choice: Self-hosted vs unpkg vs esm.sh vs skypack?
3. Publishing workflow: Manual vs automated npm+CDN publish?
4. Version strategy: semver strict vs date-based vs git-sha?
