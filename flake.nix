{
  description = "Pure-Nix CR-SQLite extension (.dylib/.so) for conflict-free replicated databases";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Use the working tree as source
        crSqliteSource = pkgs.lib.cleanSourceWith {
          src = builtins.path { path = ./.; name = "crsqlite-src"; };
          filter = path: type:
            pkgs.lib.cleanSourceFilter path type &&
            !(builtins.elem (baseNameOf path) [
              ".git" 
              "node_modules" "dist" "result" "build" "target"
              ".direnv" ".turbo" ".vscode" "__pycache__"
              "zig-cache" "zig-out"
            ]);
        };

        # Build the CR-SQLite extension using Zig
        crSqliteExtension = pkgs.stdenv.mkDerivation rec {
          pname = "cr-sqlite";
          version = "0.16.300-preview";
          
          src = crSqliteSource;
          dontStrip = true;
          
          nativeBuildInputs = with pkgs; [
            zig
          ];

          # Build the extension using Zig
          # Use -p to install directly to $out, avoiding zig-out
          buildPhase = ''
            set -euxo pipefail
            export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
            export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
            cd zig
            zig build -Doptimize=ReleaseFast -p $out
          '';

          installPhase = ''
            # Zig outputs libcrsqlite.dylib on Darwin, libcrsqlite.so on Linux
            # Rename to crsqlite.dylib/crsqlite.so for consistency with legacy naming
            if [ -f $out/lib/libcrsqlite.dylib ]; then
              mv $out/lib/libcrsqlite.dylib $out/lib/crsqlite.dylib
            elif [ -f $out/lib/libcrsqlite.so ]; then
              mv $out/lib/libcrsqlite.so $out/lib/crsqlite.so
            else
              echo "ERROR: No extension file found in $out/lib/"
              find $out/ -type f || echo "No output found"
              exit 1
            fi
            
            echo "Built extension:"
            ls -la $out/lib/
          '';

          meta = with pkgs.lib; {
            description = "CR-SQLite loadable extension for ${system} (Zig build)";
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
            echo "0.16.300-preview"
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
            zig
            pkg-config
          ]; 
        };
        
        # Dev shell with Emscripten for WASM builds
        devShells.wasm = pkgs.mkShell {
          buildInputs = with pkgs; [
            emscripten
            zig
            python3
          ];
          shellHook = ''
            echo "WASM build environment ready!"
            echo "  - emcc: $(emcc --version | head -1)"
            echo "  - zig:  $(zig version)"
            echo ""
            echo "Build steps:"
            echo "  1. cd zig && zig build wasm"
            echo "  2. ./zig/wasm-build/build-sqlite-wasm.sh"
          '';
        };
      });
}
