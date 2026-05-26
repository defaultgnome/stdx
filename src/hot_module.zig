const std = @import("std");
const DynLib = @import("./dyn_lib.zig").DynLib;

const Dir = std.Io.Dir;
const Io = std.Io;

/// HotModule is a wrapper around a dynamic library that facilitates for hot reloading.
/// Your module should export a single struct with the API you want to expose. Pass the struct type as a template parameter.
pub fn HotModule(comptime API: type, comptime symbol_name: [:0]const u8) type {
    if (@typeInfo(API) != .@"struct") {
        @compileError("API must be a struct");
    }
    if (@typeInfo(API).@"struct".layout != .@"extern") {
        @compileError("API must be an extern struct");
    }

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        io: Io,
        lib_path_original: []const u8,
        lib_path_working_copy: ?[]const u8 = null,
        /// Zero means no copy exists.
        timestamp_working_copy: Io.Timestamp = .zero,
        lib: ?DynLib = null,
        api: ?*const API = null,

        //------------------------
        //-----HIGH LEVEL API-----
        //------------------------

        /// lib_absolute_path should be an absolute path to the library
        /// the path will be duplicated and stored in the struct
        pub fn init(allocator: std.mem.Allocator, io: Io, lib_absolute_path: []const u8) !Self {
            const self = Self{
                .allocator = allocator,
                .io = io,
                .lib_path_original = try allocator.dupe(u8, lib_absolute_path),
            };
            return self;
        }

        /// lib_relative_path should be relative to the executable directory
        /// the path will be duplicated and stored in the struct
        pub fn initFromExecutableDir(allocator: std.mem.Allocator, io: Io, lib_relative_path: []const u8) !Self {
            const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
            defer allocator.free(exe_dir);
            const lib_path = try Dir.path.join(allocator, &.{ exe_dir, lib_relative_path });
            defer allocator.free(lib_path);
            return Self.init(allocator, io, lib_path);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.lib_path_original);
            if (self.lib_path_working_copy) |path| {
                self.allocator.free(path);
            }
        }

        /// create a copy of the library and load it
        pub fn load(self: *Self) !void {
            try self.createCopy();
            try self.loadLib();
        }

        /// unload the library and delete the copy
        pub fn unload(self: *Self) !void {
            self.unloadLib();
            try self.deleteCopy();
        }

        /// unload the library and load it again only if the library has changed
        /// return true if the library was reloaded
        pub fn reload(self: *Self) !bool {
            if (!try self.hasLibChanged()) return false;

            try self.unload();
            try self.load();
            return true;
        }

        //------------------------
        //-----LOW LEVEL API-----
        //------------------------

        /// load the library from the working copy if exists, else from the original path
        /// lookup for symbol_name in the library
        /// assert that the library is not already loaded
        pub fn loadLib(self: *Self) !void {
            std.debug.assert(self.lib == null);
            const lib_to_load = self.lib_path_working_copy orelse self.lib_path_original;
            var lib = try DynLib.open(lib_to_load);

            self.timestamp_working_copy = try self.getLibTimestamp();

            self.api = lib.lookup(*const API, symbol_name) orelse {
                return error.SymbolNotFound;
            };
            self.lib = lib;
        }

        pub fn unloadLib(self: *Self) void {
            if (self.lib) |*lib| {
                lib.close();
            }
            self.timestamp_working_copy = .zero;
            self.lib = null;
            self.api = null;
        }

        pub fn hasCopy(self: *Self) bool {
            return self.lib_path_working_copy != null;
        }

        /// Can't be called twice in a row,
        /// must delete the previous copy if exists before creating a new one
        pub fn createCopy(self: *Self) !void {
            std.debug.assert(!self.hasCopy());
            const timestamp = Io.Timestamp.now(self.io, .real).toNanoseconds();
            const lib_basename = Dir.path.basename(self.lib_path_original);
            const tmp_basename = try std.fmt.allocPrint(
                self.allocator,
                "{d}_{s}",
                .{ timestamp, lib_basename },
            );
            defer self.allocator.free(tmp_basename);

            var dir = try self.getLibDir();
            defer dir.close(self.io);
            try dir.copyFile(lib_basename, dir, tmp_basename, self.io, .{});
            const new_path = try dir.realPathFileAlloc(self.io, tmp_basename, self.allocator);
            self.lib_path_working_copy = new_path;
        }

        /// delete the copy of the library only if exists, else do nothing
        pub fn deleteCopy(self: *Self) !void {
            if (self.lib_path_working_copy) |path| {
                try Dir.deleteFileAbsolute(self.io, path);
                self.allocator.free(path);
                self.lib_path_working_copy = null;
            }
        }

        /// check if the library file has changed since the last time it was loaded
        pub fn hasLibChanged(self: *Self) !bool {
            const lib_timestamp = try self.getLibTimestamp();
            return lib_timestamp.nanoseconds != self.timestamp_working_copy.nanoseconds;
        }

        //-------------------
        //-----INTERNAL------
        //-------------------

        /// get the directory where the library file is located
        fn getLibDir(self: Self) !Dir {
            const maybe_lib_dir = Dir.path.dirname(self.lib_path_original);
            const dir = dir: {
                if (maybe_lib_dir) |dir_path| {
                    break :dir try Dir.cwd().openDir(self.io, dir_path, .{});
                } else {
                    break :dir Dir.cwd();
                }
            };
            return dir;
        }

        /// get the last modification timestamp of the library file
        fn getLibTimestamp(self: *Self) !Io.Timestamp {
            const file = try Dir.openFileAbsolute(self.io, self.lib_path_original, .{});
            defer file.close(self.io);
            const file_stat = try file.stat(self.io);
            return file_stat.mtime;
        }
    };
}

// TODO: make those tests work with a mock library or something
test "HotModule - High Level API" {
    if (true) {
        return error.SkipZigTest;
    }
    const API = extern struct {
        foo: *const fn () callconv(.c) void,
    };
    const APIHotModule = HotModule(API, "api");
    const test_lib_path = "test.so";

    var hot_module = try APIHotModule.initFromExecutableDir(
        std.testing.allocator,
        std.testing.io,
        test_lib_path,
    );

    try hot_module.load();
    try std.testing.expect(hot_module.api != null);

    _ = try hot_module.reload();
    try std.testing.expect(hot_module.api != null);

    try hot_module.unload();
    try std.testing.expect(hot_module.api == null);

    hot_module.deinit();
}

test "HotModule - Low Level API" {
    if (true) {
        return error.SkipZigTest;
    }
    const API = extern struct {
        foo: *const fn () callconv(.c) void,
    };
    const APIHotModule = HotModule(API, "api");
    const test_lib_path = try Dir.cwd().realPathFileAlloc(
        std.testing.io,
        "mylib.dll",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(test_lib_path);

    var hot_module = try APIHotModule.init(
        std.testing.allocator,
        std.testing.io,
        test_lib_path,
    );
    try hot_module.createCopy();
    try hot_module.loadLib();
    if (hot_module.api) |api| {
        api.foo();
    }
    hot_module.unloadLib();
    try hot_module.deleteCopy();
    hot_module.deinit();
}
