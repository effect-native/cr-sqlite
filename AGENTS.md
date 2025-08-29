# Repository Guidelines

## Project Structure & Module Organization
- Core C/Rust: `core/` (CR‑SQLite sources, Makefile, tests). Builds shared library into `core/dist/`.
- Node package entry: `index.js`, types `index.d.ts`, CLI `bin/`, helper macro `build-macros.ts`.
- Prebuilt artifacts: `lib/` (platform‑specific `crsqlite-<platform>-<arch>.(dylib|so)` and fallbacks).
- Nix flake: `flake.nix` (packages, dev shell, apps like `print-path`, `build-all-platforms`).
- Scripts: `scripts/` (production bundling, version sync, VPS verification).
- Tests: C tests under `core/src/*.test.c`; integration in `py/correctness/`; packaging sanity `dist.test.ts`.

## Build, Test, and Development
- Build (current platform via Nix): `npm run build` (nix build .#cr-sqlite).
- Bundle local lib: `npm run bundle-lib` → writes to `lib/` with platform naming.
- Production bundle (multi‑platform): `npm run build-production`.
- Validate flake: `npm run check` (nix flake check).
- Tests: `npm test` (flake check), `npm run test:docker` (if Docker running), `npm run test:vps`.
- Manual core build: `make -C core loadable` (outputs `core/dist/crsqlite.(dylib|so)`).
- Dev shell: `nix develop` to enter environment with Rust/C toolchains.

## Coding Style & Naming Conventions
- JS/TS: ESM modules, Node ≥16. Prettier enforced: 2‑space indent, trailing commas (es5), double quotes (`.prettierrc`).
- C: follow upstream style; `core/.clang-format` available; keep changes minimal.
- Artifacts: name as `crsqlite-<platform>-<arch>.(dylib|so)` and keep generic fallbacks (`crsqlite.dylib|so`).

## Testing Guidelines
- Wrapper/package changes: run `npm run check` and `npm run test:vps`; if packaging logic changes, also run `npx tsx dist.test.ts`.
- Core changes: `make -C core test` (optionally `valgrind`), and run CI‑mirroring commands in `.github/workflows/*` when possible.
- Python correctness (optional): `cd py/correctness && ./install-and-test.sh`.

## Commit & Pull Request Guidelines
- Messages: concise, imperative (“Fix build on Linux”, “Add extension path CLI”).
- Scope: separate functional changes from formatting. Reference issues when relevant.
- PRs: include description, affected platforms, test results (commands run + output snippets), and any `lib/` artifacts touched. Screenshots/logs for `npx libcrsql-extension-path` helpful.

## Security & Configuration Tips
- Prefer Nix builds for reproducibility. Avoid committing built binaries outside `lib/`.
- For cross‑compiles, use `npm run build-production`; avoid ad‑hoc renames—let scripts place files correctly.
- Do not modify vendored upstream lightly (`core/`); propose upstream when possible.

