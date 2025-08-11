const std = @import("std");
const testing = std.testing;

pub const time = @import("time.zig");
pub const mem = @import("mem.zig");

test {
    testing.refAllDecls(@This());
}
