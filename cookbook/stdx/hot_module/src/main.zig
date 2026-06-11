const std = @import("std");
const plugin = @import("plugin");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    plugin.init();
    defer plugin.deinit();

    var frame: u64 = 0;
    while (true) {
        const result = plugin.transform(frame);
        std.debug.print("frame {d} -> {d}\n", .{ frame, result });
        frame += 1;
        try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);
    }
}
