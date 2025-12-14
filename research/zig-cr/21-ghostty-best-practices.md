# 21-ghostty-best-practices

## Inventory

Representative files:
- Build entry: `.refs/ghostty/build.zig`
- Build system modules: `.refs/ghostty/src/build/Config.zig`, `.refs/ghostty/src/build/SharedDeps.zig`
- Examples of allocator patterns: `.refs/ghostty/src/termio/Termio.zig`, `.refs/ghostty/src/termio/Exec.zig`
- Testing idioms: `.refs/ghostty/src/termio/message.zig`, `.refs/ghostty/src/unicode/*`

## Runtime Role

Ghostty is a large Zig codebase with strong discipline around:
- keeping `build.zig` orchestration thin
- factoring build logic into modules
- explicit allocator lifetimes
- deterministic, leak-checked tests

## SQLite API Requirements

None (this is a Zig best-practices reference).

## Porting Implications (Zig)

Build/layout patterns to copy:
- Enforce minimum Zig version at comptime (`build.zig.zon` + `requireZig`).
- Centralize `-D` config parsing in a `Config` object.
- Create a “SharedDeps” object to apply consistent options/imports to multiple artifacts.

Allocator patterns to copy:
- Use `ArenaAllocator` for “many allocations, single lifetime” objects.
- Use `stackFallback` for bounded temporary buffers.
- Use `errdefer` for safe partial init cleanup.

Testing patterns to copy:
- `std.testing.refAllDecls(@This())` for compile coverage.
- ABI/size regression assertions for message structs.
- ability to skip expensive tests under valgrind.

## Risks / Unknowns

- Ghostty’s build system is sophisticated; for a CR-SQLite port, keep the same philosophy but simplify to a small set of artifacts (extension + tests).

## MVP Cut

- Start with a minimal `build.zig` and only adopt more of Ghostty’s build modularity when the artifact graph grows (multiple targets, optional system deps).
