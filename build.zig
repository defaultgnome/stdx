const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The real deal, that the exported lib
    const lib_mod = b.addModule("stdx", .{
        .root_source_file = b.path("src/stdx.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Testing ---

    const plugin_mod = b.createModule(.{
        .root_source_file = b.path("test/fixtures/hot_module_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });

    const plugin = b.addLibrary(.{
        .name = "stdx_hot_module_plugin",
        .linkage = .dynamic,
        .root_module = plugin_mod,
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const test_options = b.addOptions();
    test_options.addOptionPath("plugin_lib_path", plugin.getEmittedBin());

    const hot_module_test_mod = b.createModule(.{
        .root_source_file = b.path("src/hot_module_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    hot_module_test_mod.addImport("stdx", lib_mod);
    hot_module_test_mod.addOptions("build_options", test_options);

    const hot_module_tests = b.addTest(.{
        .name = "hot-module-test",
        .root_module = hot_module_test_mod,
    });
    hot_module_tests.step.dependOn(&plugin.step);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const run_hot_module_tests = b.addRunArtifact(hot_module_tests);
    run_hot_module_tests.step.dependOn(&plugin.step);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_hot_module_tests.step);
}
