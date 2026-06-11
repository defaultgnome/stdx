const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

/// This ring buffer is defined as empty when head == tail,
/// and full when head + 1 == tail (the snake ate its own tail)
/// that why the real capacity is the desired capacity + 1
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        /// not intended to be used directly
        items: []T,
        capacity: usize,
        /// first item
        head: usize,
        /// last item
        tail: usize,

        pub const empty = Self{
            .items = &.{},
            .capacity = 1, // we must have at least 1 element to work as a 0 container, because of our isFull rule
            .head = 0,
            .tail = 0,
        };

        /// Initialize with externally-managed memory. The buffer determines the
        /// capacity, and the length is set to zero.
        ///
        /// beware that we need n + 1 elements to work as a n container
        pub fn initBuffer(buffer: []T) Self {
            return .{
                .items = buffer,
                .capacity = buffer.len,
                .head = 0,
                .tail = 0,
            };
        }

        const RingBufferError = error{
            RingBufferFull,
            RingBufferEmpty,
            RingBufferIndexOutOfBounds,
        };

        pub fn push(self: *Self, item: T) RingBufferError!void {
            if (self.isFull()) return error.RingBufferFull;
            self.items[self.tail] = item;
            self.tail = self.getTail(1);
        }

        /// remove the last added item
        pub fn pop(self: *Self) RingBufferError!T {
            if (self.isEmpty()) return error.RingBufferEmpty;
            const lastTail = self.getTail(-1);
            const item = self.items[lastTail];
            self.tail = lastTail;
            return item;
        }

        pub fn remove(self: *Self) RingBufferError!void {
            if (self.isEmpty()) return error.RingBufferEmpty;
            self.head = self.getHead(1);
        }

        /// get the item at a given zero-based index
        /// 0 is always the first item at the head
        pub fn get(self: *const Self, index: isize) RingBufferError!T {
            if (self.isEmpty()) return error.RingBufferEmpty;
            const len: isize = @intCast(self.length());
            if (index >= 0) {
                if (index >= len) return error.RingBufferIndexOutOfBounds;
                return self.items[self.getHead(index)];
            } else {
                if (index < -len) return error.RingBufferIndexOutOfBounds;
                return self.items[self.getTail(index)];
            }
        }

        pub fn length(self: *const Self) usize {
            return if (self.tail >= self.head) self.tail - self.head else self.tail + self.items.len - self.head;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.head == self.tail;
        }

        pub fn isFull(self: *const Self) bool {
            return self.getTail(1) == self.head;
        }

        fn getHead(self: *const Self, offset: isize) usize {
            return @intCast(@mod((@as(isize, @intCast(self.head)) +% offset), @as(isize, @intCast(self.capacity))));
        }

        fn getTail(self: *const Self, offset: isize) usize {
            return @intCast(@mod((@as(isize, @intCast(self.tail)) +% offset), @as(isize, @intCast(self.capacity))));
        }
    };
}

test "ring buffer" {
    const Entity = struct {
        id: u64,
    };

    const EntityRingBuffer = RingBuffer(Entity);
    var buffer: [11]Entity = undefined;
    var rb = EntityRingBuffer.initBuffer(buffer[0..]);

    // setup
    try expect(rb.isEmpty());
    try expect(!rb.isFull());
    try expect(rb.length() == 0);

    // first push
    try rb.push(Entity{ .id = 1 });
    try expect(!rb.isEmpty());
    try expect(!rb.isFull());
    try expect(rb.length() == 1);
    {
        const item = try rb.get(0);
        try expect(item.id == 1);
    }
    // fill all
    for (2..11) |i| {
        try rb.push(Entity{ .id = i });
    }
    try expect(rb.isFull());
    try expect(rb.length() == 10);

    // push when full -> error Full
    const err = rb.push(Entity{ .id = 11 });
    try expect(err == error.RingBufferFull);

    // remove
    try rb.remove(); // remove id 1
    try expect(!rb.isFull());
    try expect(rb.length() == 9);
    {
        const item = try rb.get(0);
        try expect(item.id == 2);
    }
    // remove two more, and add two more, so we wrap around
    try rb.remove(); // remove id 2
    try rb.remove(); // remove id 3
    try expect(rb.length() == 7);
    try rb.push(Entity{ .id = 11 });
    try rb.push(Entity{ .id = 12 });
    try expect(rb.length() == 9);
    {
        const item = try rb.get(0);
        try expect(item.id == 4);
    }

    // try and get last - crossing over the edge to wrap around for the last
    const last = try rb.get(-1);
    try expect(last.id == 12);

    // iterate
    for (0..rb.length()) |i| {
        const item = try rb.get(@intCast(i));
        try expect(item.id == i + 4);
    }

    // pop back until empty
    while (!rb.isEmpty()) {
        _ = try rb.pop();
    }
    try expect(rb.isEmpty());
    try expect(rb.length() == 0);
}

test "empty ring buffer" {
    const EntityRingBuffer = RingBuffer(f32);
    var rb = EntityRingBuffer.empty;

    try expect(rb.isEmpty());
    try expect(rb.isFull());
    try expect(rb.length() == 0);

    try expect(rb.get(0) == error.RingBufferEmpty);
    try expect(rb.get(-1) == error.RingBufferEmpty);
    try expect(rb.pop() == error.RingBufferEmpty);
    try expect(rb.remove() == error.RingBufferEmpty);
    try expect(rb.push(1.0) == error.RingBufferFull);
}
