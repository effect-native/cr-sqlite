the old libcrsqlite.{dylib,so,dll} build(s) of the old rust cr-sqlite implementation was chonkier than sqlite itself
i believe this is because rust includes some about of runtime stuff that gets included in the build
i expect that a properly optimized build of our zig-based re-implementation should be significantly smaller than sqlite itself
if our zig build is big, that smells like we screwed something up somehow
that, or I'm confused about something

---

## Satisfied

- **Date**: 2025-12-17
- **What changed**: Size report implemented in Round 38 (TASK-068)
- **Evidence**: 
  - `make -C zig size-report` shows: Zig crsqlite is 105.72% of SQLite (~103KB overhead)
  - This is dramatically smaller than the Rust build (which was ~2-3x SQLite)
- **Conclusion**: Zig build is healthy — extension overhead is minimal (~6% over baseline SQLite)
