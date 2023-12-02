const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const IdLocal = @import("../../core/core.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../core/blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config/config.zig");

fn updateLook(rot: *fd.Rotation, input_state: *const input.FrameData) void {
    const movement_yaw = input_state.get(config.input.look_yaw).number;
    const movement_pitch = input_state.get(config.input.look_pitch).number;

    const rot_pitch = zm.quatFromNormAxisAngle(zm.Vec{ 1, 0, 0, 0 }, movement_pitch * 0.0025);
    const rot_yaw = zm.quatFromNormAxisAngle(zm.Vec{ 0, 1, 0, 0 }, movement_yaw * 0.0025);
    const rot_in = rot.asZM();
    const rpy_constrained = .{
        std.math.clamp(rpy[0], -0.9, 0.9),
        rpy[1],
        rpy[2],
    };
    const constrained_z = zm.quatFromRollPitchYaw(rpy_constrained[0], rpy_constrained[1], rpy_constrained[2]);
}

fn updateMovement(pos: *fd.Position, rot: *fd.Rotation, dt: zm.F32x4, input_state: *const input.FrameData) void {
    var speed_scalar: f32 = 50.0;
    if (input_state.held(config.input.move_fast)) {
        speed_scalar *= 50;
    } else if (input_state.held(config.input.move_slow)) {
        speed_scalar *= 0.1;
    }
    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.matFromQuat(rot.asZM());
    var forward = zm.util.getAxisZ(transform);
    var right = zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
    var up = zm.normalize3(zm.cross3(forward, right));

    right = speed * dt * right;
    forward = speed * dt * forward;
    up = speed * dt * up;

    var cpos = zm.load(pos.elems()[0..], zm.Vec, 3);

    if (input_state.held(config.input.move_forward)) {
        cpos += forward;
    } else if (input_state.held(config.input.move_backward)) {
        cpos -= forward;
    }

    if (input_state.held(config.input.move_right)) {
        cpos += right;
    } else if (input_state.held(config.input.move_left)) {
        cpos -= right;
    }

    if (input_state.held(config.input.move_up)) {
        cpos += up;
    } else if (input_state.held(config.input.move_down)) {
        cpos -= up;
    }

    zm.store(pos.elems()[0..], cpos, 3);
}

pub const StateIdle = struct {
    dummy: u32,
};

const StateCameraFreefly = struct {
    query: ecsu.Query,
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
        rot: *fd.Rotation,
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
    var query_builder = ecsu.QueryBuilder.init(ctx.ecsu_world);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Camera)
        .with(fd.Position)
        .with(fd.Rotation)
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
