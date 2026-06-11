const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opt_hot_reload = b.option(bool, "hotreload", "Enable hot reload (plugin DLL)") orelse (optimize == .Debug);

    const stdx_dep = b.dependency("stdx", .{
        .target = target,
        .optimize = optimize,
    });
    const stdx_mod = stdx_dep.module("stdx");

    const interface_mod = b.createModule(.{
        .root_source_file = b.path("src/interface.zig"),
        .target = target,
        .optimize = optimize,
    });

    const plugin_mod_simple = b.createModule(.{
        .root_source_file = b.path("src/plugin/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    var plugin_mod = plugin_mod_simple;
    var dll_compile: ?*std.Build.Step.Compile = null;

    if (opt_hot_reload) {
        const plugin_dll_mod = b.createModule(.{
            .root_source_file = b.path("src/plugin/+dll.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plugin", .module = plugin_mod_simple },
                .{ .name = "interface", .module = interface_mod },
            },
        });

        const plugin_dll = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "plugin",
            .root_module = plugin_dll_mod,
        });
        b.installArtifact(plugin_dll);
        dll_compile = plugin_dll;

        const plugin_dll_options = b.addOptions();
        const plugin_dll_rel_path = path: {
            if (target.result.os.tag.isDarwin()) {
                break :path try std.fs.path.join(b.allocator, &.{ "..", "lib", plugin_dll.out_filename });
            } else {
                break :path plugin_dll.out_filename;
            }
        };
        plugin_dll_options.addOption([]const u8, "dll_path", plugin_dll_rel_path);
        plugin_dll_options.addOption([]const u8, "dll_exported_symbol", "dll_interface");

        plugin_mod = b.createModule(.{
            .root_source_file = b.path("src/plugin/+hot_module.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "plugin", .module = plugin_mod_simple },
                .{ .name = "interface", .module = interface_mod },
                .{ .name = "options", .module = plugin_dll_options.createModule() },
                .{ .name = "stdx", .module = stdx_mod },
            },
        });
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "plugin", .module = plugin_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "hot_module_demo",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the demo").dependOn(&run_cmd.step);

    if (dll_compile) |dll| {
        const compile_dll_step = b.step("compile_dll", "Install the plugin DLL");
        compile_dll_step.dependOn(&b.addInstallArtifact(dll, .{}).step);
    }
}
