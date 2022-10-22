const std = @import("std");
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");

pub const StateIdle = struct {
    dummy: u32,
};

const StatePlayerIdle = struct {
    query: flecs.Query,
};

fn enter(context: fsm.StateFuncContext) void {
    const self = Util.castBytes(StatePlayerIdle, context.state.self);
    _ = self;
}

fn exit(context: fsm.StateFuncContext) void {
    const self = Util.castBytes(StatePlayerIdle, context.state.self);
    _ = self;
}

fn update(context: fsm.StateFuncContext) void {
    // const self = Util.cast(StateIdle, context.data.ptr);
    // _ = self;
    const self = Util.castBytes(StatePlayerIdle, context.state.self);
    var entity_iter = self.query.iterator(struct {
        camera: *fd.Camera,
        pos: *fd.Position,
        fwd: *fd.Forward,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Camera)
        .with(fd.Position)
        .with(fd.Forward);

    var query = query_builder.buildQuery();
    var self = ctx.allocator.create(StatePlayerIdle) catch unreachable;
    self.query = query;

    return .{
        .name = IdLocal.init("idle"),
        .self = std.mem.asBytes(self),
        .size = @sizeOf(StateIdle),
        .transitions = std.ArrayList(fsm.Transition).init(ctx.allocator),
        .enter = enter,
        .exit = exit,
        .update = update,
    };
}

pub fn destroy() void {}
