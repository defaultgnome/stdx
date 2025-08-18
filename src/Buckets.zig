//! the idea of a Buckets data structure is to store
//! an hashmap of linked-list of values
//! so like that collision are solved by storing all values
//! with the same key, this mean that getting a value is not O(1)
//! but it is O(n) where n is the number of values with the same key
//!
//! This implementation gets an allocate each time it need a new node for a linked-list
//! you can pass a FixedBufferAllocator to essencialy avoid allocating
const std = @import("std");
const testing = std.testing;

pub fn Buckets(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const LinkedListHashMap = std.AutoHashMap(K, std.SinglyLinkedList(V));

        allocator: std.mem.Allocator,
        map: LinkedListHashMap,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .map = LinkedListHashMap.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // FIXME: we should pass here `memory`
            // self.allocator.free(self);
            self.map.deinit();
        }
    };
}

test "Buckets" {
    const Point = struct {
        x: f32,
        y: f32,
    };

    const Entity = struct {
        id: u32,
        name: []const u8,
        position: Point,
        type: Type,

        const Type = enum {
            Chest,
            Torch,
        };
    };

    var buffer: [12 * @sizeOf(Entity)]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const PointToEntitiesBuckets = Buckets(Point, Entity);
    var buckets = PointToEntitiesBuckets.init(allocator);
    buckets.map.put(
        .{ .x = 0, .y = 0 },
        .{
            .id = 1,
            .name = "chest",
            .position = .{ .x = 0, .y = 0 },
            .type = Entity.Type.Chest,
        },
    );
    try testing.expectEqual(buckets.map.count(), 1);
    try testing.expectEqual(buckets.map.get(.{ .x = 0, .y = 0 }).?.id, 1);
    buckets.deinit();
}
