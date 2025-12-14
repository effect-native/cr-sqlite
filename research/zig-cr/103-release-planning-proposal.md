# 103: Release Planning Proposal

## Overview

This document proposes a release strategy for the Zig-based CR-SQLite implementation. The goal is to distribute prebuilt artifacts to developers across multiple platforms and ecosystems.

## Current State

**What exists today:**

| Artifact | Location | Status |
|----------|----------|--------|
| Node/Bun native package | `@effect-native/libcrsql` | Shipping (C/Rust builds) |
| Browser WASM package | `@effect-native/libcrsql-browser` | Ready (Zig builds) |
| Nix flake | `flake.nix` | Working (builds C/Rust) |
| Zig source | `zig/` | 154/154 tests passing |

**What's ready for release:**
- macOS universal binary (aarch64 + x86_64)
- Windows .dll (x86_64-windows-gnu)
- Browser WASM with multi-tab coordination
- Linux builds (need CI verification)

---

## Distribution Channels

### 1. npm (Primary Channel)

**Packages:**

| Package | Purpose | Audience |
|---------|---------|----------|
| `@effect-native/libcrsql` | Native extension for Node/Bun | Server-side developers |
| `@effect-native/libcrsql-browser` | WASM + multi-tab coordination | Frontend developers |

**Pros:**
- Largest reach (millions of daily downloads ecosystem-wide)
- Existing infrastructure (package.json, npm publish)
- Easy `npm install` for end users
- Works with bundlers (webpack, vite, esbuild)

**Cons:**
- 50MB tarball limit (need platform-specific optional deps for native)
- No native code execution on install (postinstall scripts are discouraged)
- Binary hosting needs npm or external CDN

**Recommended Pattern:** Follow `better-sqlite3`, `@esbuild/*`, `@rollup/rollup-*` model:
```
@effect-native/libcrsql                 # Main package (JS API + platform detection)
@effect-native/libcrsql-darwin-arm64    # Optional: macOS Apple Silicon
@effect-native/libcrsql-darwin-x64      # Optional: macOS Intel
@effect-native/libcrsql-linux-x64       # Optional: Linux Intel
@effect-native/libcrsql-linux-arm64     # Optional: Linux ARM
@effect-native/libcrsql-win32-x64       # Optional: Windows
@effect-native/libcrsql-browser         # WASM bundle (already exists)
```

### 2. GitHub Releases

**Pros:**
- Free hosting for binaries
- Automatic with GitHub Actions
- Direct download links for manual installation
- Changelog/release notes integration
- Works for Nix binary cache fallback

**Cons:**
- Manual download (not `npm install`)
- Need to document URLs

**Recommended:** Use for:
- Raw binaries (`.dylib`, `.so`, `.dll`, `.wasm`)
- Universal binaries (macOS fat binary)
- Checksums (`sha256sums.txt`)
- Source tarballs

### 3. Nix Flakes

**Pros:**
- Reproducible builds
- Easy `nix run` / `nix build`
- Content-addressed binary cache
- Excellent for CI/CD

**Cons:**
- Small audience (Nix users only)
- Requires Nix installation

**Recommended:** Keep `flake.nix`, add Zig build option:
```bash
nix build .#crsqlite-zig      # Zig implementation
nix build .#crsqlite          # Legacy C/Rust (for comparison)
```

### 4. JSR (Deno Registry)

**Pros:**
- Growing Deno ecosystem
- TypeScript-first
- Good for Deno Deploy

**Cons:**
- Smaller audience than npm
- Different module resolution

**Verdict:** Low priority. Can add later if there's demand.

### 5. CDN (unpkg, esm.sh, jsDelivr)

**Pros:**
- Direct `<script>` tag usage
- No build step for browser
- Great for prototyping

**Cons:**
- Depends on npm publish
- Version pinning complexity

**Recommended:** Works automatically after npm publish. Document URLs:
```html
<script type="module">
  import { createCoordinator } from 'https://esm.sh/@effect-native/libcrsql-browser';
</script>
```

