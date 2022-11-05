const std = @import("std");
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");

// const QueryComponents = struct {
//     input: *fd.Input,
//     camera: *fd.Camera,
//     pos: *fd.Position,
//     fwd: *fd.Forward,
// };

fn updateMovement(cam: *fd.Camera, pos: *fd.Position, fwd: *fd.Forward, dt: zm.F32x4, input_state: *const input.FrameData) void {
    var speed_scalar: f32 = 50.0;
    speed_scalar = 1.7;
    if (input_state.targets.contains(config.input_move_fast)) {
        speed_scalar = 6;
    } else if (input_state.targets.contains(config.input_move_slow)) {
        speed_scalar = 0.5;
    }
    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.mul(zm.rotationX(cam.pitch), zm.rotationY(cam.yaw));
    var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

    zm.store(fwd.elems()[0..], forward, 3);

    const right = speed * dt * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
    forward = speed * dt * forward;

    var cpos = zm.load(pos.elems()[0..], zm.Vec, 3);

    if (input_state.targets.contains(config.input_move_forward)) {
        cpos += forward;
    } else if (input_state.targets.contains(config.input_move_backward)) {
        cpos -= forward;
    }
    // if (window.getKey(.d) == .press) {
    if (input_state.targets.contains(config.input_move_right)) {
        cpos += right;
    } else if (input_state.targets.contains(config.input_move_left)) {
        cpos -= right;
    }

    zm.store(pos.elems()[0..], cpos, 3);
}

pub const StateIdle = struct {
    dummy: u32,
};

const StatePlayerIdle = struct {
    query: flecs.Query,
};

fn enter(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StatePlayerIdle, ctx.state.self);
    _ = self;
}

fn exit(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StatePlayerIdle, ctx.state.self);
    _ = self;
}

fn update(ctx: fsm.StateFuncContext) void {
    // const self = Util.cast(StateIdle, ctx.data.ptr);
    // _ = self;
    const self = Util.castBytes(StatePlayerIdle, ctx.state.self);
    var entity_iter = self.query.iterator(struct {
        input: *fd.Input,
        camera: *fd.Camera,
        pos: *fd.Position,
        fwd: *fd.Forward,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }

        updateMovement(comps.camera, comps.pos, comps.fwd, ctx.dt, ctx.frame_data);
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Input)
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