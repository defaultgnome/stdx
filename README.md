# STDX

My personal "Extend Standard" Zig library.

## Install

To add the dependency to your project, you can:

1. Add with `zig fetch --save https://github.com/defaultgnome/stdx.git`
2. Add with `zig fetch --save https://github.com/defaultgnome/stdx/archive/refs/tags/<REPLACE ME>.tar.gz`

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
