const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Check if we're building for WASM
    const is_wasm = target.result.cpu.arch == .wasm32 or target.result.cpu.arch == .wasm64;

    const root_mod = b.addModule("crsql", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add C header include path for SQLite extension headers
    root_mod.addIncludePath(b.path("src/ffi/c"));

    // Add C source file for workaround functions (SQLITE_TRANSIENT, etc.)
    // Note: For WASM builds, we use a Zig-native implementation instead
    if (!is_wasm) {
        root_mod.addCSourceFile(.{
            .file = b.path("src/ffi/c/workaround.c"),
            .flags = &.{},
        });
    }

    root_mod.addAnonymousImport("golden_vectors", .{
        .root_source_file = b.path("test/golden_vectors.zig"),
        .target = target,
        .optimize = optimize,
    });

    root_mod.addAnonymousImport("merge_oracle", .{
        .root_source_file = b.path("test/merge_oracle.zig"),
        .target = target,
        .optimize = optimize,
    });

    root_mod.addAnonymousImport("merge_integration", .{
        .root_source_file = b.path("test/merge_integration.zig"),
        .target = target,
        .optimize = optimize,
    });

    // For native targets, build static and shared libraries
    if (!is_wasm) {
        // Static library for embedding
        const static_lib = b.addLibrary(.{
            .name = "crsql",
            .linkage = .static,
            .root_module = root_mod,
        });
        b.installArtifact(static_lib);

        // Shared library for loadable extension (.so/.dylib)
        // This is the primary output for use as a SQLite loadable extension
        const shared_lib = b.addLibrary(.{
            .name = "crsqlite",
            .linkage = .dynamic,
            .root_module = root_mod,
        });
        b.installArtifact(shared_lib);
    }

    // WASM build: produces a .wasm file that can be loaded into SQLite WASM
    // SQLite WASM uses Emscripten and expects extensions to be compiled in at build time,
    // not dynamically loaded. This WASM artifact is for embedding into SQLite WASM builds.
    if (is_wasm) {
        const wasm_lib = b.addLibrary(.{
            .name = "crsqlite",
            .linkage = .static, // WASM uses static linking - no dynamic loading
            .root_module = root_mod,
        });
        // Export the entry point symbol for SQLite to find
        wasm_lib.root_module.export_symbol_names = &.{
            "sqlite3_crsqlite_init",
            "sqlite3_extension_init",
        };
        b.installArtifact(wasm_lib);
    }

    // Named step for WASM builds (convenience)
    const wasm_step = b.step("wasm", "Build for WebAssembly (wasm32-freestanding)");
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_mod = b.addModule("crsql-wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    wasm_mod.addIncludePath(b.path("src/ffi/c"));
    // No C source for WASM - uses Zig-native workarounds

    wasm_mod.addAnonymousImport("golden_vectors", .{
        .root_source_file = b.path("test/golden_vectors.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    wasm_mod.addAnonymousImport("merge_oracle", .{
        .root_source_file = b.path("test/merge_oracle.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    wasm_mod.addAnonymousImport("merge_integration", .{
        .root_source_file = b.path("test/merge_integration.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });

    // Static library (.a) for embedding into SQLite WASM builds
    // This is the primary WASM artifact - use it when building SQLite WASM with cr-sqlite
    const wasm_static = b.addLibrary(.{
        .name = "crsqlite",
        .linkage = .static,
        .root_module = wasm_mod,
    });
    wasm_static.root_module.export_symbol_names = &.{
        "sqlite3_crsqlite_init",
        "sqlite3_extension_init",
    };
    const wasm_static_install = b.addInstallArtifact(wasm_static, .{});
    wasm_step.dependOn(&wasm_static_install.step);

    // Also produce a standalone .wasm object file for inspection/testing
    // This can be examined with wasm-objdump but cannot be dynamically loaded into SQLite WASM
    const wasm_obj = b.addObject(.{
        .name = "crsqlite",
        .root_module = wasm_mod,
    });
    wasm_obj.root_module.export_symbol_names = &.{
        "sqlite3_crsqlite_init",
        "sqlite3_extension_init",
    };
    // Install the .wasm object file to lib/crsqlite.wasm
    const install_wasm = b.addInstallFile(wasm_obj.getEmittedBin(), "lib/crsqlite.wasm");
    wasm_step.dependOn(&install_wasm.step);

    // Tests only run on native targets
    if (!is_wasm) {
        const tests = b.addTest(.{
            .name = "crsql",
            .root_module = root_mod,
        });

        const run_tests = b.addRunArtifact(tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_tests.step);
    }
}
