const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

pub const bytes_per_kilobyte = 1024;
pub const bytes_per_megabyte = bytes_per_kilobyte * 1024;
pub const bytes_per_gigabyte = bytes_per_megabyte * 1024;
pub const bytes_per_terabyte = bytes_per_gigabyte * 1024;

/// Repeats the pattern into the data slice.
/// Assert that the data slice is a multiple of the pattern length.
/// Assert that the pattern is not empty.
/// Assert that the data slice is not empty.
pub fn repeatIntoSlice(comptime T: type, data: []T, pattern: []const T) void {
    assert(data.len != 0);
    assert(pattern.len != 0);
    assert(@mod(data.len, pattern.len) == 0);

    for (data, 0..) |*dst, i| {
        const pattern_index = i % pattern.len;
        dst.* = pattern[pattern_index];
    }
}

test repeatIntoSlice {
    var data: [15]u8 = std.mem.zeroes([15]u8);
    repeatIntoSlice(u8, data[0..9], &[_]u8{ 1, 2, 3 });
    try testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 2, 3, 1, 2, 3, 1, 2, 3, 0, 0, 0, 0, 0, 0 },
        &data,
    );
}
