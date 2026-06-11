//! Hot-reload dynamic library host.
//!
//! Copies the built `.so`/`.dylib`/`.dll` to a unique sibling filename, loads the copy,
//! and watches the **original** path mtime — rebuild can overwrite the original while
//! the host still holds the copy open.
//!
//! Contract:
//! - Shared `extern struct` of `callconv(.c)` fn pointers (same layout in exe + plugin).
//! - Plugin exports one symbol, e.g. `export const api = API{ ... };`.
//! - `HotModule(API, "api")` — second arg must match export name.
//! - All I/O via `std.Io` (Zig 0.16+).
//!
//! Build: dynamic library + `addOptionPath("plugin_lib_path", plugin.getEmittedBin())` for dev;
//! ship with `initFromExecutableDir` + relative filename beside the exe.
const std = @import("std");
const DynLib = @import("./dyn_lib.zig").DynLib;

const Dir = std.Io.Dir;
const Io = std.Io;

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
        /// Last loaded mtime of `lib_path_original`; `.zero` = no copy loaded.
        timestamp_working_copy: Io.Timestamp = .zero,
        lib: ?DynLib = null,
        api: ?*const API = null,

        // ==== HIGH LEVEL API ====
        /// Dev path — typically `@import("build_options").plugin_lib_path`.
        pub fn init(allocator: std.mem.Allocator, io: Io, lib_absolute_path: []const u8) !Self {
            const self = Self{
                .allocator = allocator,
                .io = io,
                .lib_path_original = try allocator.dupe(u8, lib_absolute_path),
            };
            return self;
        }

        /// Shipped layout — `lib_relative_path` relative to exe dir (e.g. `"libmy_plugin.dylib"`).
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

        pub fn load(self: *Self) !void {
            try self.createCopy();
            try self.loadLib();
        }

        pub fn unload(self: *Self) !void {
            self.unloadLib();
            try self.deleteCopy();
        }

        /// Reload only when **original** file mtime changed; returns whether reload ran.
        pub fn reload(self: *Self) !bool {
            if (!try self.hasLibChanged()) return false;

            try self.unload();
            try self.load();
            return true;
        }

        // ==== LOW LEVEL API ====
        /// Open working copy (or original); resolve `symbol_name`. Asserts not already loaded.
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

        /// Unique `{timestamp}_{basename}` in same dir as original. One copy at a time.
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
            const new_path_z = try dir.realPathFileAlloc(self.io, tmp_basename, self.allocator);
            defer self.allocator.free(new_path_z);
            self.lib_path_working_copy = try self.allocator.dupe(u8, new_path_z);
        }

        /// No-op if no copy. On Windows: must unload first else delete fails (file still mapped).
        pub fn deleteCopy(self: *Self) !void {
            if (self.lib_path_working_copy) |path| {
                try Dir.deleteFileAbsolute(self.io, path);
                self.allocator.free(path);
                self.lib_path_working_copy = null;
            }
        }

        /// Compare `lib_path_original` mtime to last `loadLib` snapshot.
        /// TODO: maybe sample multiple times and wait for stability?
        pub fn hasLibChanged(self: *Self) !bool {
            const lib_timestamp = try self.getLibTimestamp();
            return lib_timestamp.nanoseconds != self.timestamp_working_copy.nanoseconds;
        }

        // ==== INTERNAL ====
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

        fn getLibTimestamp(self: *Self) !Io.Timestamp {
            const file = try Dir.openFileAbsolute(self.io, self.lib_path_original, .{});
            defer file.close(self.io);
            const file_stat = try file.stat(self.io);
            return file_stat.mtime;
        }
    };
}