### 6. Other Channels (Not Recommended)

| Channel | Why Not |
|---------|---------|
| Homebrew | SQLite extensions aren't typical brew packages |
| Cargo | Not a Rust project anymore |
| apt/rpm | High maintenance, low audience |
| CocoaPods/Swift PM | Better to document manual integration |

---

## Versioning Strategy

### Recommendation: Aligned Versions with Independent Patches

```
@effect-native/libcrsql           0.17.0    # Main version
@effect-native/libcrsql-browser   0.17.0    # Same major.minor
@effect-native/libcrsql-*-*       0.17.0    # Platform packages
```

**Rules:**
1. **Major version**: Breaking API changes (rare)
2. **Minor version**: New features, new platforms, significant fixes
3. **Patch version**: Bug fixes, CI improvements

**Version source of truth:** `package.json` in repo root

**Rationale:**
- Simpler mental model ("is my browser package compatible with my server package?")
- Sync points force testing all platforms together
- Upstream CR-SQLite is at 0.16.x; we can align or diverge

---

## Artifact Matrix

### Native Extensions

| Platform | Arch | Format | Priority | Status |
|----------|------|--------|----------|--------|
| macOS | arm64 | `.dylib` | P0 | Ready |
| macOS | x86_64 | `.dylib` | P0 | Ready |
| macOS | universal | `.dylib` | P1 | Ready |
| Linux | x86_64 | `.so` | P0 | Needs CI |
| Linux | arm64 | `.so` | P1 | Needs CI |
| Windows | x86_64 | `.dll` | P2 | Ready (GNU) |
| Windows | arm64 | `.dll` | P3 | Not started |

### Browser/WASM

| Artifact | Format | Priority | Status |
|----------|--------|----------|--------|
| Core WASM | `sql-wasm.wasm` | P0 | Ready |
| Multi-tab coordinator | `coordinator.js` | P0 | Ready |
| Provider implementation | `provider.js` | P0 | Ready |
| TypeScript types | `index.d.ts` | P0 | Ready |

### Build Matrix CI

```yaml
# Proposed GitHub Actions matrix
strategy:
  matrix:
    include:
      - os: macos-latest
        target: aarch64-apple-darwin
      - os: macos-13
        target: x86_64-apple-darwin
      - os: ubuntu-latest
        target: x86_64-unknown-linux-gnu
      - os: ubuntu-latest
        target: aarch64-unknown-linux-gnu
      - os: windows-latest
        target: x86_64-pc-windows-gnu
```

---

## Documentation Strategy

### Principle: Docs Live Near Code

| Doc Type | Location | Notes |
|----------|----------|-------|
| API reference | Inline JSDoc in `.js`/`.ts` | IDE autocomplete |
| Build instructions | `zig/README.md` | Exists |
| Usage guide | `README.md` (root) | Exists, needs update |
| Browser quickstart | `zig/browser-dist/README.md` | Needs creation |
| Architecture | `research/zig-cr/*.md` | Exists |
| Changelog | `CHANGELOG.md` | Needs automation |

### Documentation Checklist

- [ ] Update root `README.md` to mention Zig implementation
- [ ] Add "Zig vs C/Rust" section explaining the transition
- [ ] Create `zig/browser-dist/README.md` with multi-tab usage examples
- [ ] Add migration guide for existing C/Rust users (if API differs)
- [ ] Document platform support matrix in README

---

## Staged Rollout Plan

### Stage 1: Browser Beta (Week 1)

**Goal:** Ship `@effect-native/libcrsql-browser` to npm

**Tasks:**
- [ ] Finalize `zig/browser-dist/package.json` version
- [ ] Write `zig/browser-dist/README.md` with usage examples
- [ ] Verify WASM builds in CI
- [ ] Publish to npm with `beta` tag: `npm publish --tag beta`
- [ ] Test in real application (multi-tab demo)

**Acceptance:** Users can `npm install @effect-native/libcrsql-browser@beta`

### Stage 2: Linux Native (Week 2)

