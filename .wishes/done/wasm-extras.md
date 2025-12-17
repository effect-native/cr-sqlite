our wasm build doesn't support loadable extensions
so let's bake in a few extensions that I particularly like

- our new zig-based cr-sqlite (naturally)
- https://github.com/asg017/sqlite-vec
- full text search
- BJSON

---

**Satisfied:** 2025-12-16 (Round 39)
**What changed:**
- sqlite-vec v0.1.6 statically linked into WASM build
- FTS5 enabled (compile-time flag)
- JSONB enabled (compile-time flag)
- 12 new browser tests proving each extension works
- WASM size: 1,440,717 bytes (~100KB overhead for features)
**Task:** `.tasks/done/TASK-067-zig-wasm-baked-in-extensions.md`
