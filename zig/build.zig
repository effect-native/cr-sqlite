const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.addModule("crsql", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    const lib = b.addLibrary(.{
        .name = "crsql",
        .linkage = .static,
        .root_module = root_mod,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .name = "crsql",
        .root_module = root_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
