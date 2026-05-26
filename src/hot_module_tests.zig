//! NOTE: vibe coded, so i don't know what this is worth right now
const std = @import("std");
const stdx = @import("stdx");
const build_options = @import("build_options");

const testing = std.testing;
const HotModule = stdx.HotModule;
const Dir = std.Io.Dir;
const Io = std.Io;

const TestAPI = extern struct {
    increaseCallCount: *const fn () callconv(.c) void,
    getCallCount: *const fn () callconv(.c) u32,
};

const TestHotModule = HotModule(TestAPI, "api");

fn pluginLibPathAlloc(allocator: std.mem.Allocator, io: Io) ![]const u8 {
    const path = build_options.plugin_lib_path;
    if (Dir.path.isAbsolute(path)) return allocator.dupe(u8, path);
    const path_z = try Dir.cwd().realPathFileAlloc(io, path, allocator);
    defer allocator.free(path_z);
    return allocator.dupe(u8, path_z);
}

fn bumpLibMtime(io: Io, lib_absolute_path: []const u8) !void {
    var file = try Dir.openFileAbsolute(io, lib_absolute_path, .{ .mode = .read_write });
    defer file.close(io);
    try file.setTimestampsNow(io);
}

fn copyPluginBesideExecutable(
    allocator: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
) ![]const u8 {
    const basename = Dir.path.basename(src_path);
    const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(exe_dir);
    const dest_path = try Dir.path.join(allocator, &.{ exe_dir, basename });
    if (std.mem.eql(u8, src_path, dest_path)) return dest_path;

    var src_parent = try Dir.cwd().openDir(io, Dir.path.dirname(src_path).?, .{});
    defer src_parent.close(io);
    var dest_parent = try Dir.cwd().openDir(io, exe_dir, .{});
    defer dest_parent.close(io);
    try src_parent.copyFile(Dir.path.basename(src_path), dest_parent, basename, io, .{ .replace = true });
    return dest_path;
}

test "loadLib opens plugin and resolves api" {
    const allocator = testing.allocator;
    const io = testing.io;
    const lib_path = try pluginLibPathAlloc(allocator, io);
    defer allocator.free(lib_path);

    var hot_module = try TestHotModule.init(allocator, io, lib_path);
    defer hot_module.deinit();

    try hot_module.loadLib();
    defer hot_module.unloadLib();

    const api = hot_module.api orelse return error.TestExpectedEqual;
    const count_before = api.getCallCount();
    api.increaseCallCount();
    try testing.expect(api.getCallCount() == count_before + 1);
}

test "createCopy loadLib deleteCopy" {
    const allocator = testing.allocator;
    const io = testing.io;
    const lib_path = try pluginLibPathAlloc(allocator, io);
    defer allocator.free(lib_path);

    var hot_module = try TestHotModule.init(allocator, io, lib_path);
    defer hot_module.deinit();

    try hot_module.createCopy();
    try testing.expect(hot_module.hasCopy());

    try hot_module.loadLib();
    try testing.expect(hot_module.api != null);
    hot_module.unloadLib();

    try hot_module.deleteCopy();
    try testing.expect(!hot_module.hasCopy());
}

test "hasLibChanged and reload" {
    const allocator = testing.allocator;
    const io = testing.io;
    const lib_path = try pluginLibPathAlloc(allocator, io);
    defer allocator.free(lib_path);

    var hot_module = try TestHotModule.init(allocator, io, lib_path);
    defer hot_module.deinit();

    try hot_module.load();
    defer hot_module.unload() catch {};

    try testing.expect(!try hot_module.hasLibChanged());
    try testing.expect(!try hot_module.reload());

    try bumpLibMtime(io, lib_path);
    try testing.expect(try hot_module.hasLibChanged());

    const reloaded = try hot_module.reload();
    try testing.expect(reloaded);
    try testing.expect(hot_module.api != null);

    const api = hot_module.api orelse return error.TestExpectedEqual;
    api.increaseCallCount();
    try testing.expect(api.getCallCount() > 0);
}

test "high level load unload" {
    const allocator = testing.allocator;
    const io = testing.io;
    const lib_path = try pluginLibPathAlloc(allocator, io);
    defer allocator.free(lib_path);

    var hot_module = try TestHotModule.init(allocator, io, lib_path);
    defer hot_module.deinit();

    try hot_module.load();
    try testing.expect(hot_module.api != null);

    try hot_module.unload();
    try testing.expect(hot_module.api == null);
    try testing.expect(!hot_module.hasCopy());
}

test "initFromExecutableDir loads library beside test executable" {
    const allocator = testing.allocator;
    const io = testing.io;
    const src_path = try pluginLibPathAlloc(allocator, io);
    defer allocator.free(src_path);
    const basename = Dir.path.basename(src_path);

    const dest_path = try copyPluginBesideExecutable(allocator, io, src_path);
    defer if (!std.mem.eql(u8, src_path, dest_path)) allocator.free(dest_path);
    defer if (!std.mem.eql(u8, src_path, dest_path)) {
        Dir.deleteFileAbsolute(io, dest_path) catch {};
    };

    var hot_module = try TestHotModule.initFromExecutableDir(allocator, io, basename);
    defer hot_module.deinit();

    try hot_module.load();
    defer hot_module.unload() catch {};

    const api = hot_module.api orelse return error.TestExpectedEqual;
    const count_before = api.getCallCount();
    api.increaseCallCount();
    try testing.expect(api.getCallCount() == count_before + 1);
}
