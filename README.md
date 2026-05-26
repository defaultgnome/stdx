# STDX

My personal Standard "Extended" Zig Library.

I take the liberty to break everything, you better just copy or fork the part you need.

## Versions

`main` branch use zig version 0.16.0, see tags for other versions (not maintained)

## Install

To add the dependency to your project, you can:

1. Add with `zig fetch --save git+https://github.com/defaultgnome/stdx.git`
2. Add with `zig fetch --save git+https://github.com/defaultgnome/stdx/archive/refs/tags/<REPLACE ME>.tar.gz`

```zig
const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build) !void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const dep_stdx = b.dependency("stdx", .{
      .target = target,
      .optimize = optimize,
  });

  // Your App
  const hello = b.addExecutable(.{
      .name = "hello",
      .target = target,
      .optimize = optimize,
      .root_source_file = b.path("src/hello.zig"),
  });
  hello.root_module.addImport("stdx", dep_stdx.module("stdx"));
  b.installArtifact(hello);

  const run = b.addRunArtifact(hello);
  b.step("run", "Run hello").dependOn(&run.step);
}
```

## Usage

### Hot Module

`HotModule` loads a dynamic library, keeps a writable copy beside the original (so the linker can reload while the file on disk is rebuilt), and exposes your plugin API through a single exported symbol.

Requirements:

- Zig **0.16.0** (uses `std.Io` for filesystem operations).
- Plugin functions use **`callconv(.c)`**.
- The API type is an **`extern struct`** of function pointers (same layout in the executable and the `.so` / `.dylib` / `.dll`).
- The plugin exports one value, usually `export const api = ...`.

#### 1. Shared API struct

Create a small file both the executable and the plugin import, for example `src/plugin_api.zig`:

```zig
pub const API = extern struct {
    add: *const fn (i32, i32) callconv(.c) i32,
    greet: *const fn ([*:0]const u8) callconv(.c) void,
};
```

Every field must be a C-callable function pointer. The struct must be `extern` so the layout matches what the dynamic loader expects.

#### 2. Plugin module (dynamic library root)

Create `src/plugin.zig` (name is up to you). Implement the functions with C calling convention and export the API table:

```zig
const API = @import("plugin_api").API;

fn add(a: i32, b: i32) callconv(.c) i32 {
    return a + b;
}

fn greet(name: [*:0]const u8) callconv(.c) void {
    const std = @import("std");
    std.debug.print("Hello, {s}!\n", .{name});
}

/// Symbol name must match the second parameter of `HotModule(API, "api")`.
export const api = API{
    .add = add,
    .greet = greet,
};
```

Rebuild the plugin after code changes; call `reload()` in the host to pick up a new copy.

#### 3. `build.zig`: modules, dynamic library, path injection

Wire the plugin as a **dynamic library** and pass its path into the executable with `addOptions` / `addOptionPath` (resolved when the build runs):

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_stdx = b.dependency("stdx", .{
        .target = target,
        .optimize = optimize,
    });

    const plugin_api_mod = b.createModule(.{
        .root_source_file = b.path("src/plugin_api.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Plugin (hot-reloadable dynamic library) ---
    const plugin_mod = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_mod.addImport("plugin_api", plugin_api_mod);

    const plugin = b.addLibrary(.{
        .name = "my_plugin",
        .linkage = .dynamic,
        .root_module = plugin_mod,
    });

    // --- Host executable ---
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("stdx", dep_stdx.module("stdx"));
    exe_mod.addImport("plugin_api", plugin_api_mod);

    const options = b.addOptions();
    options.addOptionPath("plugin_lib_path", plugin.getEmittedBin());
    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_module = exe_mod,
    });
    exe.step.dependOn(&plugin.step);

    b.installArtifact(exe);
    b.installArtifact(plugin);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run the app").dependOn(&run.step);
}
```

`addOptionPath` records the built artifact path (under `.zig-cache/...`) into `build_options.plugin_lib_path`. The executable reads it via `@import("build_options")`.

For distribution, install the `.so` / `.dylib` / `.dll` next to your executable and use `initFromExecutableDir` with a **relative** filename instead of the compile-time cache path.

#### 4. Main executable: `HotModule` + injected path

In `src/main.zig`:

```zig
const std = @import("std");
const stdx = @import("stdx");
const API = @import("plugin_api").API;
const build_options = @import("build_options");

const PluginHost = stdx.HotModule(API, "api");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var host = try PluginHost.init(allocator, io, build_options.plugin_lib_path);
    defer host.deinit();

    // See “High level” vs “Low level” below.
    try host.load();
    defer host.unload() catch {};

    if (host.api) |api| {
        _ = api.add(2, 40);
        api.greet("world");
    }

    // After rebuilding the plugin on disk:
    if (try host.reload()) {
        std.debug.print("Plugin reloaded\n", .{});
    }
}
```

- First type argument: your `extern struct` API.
- Second argument: exported symbol name (`"api"` → `export const api`).
- Path: absolute path from `build_options`, or `initFromExecutableDir(allocator, io, "libmy_plugin.dylib")` when the library sits beside the binary.

You need an `std.Io` instance (`init.io` in a normal `main`); all file operations inside `HotModule` use it.

#### 5. High level vs low level API

**High level** (copy + load + reload + cleanup):

| Method | Purpose |
|--------|---------|
| `load()` | `createCopy()` then `loadLib()` |
| `unload()` | `unloadLib()` then `deleteCopy()` |
| `reload()` | If the **original** file mtime changed, `unload()` + `load()`; returns whether a reload happened |

**Low level** (manual steps):

| Method | Purpose |
|--------|---------|
| `createCopy()` | Copy the library to a unique name in the same directory |
| `loadLib()` | Open the working copy (or original) and resolve `api` |
| `unloadLib()` | Close the library |
| `deleteCopy()` | Remove the working copy file |
| `hasLibChanged()` | Compare original file mtime to last loaded mtime |

Example using only the low-level API:

```zig
try host.createCopy();
try host.loadLib();
defer host.unloadLib();
defer host.deleteCopy() catch {};

if (host.api) |api| {
    api.greet("from copy");
}
```
