//! Hot-reload wrapper. In Release builds, `build.zig` links `root.zig` directly instead.
const std = @import("std");
const HotModule = @import("stdx").HotModule;
const options = @import("options");
const interface = @import("interface");

const dll_exported_symbol: [:0]const u8 = options.dll_exported_symbol ++ "";
const PluginHotModule = HotModule(interface.Interface, dll_exported_symbol);
var hot_module: PluginHotModule = undefined;

var aa: std.heap.ArenaAllocator = undefined;
var threaded: std.Io.Threaded = undefined;

pub fn init() void {
    aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = aa.allocator();
    threaded = std.Io.Threaded.init(allocator, .{});

    hot_module = PluginHotModule.initFromExecutableDir(allocator, threaded.io(), options.dll_path) catch {
        std.log.err("Failed to init plugin DLL", .{});
        unreachable;
    };
    hot_module.load() catch {
        std.log.err("Failed to load plugin DLL", .{});
        unreachable;
    };
    std.log.info("Plugin DLL loaded", .{});
}

pub fn deinit() void {
    hot_module.unload() catch {
        std.log.err("Failed to unload plugin DLL", .{});
        unreachable;
    };
    hot_module.deinit();
    std.log.info("Plugin DLL unloaded", .{});

    threaded.deinit();
    aa.deinit();
}

pub fn transform(frame: u64) u64 {
    if (hot_module.reload() catch false) {
        std.log.info("Plugin DLL reloaded", .{});
    }
    if (hot_module.api) |iface| {
        return iface.transform(frame);
    }
    std.log.err("Failed to get plugin interface", .{});
    return 0;
}
