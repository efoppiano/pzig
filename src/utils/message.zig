const std = @import("std");
const Order = std.math.Order;

pub fn Message(comptime T: type) type {
    return struct {
        data: T,
        eof: bool,

        const Self = @This();

        pub fn init(data: T) Self {
            return Self{ .data = data, .eof = false };
        }

        pub fn init_null() Self {
            std.debug.assert(T == u0);
            return Self{ .data = undefined, .eof = false };
        }

        pub fn is_eof(self: Self) bool {
            return self.eof;
        }

        pub fn init_eof() Self {
            return Message(T){ .data = undefined, .eof = true };
        }
    };
}

pub const EmptyMessage = Message(u0);

pub fn DataWithFn(comptime Ctx: type, comptime R: type, comptime S: type) type {
    return struct {
        data: []const R,
        func: ?*const fn (*const Ctx, R) S,
        func2: ?*const fn (R) S,
        context: ?*const Ctx,
        destination: []S,

        const Self = @This();

        pub fn init(data: []const R, func: *const fn (*const Ctx, R) S, context: *const Ctx, destination: []S) Self {
            return Self{ .data = data, .func = func, .func2 = null, .context = context, .destination = destination };
        }

        pub fn init_stateless(data: []const R, func: *const fn (R) S, destination: []S) Self {
            return Self{ .data = data, .func = null, .func2 = func, .context = null, .destination = destination };
        }

        fn call_one(self: Self, value: *const R) S {
            if (self.func) |func| {
                return func(self.context.?, value.*);
            } else if (self.func2) |func| {
                return func(value.*);
            } else {
                unreachable;
            }
        }

        pub fn call(self: Self) void {
            std.debug.assert(self.destination.len >= self.data.len);

            for (self.data, 0..) |item, i| {
                self.destination[i] = self.call_one(&item);
            }
        }
    };
}
