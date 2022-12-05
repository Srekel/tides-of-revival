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
const zbt = @import("zbullet");

fn updateMovement(pos: *fd.Position, rot: *fd.EulerRotation, fwd: *fd.Forward, dt: zm.F32x4, input_state: *const input.FrameData) void {
    var speed_scalar: f32 = 10.7;
    if (input_state.targets.contains(config.input_move_fast)) {
        speed_scalar = 6;
    } else if (input_state.targets.contains(config.input_move_slow)) {
        speed_scalar = 0.5;
    }

    const yaw = input_state.get(config.input_look_yaw);

    rot.yaw += 0.0025 * yaw.number;
    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.mul(zm.rotationX(rot.pitch), zm.rotationY(rot.yaw));
    var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

    zm.store(fwd.elems()[0..], forward, 3);

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
    // std.debug.print("yaw{}\n", .{yaw});

    zm.store(pos.elems()[0..], cpos, 3);
}

fn updateSnapToTerrain(physics_world: zbt.World, pos: *fd.Position) void {
    var ray_result: zbt.RayCastResult = undefined;
    const ray_origin = fd.Position.init(pos.x, pos.y + 20, pos.z);
    const ray_end = fd.Position.init(pos.x, pos.y - 10, pos.z);
    const hit = physics_world.rayTestClosest(
        ray_origin.elemsConst()[0..],
        ray_end.elemsConst()[0..],
        .{ .default = true }, // zbt.CBT_COLLISION_FILTER_DEFAULT,
        zbt.CollisionFilter.all,
        .{ .use_gjk_convex_test = true }, // zbt.CBT_RAYCAST_FLAG_USE_GJK_CONVEX_TEST,
        &ray_result,
    );

    if (hit) {
        pos.y = ray_result.hit_point_world[1];
    }
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
        pos: *fd.Position,
        rot: *fd.EulerRotation,
        fwd: *fd.Forward,
        cam: *fd.Camera,
    });

    while (entity_iter.next()) |comps| {
        if (!comps.input.active) {
            continue;
        }

        updateMovement(comps.pos, comps.rot, comps.fwd, ctx.dt, ctx.frame_data);
        updateSnapToTerrain(ctx.physics_world, comps.pos);
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Position)
        .with(fd.EulerRotation)
        .with(fd.Forward)
        .without(fd.Camera);

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
