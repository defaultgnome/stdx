const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const threads = try std.Thread.spawn(.{}, worker, .{init.io});
    std.debug.print("[MAIN] Hello\n", .{});
    defer threads.join();
}

fn worker(io: std.Io) void {
    for (0..3) |i| {
        std.Io.sleep(
            io,
            std.Io.Duration.fromMilliseconds(1000),
            std.Io.Clock.real,
        ) catch {
            std.debug.print("[WORKER] Failed to sleep\n", .{});
        };
        std.debug.print("[WORKER] Hello {d}\n", .{i});
    }
}