**Goal:** Ship Linux x86_64 Zig builds as default

**Tasks:**
- [ ] Set up Linux CI builds (GitHub Actions + Nix)
- [ ] Create platform-specific npm packages (`@effect-native/libcrsql-linux-x64`)
- [ ] Test in Docker container
- [ ] Publish with `beta` tag

**Acceptance:** `npm install @effect-native/libcrsql` works in Docker/Linux

### Stage 3: macOS + Windows (Week 3)

**Goal:** Full native platform support

**Tasks:**
- [ ] Publish `@effect-native/libcrsql-darwin-arm64`
- [ ] Publish `@effect-native/libcrsql-darwin-x64`
- [ ] Publish `@effect-native/libcrsql-win32-x64`
- [ ] Update main package to auto-select platform package
- [ ] Test on all platforms

**Acceptance:** Works on macOS (Intel + Apple Silicon) and Windows

### Stage 4: Stable Release (Week 4)

**Goal:** Remove beta tags, update docs, announce

**Tasks:**
- [ ] Remove `beta` tags from all packages
- [ ] Update root README with new architecture
- [ ] Create GitHub Release with binaries
- [ ] Write migration guide (if needed)
- [ ] Announce on relevant channels

**Acceptance:** `npm install @effect-native/libcrsql` just works everywhere

### Stage 5: Post-Release (Ongoing)

- [ ] Linux ARM64 support
- [ ] Windows ARM64 support
- [ ] iOS/Android static library guides
- [ ] Performance benchmarks vs C/Rust
- [ ] Service Worker fallback for older browsers

---

## Engineering Tasks for `.tasks/`

Based on this proposal, the following task cards should be created:

### Immediate (P0)

| Task ID | Title | Files |
|---------|-------|-------|
| TASK-037 | Publish browser package to npm beta | `zig/browser-dist/*` |
| TASK-038 | Set up Zig Linux CI builds | `.github/workflows/*` |
| TASK-039 | Create platform-specific npm packages | `package.json`, new packages |

### Short-term (P1)

| Task ID | Title | Files |
|---------|-------|-------|
| TASK-040 | Update root README for Zig transition | `README.md` |
| TASK-041 | Write browser package README | `zig/browser-dist/README.md` |
| TASK-042 | Create GitHub Release workflow | `.github/workflows/release.yml` |

### Medium-term (P2)

| Task ID | Title | Files |
|---------|-------|-------|
| TASK-043 | Windows ARM64 builds | `zig/build.zig`, CI |
| TASK-044 | Linux ARM64 CI verification | `.github/workflows/*` |
| TASK-045 | Changelog automation | `scripts/`, `.github/` |

---

## Risk Analysis

| Risk | Mitigation |
|------|------------|
| npm publish fails for large binaries | Use platform-specific optional deps |
| Windows builds have ABI issues | Test both GNU and MSVC targets |
| Breaking changes from C/Rust version | Maintain both, document differences |
| CI costs for matrix builds | Use Nix binary cache, parallelize |
| Users stuck on old versions | Semantic versioning, deprecation notices |

---

## Success Metrics

1. **Adoption:** npm weekly downloads > 1000 within 3 months
2. **Reliability:** Zero critical bugs in stable release
3. **Platform coverage:** All P0/P1 platforms shipping
4. **Documentation:** < 5 minutes from `npm install` to working code
5. **Bundle size:** Browser package < 2MB gzipped

---

## Appendix: Competitor Analysis

### How similar projects distribute:

**better-sqlite3:**
- Platform-specific npm packages (`better-sqlite3-darwin-arm64`, etc.)
- Prebuild binaries via GitHub Releases
- Fallback to node-gyp compile

**sql.js:**
- Single npm package with WASM
- CDN-friendly (works via unpkg)
- ~2MB download

**@libsql/client:**
- Multiple packages (core + platform-specific)
- Turso hosting integration
- WASM + native both supported

**Recommendation:** Follow `better-sqlite3` model for native, `sql.js` model for browser.
