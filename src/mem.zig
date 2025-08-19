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

/// copy a window from `src` into a matching window in `dest`.
pub fn copy2dSlice(
    comptime T: type,
    dest: []T,
    dest_width: usize,
    dest_x: usize,
    dest_y: usize,
    src: []T,
    src_width: usize,
    src_height: usize,
    src_x: usize,
    src_y: usize,
) void {
    for (0..src_height) |y| {
        const dest_row_start = (dest_y + y) * dest_width + dest_x;
        const src_row_start = (src_y + y) * src_width + src_x;
        @memcpy(dest[dest_row_start .. dest_row_start + src_width], src[src_row_start .. src_row_start + src_width]);
    }
}

test copy2dSlice {
    var dest: [100]u8 = undefined;
    const dest_width = 10;
    const dest_x = 2;
    const dest_y = 3;
    const src_width = 3;
    const src_height = 3;
    var src: [src_width * src_height]u8 = undefined;
    for (0..src.len) |i| {
        src[i] = @intCast(i + 1);
    }
    copy2dSlice(
        u8,
        &dest,
        dest_width,
        dest_x,
        dest_y,
        &src,
        src_width,
        src_height,
        0,
        0,
    );

    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, dest[32..35]);
    try testing.expectEqualSlices(u8, &.{ 4, 5, 6 }, dest[42..45]);
    try testing.expectEqualSlices(u8, &.{ 7, 8, 9 }, dest[52..55]);
}
