const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");

fn updateLook(rot: *fd.EulerRotation, input_state: *const input.FrameData) void {
    const movement_yaw = input_state.get(config.input_look_yaw);
    const movement_pitch = input_state.get(config.input_look_pitch);

    // if (cam.window.getMouseButton(.right) == .press) {
    rot.pitch += 0.0025 * movement_pitch.number;
    rot.yaw += 0.0025 * movement_yaw.number;
    rot.pitch = math.min(rot.pitch, 0.48 * math.pi);
    rot.pitch = math.max(rot.pitch, -0.48 * math.pi);
    rot.yaw = zm.modAngle(rot.yaw);
    // }
}

fn updateMovement(pos: *fd.Position, rot: *fd.EulerRotation, dt: zm.F32x4, input_state: *const input.FrameData) void {
    var speed_scalar: f32 = 50.0;
    if (input_state.held(config.input_move_fast)) {
        speed_scalar *= 50;
    } else if (input_state.held(config.input_move_slow)) {
        speed_scalar *= 0.1;
    }
    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.mul(zm.rotationX(rot.pitch), zm.rotationY(rot.yaw));
    var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

    const right = speed * dt * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
    forward = speed * dt * forward;

    var cpos = zm.load(pos.elems()[0..], zm.Vec, 3);

    if (input_state.held(config.input_move_forward)) {
        cpos += forward;
    } else if (input_state.held(config.input_move_backward)) {
        cpos -= forward;
    }

    if (input_state.held(config.input_move_right)) {
        cpos += right;
    } else if (input_state.held(config.input_move_left)) {
        cpos -= right;
    }

    zm.store(pos.elems()[0..], cpos, 3);
}

pub const StateIdle = struct {
    dummy: u32,
};

const StateCameraFreefly = struct {
    query: flecs.Query,
};

fn enter(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StateCameraFreefly, ctx.state.self);
    _ = self;
}

fn exit(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StateCameraFreefly, ctx.state.self);
    _ = self;
}

fn update(ctx: fsm.StateFuncContext) void {
    // const self = Util.cast(StateIdle, ctx.data.ptr);
    // _ = self;
    const self = Util.castBytes(StateCameraFreefly, ctx.state.self);
    var entity_iter = self.query.iterator(struct {
        input: *fd.Input,
        camera: *fd.Camera,
        pos: *fd.Position,
        rot: *fd.EulerRotation,
        // fwd: *fd.Forward,
        // transform: *fd.Transform,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }

        if (cam.class != 0) {
            // HACK
            continue;
        }
        updateLook(comps.rot, ctx.frame_data);
        updateMovement(comps.pos, comps.rot, ctx.dt, ctx.frame_data);
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Camera)
        .with(fd.Position)
        .with(fd.EulerRotation)
    // .with(fd.Transform)
    ;

    var query = query_builder.buildQuery();
    var self = ctx.allocator.create(StateCameraFreefly) catch unreachable;
    self.query = query;

    return .{
        .name = IdLocal.init("freefly"),
        .self = std.mem.asBytes(self),
        .size = @sizeOf(StateIdle),
        .transitions = std.ArrayList(fsm.Transition).init(ctx.allocator),
        .enter = enter,
        .exit = exit,
        .update = update,
    };
}

pub fn destroy() void {}
