const std = @import("std");
const Queue = @import("queue.zig").Queue;
const Message = @import("message.zig").Message;
const EmptyMessage = @import("message.zig").EmptyMessage;
const DataWithFn = @import("message.zig").DataWithFn;

pub fn Worker(comptime R: type, comptime S: type, comptime Ctx: type) type {
    return struct {
        input_queue: *Queue(InputType),
        result_queue: *Queue(OutputType),

        const Self = @This();
        const InputType = Message(DataWithFn(Ctx, R, S));
        const OutputType = EmptyMessage;

        pub fn init(input_queue: *Queue(InputType), result_queue: *Queue(OutputType)) Self {
            return Self{
                .input_queue = input_queue,
                .result_queue = result_queue,
            };
        }

        pub fn run(self: *Self) !void {
            while (true) {
                const message = self.input_queue.pop();

                if (message.is_eof()) {
                    break;
                }

                message.data.call();

                try self.result_queue.push(OutputType.init_null());
            }
        }
    };
}

pub fn worker_loop(comptime R: type, comptime S: type, comptime T: type, worker: *Worker(R, S, T)) !void {
    return worker.run();
}

pub fn initiate_worker(comptime R: type, comptime S: type, comptime T: type, worker: *Worker(R, S, T)) !std.Thread {
    return std.Thread.spawn(.{}, worker_loop, .{ R, S, T, worker });
}
