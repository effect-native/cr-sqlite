# TASK-033: Mobile Static Embedding Guide (iOS + Android)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] Clear steps for building a static archive for target platforms.
- [x] Explicit note about why dynamic extension loading often fails on mobile.
- [x] A minimal "hello" validation strategy described (even if not runnable in CI).

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started
- Task completed: created comprehensive mobile static embedding guide

## Completion Notes
**Completed: 2025-12-14**

Created `research/zig-cr/104-mobile-static-embedding-guide.md` covering:
- Why static embedding is required (dynamic loading blocked on iOS, limited on Android)
- Zig build commands for all iOS and Android targets
- iOS integration: XCFramework creation, Swift/ObjC init code examples
- Android integration: CMake setup, JNI wrapper, Kotlin examples
- Validation strategy: symbol checks, minimal "hello" test apps, integration checklist
- Common issues and troubleshooting

Also updated:
- `zig/README.md`: added link to guide, removed "packaging guides" from limitations
- `research/zig-cr/92-gap-backlog.md`: marked mobile embedding docs as done
