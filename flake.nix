{
  description = "Pure-Nix CR-SQLite extension (.dylib/.so) for conflict-free replicated databases";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # Use the working tree as source (include submodules)
        # builtins.path snapshots the on-disk tree instead of the flake's
        # git-based source (which omits submodule contents). We then apply a
        # lightweight clean filter to avoid bulky folders like node_modules.
        crSqliteSource = pkgs.lib.cleanSourceWith {
          src = builtins.path { path = ./.; name = "crsqlite-src"; };
          filter = path: type:
            pkgs.lib.cleanSourceFilter path type &&
            !(builtins.elem (baseNameOf path) [
              ".git" 
              "node_modules" "dist" "result" "build" "target"
              ".direnv" ".turbo" ".vscode" "__pycache__"
            ]);
        };
        
        # Rust toolchain - use nightly as required by CR-SQLite
        rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
          extensions = [ "rust-src" ];
        };

        # Build the CR-SQLite extension
        crSqliteExtension = pkgs.stdenv.mkDerivation rec {
          pname = "cr-sqlite";
          version = "0.16.3";
          
          src = crSqliteSource;
          
          nativeBuildInputs = with pkgs; [
            rustToolchain
            pkg-config
            gnumake
            git
          ];

          buildInputs = with pkgs; [
            sqlite
            openssl
          ];

          # Rust/Cargo environment
          CARGO_HOME = "$TMPDIR/.cargo";
          RUSTC_BOOTSTRAP = "1";
          
          # Build the extension using the upstream Makefile
          buildPhase = ''
            # Debug: show what files are actually available
            echo "=== DEBUG: Files in build root (first 30) ==="
            find . -maxdepth 2 -type f | head -30
            echo
            echo "=== DEBUG: core directory checks ==="
            ls -la core || true
            ls -la core/rs || true
            ls -la core/rs/sqlite-rs-embedded || true
            test -f core/Makefile && echo "Found core/Makefile" || echo "Missing core/Makefile"
            echo
            echo "=== DEBUG: sqlite-rs-embedded sample files ==="
            find core/rs/sqlite-rs-embedded -maxdepth 2 -name "*.toml" 2>/dev/null | head -10 || echo "No .toml files found"
            # Stop early; this is a verification build
            exit 1
          '';

          installPhase = ''
            mkdir -p $out/lib
            
            # Copy the loadable extension from core/dist/
            if [ -f core/dist/crsqlite.dylib ]; then
              cp core/dist/crsqlite.dylib $out/lib/crsqlite.dylib
            elif [ -f core/dist/crsqlite.so ]; then
              cp core/dist/crsqlite.so $out/lib/crsqlite.so
            else
              echo "ERROR: No extension file found in core/dist/"
              find core/dist/ -type f || echo "No core/dist directory found"
              exit 1
            fi
            
            # List what we built for debugging
            echo "Built extension:"
            ls -la $out/lib/
          '';

          meta = with pkgs.lib; {
            description = "CR-SQLite loadable extension for ${system}";
            platforms = [ system ];
            license = licenses.asl20;
          };
        };

        # Package: exposes only the extension files
        extensionOnly = pkgs.stdenv.mkDerivation {
          pname = "cr-sqlite-extension";
          version = crSqliteExtension.version;
          src = pkgs.writeText "dummy" "";
          dontConfigure = true;
          dontBuild = true;
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/lib
            # copy extension files (dylib on darwin, so* on linux), keep symlinks
            cp -a ${crSqliteExtension}/lib/crsqlite*.dylib $out/lib/ 2>/dev/null || true
            cp -a ${crSqliteExtension}/lib/crsqlite*.so*   $out/lib/ 2>/dev/null || true
          '';
          meta = with pkgs.lib; {
            description = "CR-SQLite extension for ${system}";
            platforms = [ system ];
            license = licenses.asl20;
          };
        };

        # App: prints canonical path to the extension
        printPath = pkgs.writeShellApplication {
          name = "cr-sqlite-extension-path";
          text = ''
            set -euo pipefail
            dir='${extensionOnly}/lib'
            candidate=$(find "$dir" -name "crsqlite*.dylib" -o -name "crsqlite*.so*" 2>/dev/null | head -n1)
            [ -n "''${candidate:-}" ] || { echo "crsqlite extension not found" >&2; exit 1; }
            echo "$candidate"
          '';
        };

        # App: prints the CR-SQLite version
        printVersion = pkgs.writeShellApplication {
          name = "cr-sqlite-version";
          text = ''
            echo "0.16.3"
          '';
        };

        # App: builds extensions for current platform with correct naming
        buildAllPlatforms = pkgs.writeShellApplication {
          name = "build-all-platforms";
          text = ''
            set -euo pipefail
            echo "🔨 Building CR-SQLite extension for current platform..."
            
            # Build for current platform
            nix build .#cr-sqlite
            
            mkdir -p lib
            
            # Determine current platform and architecture
            current_system="${system}"
            case "$current_system" in
              x86_64-linux)
                platform="linux"
                arch="x86_64"
                ext="so"
                ;;
              aarch64-linux) 
                platform="linux"
                arch="aarch64"
                ext="so"
                ;;
              x86_64-darwin)
                platform="darwin"
                arch="x86_64" 
                ext="dylib"
                ;;
              aarch64-darwin)
                platform="darwin"
                arch="aarch64"
                ext="dylib"
                ;;
              *)
                echo "⚠️  Unsupported platform: $current_system"
                exit 1
                ;;
            esac
            
            # Copy with platform-specific naming
            echo "📦 Copying extension for $platform-$arch..."
            case "$ext" in
              so)
                # Find and copy the .so file
                so_file=$(find result/lib -name "crsqlite.so*" -type f | head -n1)
                if [ -n "$so_file" ]; then
                  cp -v "$so_file" "lib/crsqlite-$platform-$arch.so"
                  cp -v "$so_file" "lib/crsqlite.so"  # fallback
                fi
                ;;
              dylib)
                # Find and copy the .dylib file
                dylib_file=$(find result/lib -name "crsqlite*.dylib" -type f | head -n1)
                if [ -n "$dylib_file" ]; then
                  cp -v "$dylib_file" "lib/crsqlite-$platform-$arch.dylib"
                  cp -v "$dylib_file" "lib/crsqlite.dylib"  # fallback
                fi
                ;;
            esac
            
            echo "✅ Build complete for $current_system:"
            ls -la lib/
          '';
        };

        # CI check: ensure extension can be loaded (basic existence check)
        checkExt = pkgs.runCommand "check-cr-sqlite-ext" 
          { buildInputs = [ pkgs.sqlite ]; } 
          ''
            # Just check that the extension file exists and is a valid shared library
            ext_file="${extensionOnly}/lib/crsqlite.so"
            if [ ! -f "$ext_file" ]; then
              ext_file="${extensionOnly}/lib/crsqlite.dylib"
            fi
            
            if [ -f "$ext_file" ]; then
              echo "Extension file exists: $ext_file"
              file "$ext_file" || echo "file command not available"
              touch $out
            else
              echo "No extension file found in ${extensionOnly}/lib/"
              ls -la ${extensionOnly}/lib/ || echo "No lib directory"
              exit 1
            fi
          '';

      in {
        packages.cr-sqlite = extensionOnly;
        packages.default = extensionOnly;
        apps."print-path" = { type = "app"; program = "${printPath}/bin/cr-sqlite-extension-path"; };
        apps."print-version" = { type = "app"; program = "${printVersion}/bin/cr-sqlite-version"; };
        apps."build-all-platforms" = { type = "app"; program = "${buildAllPlatforms}/bin/build-all-platforms"; };
        checks.loadableExtension = checkExt;
        devShells.default = pkgs.mkShell { 
          buildInputs = with pkgs; [ 
            sqlite 
            rustToolchain
            pkg-config
            cmake
            gnumake
          ]; 
        };
      });
}
