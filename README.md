# pzig

A simple data parallelism library for Zig.

This library is a work in progress and is not suitable for production use. Any feedback is welcome.

## Using the library

### Zigmod

Install the library using [zigmod](https://github.com/nektro/zigmod/)

```bash
zigmod aq add 1/efoppiano/pzig
```

Then import the library in your project

```zig
const pzig = @import("pzig");
```

### Examples

#### BasicMap

The simplest way to apply a function to an array in parallel is to use the `BasicMap` struct.

```zig
const std = @import("std");
const pzig = @import("pzig");

// Function to be applied to each element of the input array.
// Both the input and output types must be the same.
fn add_one(x: i32) i32 {
    return x + 1;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const config = .{ .allocator = allocator, .batch_size = 2, .n_threads = 4 };
    var pmap = try pzig.BasicMap(i32).init(config);

    const input_array = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const result = try pmap.map_alloc(add_one, &input_array);
    defer allocator.free(result);

    std.debug.print("Result: {any}\n", .{result});
    try pmap.destroy();
}
```

#### NoContextMap

If the input and output types are not the same, but the function does not require any context, you can use the `NoContextMap` struct.

```zig
const std = @import("std");
const pzig = @import("pzig");

// Function to be applied to each element of the input array.
// The only parameter is the input element.
// The input and output types can be different.
fn is_even(x: u32) bool {
    return x % 2 == 0;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const config = .{ .allocator = allocator, .batch_size = 2, .n_threads = 4 };
    var pmap = try pzig.NoContextMap(u32, bool).init(config);

    const input_array = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const result = try pmap.map_alloc(is_even, &input_array);
    defer allocator.free(result);

    std.debug.print("Result: {any}\n", .{result});
    try pmap.destroy();
}
```

#### ParallelMap

If you need to pass a context to the function, you can use the `ParallelMap` struct.

**Warning**: the context **must** be thread-safe, as it will be shared among all threads.


```zig
const std = @import("std");
const pzig = @import("pzig");

const Allocator = std.mem.Allocator;

// Function to be applied to each element of the input array.
// The first parameter is the context.
fn greet(allocator: *const Allocator, guest: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator.*, "Hello, {s}!", .{guest});
}

pub fn main() !void {
    // GeneralPurposeAllocator is thread-safe, so it can be used as the context.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const config = .{ .allocator = allocator, .batch_size = 2, .n_threads = 4 };
    const ReturnType = @typeInfo(@TypeOf(greet)).Fn.return_type.?; // ![]const u8
    var pmap = try pzig.ParallelMap([]const u8, ReturnType, Allocator).init(config);

    const input_array = [_][]const u8{ "Alice", "Bob", "Charlie", "David", "Eve" };
    const result = try pmap.map_alloc(&allocator, greet, &input_array);
    defer {
        for (result) |g| {
            const greeting = g catch {
                continue;
            };
            allocator.free(greeting);
        }
        allocator.free(result);
    }

    std.debug.print("Result:\n", .{});
    for (result) |greeting| {
        std.debug.print("{s}\n", .{try greeting});
    }
    try pmap.destroy();
}
```

## Compatibility

This library is compatible with **Zig 0.13.0**
