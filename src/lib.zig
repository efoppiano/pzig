pub const std = @import("std");
pub const Thread = std.Thread;
pub const Queue = @import("utils/queue.zig").Queue;
pub const Message = @import("utils/message.zig").Message;
pub const EmptyMessage = @import("utils/message.zig").EmptyMessage;
pub const DataWithFn = @import("utils/message.zig").DataWithFn;
pub const initiate_worker = @import("utils/worker.zig").initiate_worker;
pub const Worker = @import("utils/worker.zig").Worker;

const c = @cImport({
    @cInclude("sys/sysinfo.h");
});

pub const Config = struct { n_threads: ?usize = null, batch_size: usize = 1, allocator: std.mem.Allocator };

pub fn ParallelMap(comptime R: type, comptime S: type, comptime Ctx: type) type {
    return struct {
        pub const Self = @This();
        const Data = DataWithFn(Ctx, R, S);
        pub const MessageInput = Message(Data);
        pub const MessageOutput = EmptyMessage;

        threads: []Thread,
        workers: []Worker(R, S, Ctx),
        input_queue: *Queue(MessageInput),
        output_queue: *Queue(MessageOutput),
        allocator: std.mem.Allocator,
        batch_size: usize,

        pub fn init(config: Config) !Self {
            const n_threads: usize = if (config.n_threads != null) config.n_threads.? else @intCast(c.get_nprocs());

            var threads = try config.allocator.alloc(Thread, n_threads);
            var workers = try config.allocator.alloc(Worker(R, S, Ctx), n_threads);

            var input_queue = try config.allocator.create(Queue(MessageInput));
            var output_queue = try config.allocator.create(Queue(MessageOutput));

            input_queue.init_ptr(config.allocator);
            output_queue.init_ptr(config.allocator);

            for (0..n_threads) |i| {
                workers[i] = Worker(R, S, Ctx).init(input_queue, output_queue);
                threads[i] = try initiate_worker(R, S, Ctx, &workers[i]);
            }

            return Self{
                .threads = threads,
                .workers = workers,
                .input_queue = input_queue,
                .output_queue = output_queue,
                .allocator = config.allocator,
                .batch_size = config.batch_size,
            };
        }

        pub fn destroy(self: *Self) !void {
            for (0..self.threads.len) |_| {
                try self.input_queue.push(MessageInput.init_eof());
            }
            for (self.threads) |thread| {
                thread.join();
            }
            self.input_queue.destroy();
            self.output_queue.destroy();
            self.allocator.destroy(self.input_queue);
            self.allocator.destroy(self.output_queue);
            self.allocator.free(self.threads);
            self.allocator.free(self.workers);
        }

        /// Returns the amount of created batches
        fn send_messages(self: *Self, ctx: *const Ctx, func: *const fn (*const Ctx, R) S, input: []const R, results: []S) !usize {
            var next_pos: u64 = 0;
            var input_pos: usize = 0;

            while (input_pos < input.len) {
                const actual_batch_size = @min(self.batch_size, input.len - input_pos);
                const input_slice = input[input_pos .. input_pos + actual_batch_size];
                const results_slice = results[input_pos .. input_pos + actual_batch_size];
                const message = MessageInput.init(Data.init(input_slice, func, ctx, results_slice));
                input_pos += actual_batch_size;
                next_pos += 1;
                try self.input_queue.push(message);
            }
            return next_pos;
        }

        fn send_messages_stateless(self: *Self, func: *const fn (R) S, input: []const R, results: []S) !usize {
            var next_pos: u64 = 0;
            var input_pos: usize = 0;

            while (input_pos < input.len) {
                const actual_batch_size = @min(self.batch_size, input.len - input_pos);
                const input_slice = input[input_pos .. input_pos + actual_batch_size];
                const results_slice = results[input_pos .. input_pos + actual_batch_size];
                const message = MessageInput.init(Data.init_stateless(input_slice, func, results_slice));
                input_pos += actual_batch_size;
                next_pos += 1;
                try self.input_queue.push(message);
            }
            return next_pos;
        }

        fn receive_results(self: *Self, expected_batches: usize, results: []S) !void {
            std.debug.assert(results.len >= expected_batches);

            var received_results: u64 = 0;

            while (received_results < expected_batches) {
                const message = self.output_queue.pop();
                if (message.is_eof()) {
                    break;
                }

                received_results += 1;
            }
        }

        pub fn map(self: *Self, ctx: *const Ctx, func: *const fn (*const Ctx, R) S, input: []const R, results: []S) !void {
            std.debug.assert(results.len >= input.len);

            const n_batches = try self.send_messages(ctx, func, input, results);
            try self.receive_results(n_batches, results);
        }

        /// Allocates the results array
        /// Invoker owns the array, and must free it
        pub fn map_alloc(self: *Self, ctx: *const Ctx, func: *const fn (*const Ctx, R) S, input: []const R) ![]S {
            const results = try self.allocator.alloc(S, input.len);
            try self.map(ctx, func, input, results);
            return results;
        }

        fn map_no_ctx(self: *Self, func: *const fn (R) S, input: []const R, results: []S) !void {
            std.debug.assert(results.len >= input.len);
            std.debug.assert(Ctx == u0);

            const n_batches = try self.send_messages_stateless(func, input, results);
            try self.receive_results(n_batches, results);
        }

        /// Allocates the results array
        /// Invoker owns the array, and must free it
        fn map_no_ctx_alloc(self: *Self, func: *const fn (R) S, input: []const R) ![]S {
            std.debug.assert(Ctx == u0);

            const results = try self.allocator.alloc(S, input.len);
            try self.map_no_ctx(func, input, results);
            return results;
        }
    };
}

pub fn SimilarMap(comptime R: type, comptime T: type) type {
    return ParallelMap(R, R, T);
}

pub fn NoContextMap(comptime R: type, comptime S: type) type {
    return struct {
        const Self = @This();

        inner: ParallelMap(R, S, u0),

        pub fn init(config: Config) !Self {
            return Self{ .inner = try ParallelMap(R, S, u0).init(config) };
        }

        pub fn destroy(self: *Self) !void {
            return self.inner.destroy();
        }

        pub fn map(self: *Self, func: *const fn (R) S, input: []const R, results: []S) !void {
            return self.inner.map_no_ctx(func, input, results);
        }

        /// Allocates the results array
        /// Invoker owns the array, and must free it
        pub fn map_alloc(self: *Self, func: *const fn (R) S, input: []const R) ![]S {
            return self.inner.map_no_ctx_alloc(func, input);
        }
    };
}

pub fn BasicMap(comptime R: type) type {
    return NoContextMap(R, R);
}
