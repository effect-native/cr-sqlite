Gaps (zig/ vs research/zig-cr)  
- Docs mismatch: zig/README.md:5 still claims partial C oracle + missing alter, but research/zig-cr/92-gap-backlog.md:7 says MVP complete and 154/154 passing. This is a real “gap” because it will mislead anyone trying to use/validate the Zig implementation.  
- Performance hotspot items not yet done (from research/zig-cr/11-performance-hotspots.md:6 and tracked in research/zig-cr/92-gap-backlog.md:161):  
  - PRAGMA schema_version-keyed invalidation caching  
  - PRAGMA data_version amortization (per-transaction / per-query-loop flag)  
  - sqlite3_prepare_v3(...SQLITE_PREPARE_PERSISTENT...) use for long-lived statements  
- Web multi-tab “Phase 2” items still open (called out in research/zig-cr/92-gap-backlog.md:186 and motivated by research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md:10):  
  - Service Worker fallback (when SharedWorker missing)  
  - Reactive query subscriptions / notifications surface (more than “manual re-query”)  
- Cross-platform packaging gaps (tracked in research/zig-cr/92-gap-backlog.md:214):  
  - macOS universal binary (aarch64+x86_64)  
  - Windows .dll build  
  - iOS/Android static embedding guide  
- Big future proposals not implemented (expected): the “threadsafe-by-default / mesh” family (research/zig-cr/99-threadsafe-sqlite-proposals.md:31, research/zig-cr/100-proposal-node-multiprocess-crsqlite-mesh.md:19, research/zig-cr/101-proposal-universal-crsqlite-mt-js.md:34, research/zig-cr/102-proposal-crsqlite-global-mesh.md:5) has no corresponding implementation in zig/ yet.
Wishes review (.wishes/)  
- /.wishes/spec-first-RGRTDD.md:1 asks for new “realistic” spec/tests-as-examples now that we’re green everywhere.  
- /.wishes/stop-before-typescript.md:1 is an explicit constraint: do not race ahead on new TS work; if we feel pressure to do TS-heavy features, we should write it down and mark it blocked.
Tasks review (.tasks/)  
- Only one backlog task exists: /.tasks/backlog/TASK-026-A-macos-universal-binary.md:1.  
- It’s directionally right, but the implementation notes are currently underspecified relative to zig/build.zig’s default single zig-out/ install prefix (zig/build.zig:46). To build two mac targets without stomping outputs, the task should explicitly require separate --prefix (and likely separate cache dirs) per target before lipo.
Proposed next concurrent subagent assignments (do not assign yet)  
1) macOS universal dylib (highest near-term “ship-ability”)  
   - Based on existing backlog /.tasks/backlog/TASK-026-A-macos-universal-binary.md:1  
   - Files: zig/Makefile:1 (add make universal or similar), maybe CI workflow later  
   - Output verification: lipo -info ... + load-test with sqlite3 via nix
2) Performance tranche: schema/data version amortization + persistent statements  
   - Source: research/zig-cr/11-performance-hotspots.md:6, backlog research/zig-cr/92-gap-backlog.md:161  
   - Files likely centered on zig/src/changes_vtab.zig and wherever we prepare hot statements (plus any stmt cache module)  
   - Goal: reduce prepare churn + pragma spam without changing semantics
3) Windows .dll build reconnaissance + minimal build target (even if not fully CI’d yet)  
   - Source: research/zig-cr/92-gap-backlog.md:215  
   - Files: zig/build.zig:1 (target/export correctness), plus a small harness note on how to test load on Windows  
   - Outcome: either a real build artifact path or a crisp “blocked by X” statement with next steps
4) Docs alignment task (small but high leverage)  
   - Fix zig/README.md:5 to reflect reality and point at the real acceptance suite location (research/zig-cr/10-test-oracle.md / core/src/*.test.c)  
   - This closes the “people can’t tell what’s done” gap immediately
5) Spec-first “realistic scenarios” tests (non-TS)  
   - Convert /.wishes/spec-first-RGRTDD.md:8 into a small set of new harness tests under zig/harness/ that read like executable examples.  
   - Keep it Zig/shell first to respect /.wishes/stop-before-typescript.md:1.  
   - If any scenario truly demands TS (e.g. SW fallback), we write a blocked wish/task instead of implementing.
.tasks accuracy fixups (recommend before we start work)  
- Update /.tasks/backlog/TASK-026-A-macos-universal-binary.md:31 to explicitly require per-target zig build with distinct --prefix outputs (so the lipo paths in the task are actually achievable), and clarify whether we expect nix cross-target builds to work on this host or if it needs a remote builder.
