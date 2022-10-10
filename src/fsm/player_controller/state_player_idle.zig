const std = @import("std");
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const fsm = @import("../fsm.zig");

pub const StateIdle = struct {
    dummy: u32,
};

fn enter(context: *fsm.StateFuncContext) void {
    const self = Util.cast(context.data, StateIdle);
    // _ = self;
    self.dummy = 0;
    // _ = context;
}

fn exit(context: *fsm.StateFuncContext) void {
    const self = Util.cast(context.data, StateIdle);
    // const self = @ptrCast(StateIdle, @alignCast(@alignOf(StateIdle), self_opaque));
    // @Call(.{ .modifier = .always_inline }, self.init, .{ self, context });
    // const self = @ptrCast(*StateIdle, @alignCast(@alignOf(StateIdle), context.data));
    _ = self;
    // _ = context;
}

fn update(context: *fsm.StateFuncContext) void {
    const self = Util.cast(context.data, StateIdle);
    // const self = @ptrCast(StateIdle, @alignCast(@alignOf(StateIdle), self_opaque));
    // @Call(.{ .modifier = .always_inline }, self.init, .{ self, context });
    // const self = @ptrCast(*StateIdle, @alignCast(@alignOf(StateIdle), context.data));
    // _ = self;
    self.dummy += 1;
    // _ = context;
}

pub fn create(allocator: std.mem.Allocator) fsm.State {
    return .{
        .name = IdLocal.init("idle"),
        .size = @sizeOf(StateIdle),
        // .ptr = allocator.create(StateIdle) catch unreachable,
        .transitions = std.ArrayList(fsm.Transition).init(allocator),
        .enter = enter,
        .exit = exit,
        .update = update,
    };
}
