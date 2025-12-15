# TASK-047: Phase 1 instructions — React Native runtime packages

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Tom notes: `.wishes/done/tom-review-crsql-mesh-instructions.md`
- Package map: `effect-native/.specs/crsqlite-global-mesh-packages/instructions.md` (RN package names)
- Spec-first rules: `effect-native/.specs/AGENTS.md`

## Description
Create Phase 1 `instructions.md` for React Native runtime packages:

- `@effect-native/crsql-mesh-runtime-react-native-op-sqlite`
- `@effect-native/crsql-mesh-runtime-react-native-expo-sqlite`

Keep it thing-golf small: intent + out-of-scope only.
No requirements/design/implementation.

STOP after Phase 1 docs.

## Files to Create
- `effect-native/.specs/crsql-mesh-runtime-react-native-op-sqlite/instructions.md`
- `effect-native/.specs/crsql-mesh-runtime-react-native-expo-sqlite/instructions.md`

## Acceptance Criteria
- [x] Each instructions.md follows Phase 1 rules.
- [x] Each doc explicitly states extension-loading assumptions (native vs wasm).
- [x] Each doc explicitly excludes Electron.

## Progress Log
### 2025-12-15
- Task created from Tom request

### 2025-12-14
- Created `effect-native/.specs/crsql-mesh-runtime-react-native-op-sqlite/instructions.md`
- Created `effect-native/.specs/crsql-mesh-runtime-react-native-expo-sqlite/instructions.md`

## Completion Notes
**Date:** 2025-12-14

**Summary:** Created Phase 1 `instructions.md` files for both React Native runtime packages.

**Files created:**
- `effect-native/.specs/crsql-mesh-runtime-react-native-op-sqlite/instructions.md`
- `effect-native/.specs/crsql-mesh-runtime-react-native-expo-sqlite/instructions.md`

**Key decisions documented:**
- Both packages use **native extension loading** (not WASM) — `.dylib` on iOS, `.so` on Android
- Both packages explicitly exclude Electron
- op-sqlite package targets general React Native apps
- expo-sqlite package requires Expo SDK 54+ for `loadExtensionAsync()` support
- Cross-app sync, background scheduling, and battery-aware sync are deferred to future work
