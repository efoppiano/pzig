const std = @import("std");
const testing = std.testing;
const pzig = @import("lib.zig");

fn add_one(x: i32) i32 {
    return x + 1;
}

test "Stateless Similar Map works with 1 thread, batch_size=1 and input array of 1 element" {
    const allocator = testing.allocator;
    const input_array = [_]i32{1};
    const config = .{ .allocator = allocator, .batch_size = 1, .n_threads = 1 };
    var pmap = try pzig.BasicMap(i32).init(config);

    const result = try pmap.map_alloc(add_one, &input_array);
    defer allocator.free(result);

    defer pmap.destroy() catch |err| {
        std.debug.print("Failed to destroy pmap: {}\n", .{err});
    };

    try testing.expectEqual(1, result.len);
    try testing.expectEqual(2, result[0]);
}
