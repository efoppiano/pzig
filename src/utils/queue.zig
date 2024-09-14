const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        const TailQueueType = std.TailQueue(T);

        unsafe_queue: TailQueueType,
        lock: std.Thread.Mutex,
        allocator: Allocator,
        not_empty: std.Thread.Semaphore,

        pub fn init_ptr(self: *Self, allocator: Allocator) void {
            self.unsafe_queue = TailQueueType{};
            self.lock = std.Thread.Mutex{};
            self.allocator = allocator;
            self.not_empty = std.Thread.Semaphore{};
        }

        pub fn init(allocator: Allocator) Self {
            const not_empty = std.Thread.Semaphore{};
            const unsafe_queue = TailQueueType{};
            return Self{
                .unsafe_queue = unsafe_queue,
                .lock = std.Thread.Mutex{},
                .allocator = allocator,
                .not_empty = not_empty,
            };
        }

        pub fn destroy(self: *Self) void {
            while (self.unsafe_queue.popFirst()) |node| {
                self.allocator.destroy(node);
            }
        }

        fn append(self: *Self, value: T) !void {
            var new_node = try self.allocator.create(TailQueueType.Node);
            new_node.data = value;

            self.lock.lock();
            self.unsafe_queue.append(new_node);
            self.lock.unlock();
        }

        pub fn push(self: *Self, value: T) !void {
            var new_node = try self.allocator.create(TailQueueType.Node);
            new_node.data = value;

            self.lock.lock();
            self.unsafe_queue.append(new_node);
            self.lock.unlock();

            self.not_empty.post();
        }

        fn remove(self: *Self) T {
            self.lock.lock();
            if (self.unsafe_queue.popFirst()) |node| {
                defer self.allocator.destroy(node);
                self.lock.unlock();
                return node.data;
            }
            self.lock.unlock();
            std.debug.panic("Queue is empty", .{});
        }

        pub fn pop(self: *Self) T {
            self.not_empty.wait();
            const value = self.remove();
            return value;
        }
    };
}
