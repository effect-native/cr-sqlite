# TASK-033: Mobile Static Embedding Guide (iOS + Android)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
low

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (Cross-platform Packaging & CI)
- Platform notes: `research/zig-cr/93-phased-execution-proposal.md` (static embedding for web/iOS/Android)
- Zig build: `zig/build.zig` (static lib already built)

## Description
Document and validate a minimal static-embedding path for mobile:

- iOS: link `libcrsql.a` into an app's SQLite build (or host SQLite) and call init symbol
- Android: same idea, but NDK toolchain

Important: this is a guide + validation harness, not a full RN integration.

## Files to Modify
- `zig/README.md` (optional section)
- `research/zig-cr/*` (small focused guide doc; keep it close to code)
- `research/zig-cr/92-gap-backlog.md` (status notes)

## Acceptance Criteria
- [ ] Clear steps for building a static archive for target platforms.
- [ ] Explicit note about why dynamic extension loading often fails on mobile.
- [ ] A minimal "hello" validation strategy described (even if not runnable in CI).

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

## Completion Notes
[fill in when done]
