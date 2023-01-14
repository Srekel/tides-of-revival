const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");
const fr = @import("../../flecs_relation.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");
const zbt = @import("zbullet");
const egl_math = @import("../../core/math.zig");

fn updateMovement(pos: *fd.Position, rot: *fd.EulerRotation, fwd: *fd.Forward, dt: zm.F32x4, input_state: *const input.FrameData) void {
    var speed_scalar: f32 = 1.7;
    if (input_state.held(config.input_move_fast)) {
        speed_scalar = 126;
    } else if (input_state.held(config.input_move_slow)) {
        speed_scalar = 0.5;
    }

    speed_scalar *= 2.0;

    const yaw = input_state.get(config.input_look_yaw);

    rot.yaw += 0.0025 * yaw.number;
    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.mul(zm.rotationX(rot.pitch), zm.rotationY(rot.yaw));
    var forward = zm.util.getAxisZ(transform);

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

fn updateDeathFromDarkness(entity: flecs.Entity, ctx: fsm.StateFuncContext) void {
    const transform = entity.get(fd.Transform);
    const pos = transform.?.getPos00();

    const environment_info = ctx.flecs_world.getSingletonMut(fd.EnvironmentInfo).?;
    if (environment_info.sun_height > -0.5) {
        return;
    }

    const FilterCallback = struct {
        transform: *fd.Transform,
        light: *const fd.Light,
    };

    var safe_from_darkness = false;
    var filter = ctx.flecs_world.filter(FilterCallback);
    defer filter.deinit();
    var filter_it = filter.iterator(FilterCallback);
    while (filter_it.next()) |comps| {
        if (filter_it.entity().hasPair(flecs.c.Constants.EcsChildOf, entity.id)) {
            continue;
        }

        const dist = egl_math.dist3_xz(pos, comps.transform.getPos00());
        if (dist < comps.light.range) {
            safe_from_darkness = true;
            break;
        }
    }

    if (!safe_from_darkness) {
        std.debug.panic("dead", .{});
    }
}

fn updateWinFromArrival(entity: flecs.Entity, ctx: fsm.StateFuncContext) void {
    const transform = entity.get(fd.Transform);
    const pos = transform.?.getPos00();

    const environment_info = ctx.flecs_world.getSingletonMut(fd.EnvironmentInfo).?;
    if (environment_info.sun_height > 0) {
        return;
    }

    const FilterCallback = struct {
        pos: *fd.Position,
        city: *const fd.CompCity,
    };

    var filter = ctx.flecs_world.filter(FilterCallback);
    defer filter.deinit();
    var filter_it = filter.iterator(FilterCallback);
    while (filter_it.next()) |comps| {
        if (filter_it.entity().hasPair(fr.Hometown, entity.id)) {
            continue;
        }

        const dist = egl_math.dist3_xz(pos, comps.pos.elemsConst().*);
        if (dist < 50) {
            std.debug.panic("win", .{});
            break;
        }
    }
}

pub const StateIdle = struct {
    amount_moved: f32,
    sfx_footstep_index: u32,
};

const StatePlayerIdle = struct {
    query: flecs.Query,
};

fn enter(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StatePlayerIdle, ctx.state.self);
    _ = self;
    // const state = ctx.blob_array.getBlobAsValue(comps.fsm.blob_lookup, StateIdle);
    // state.*.amount_moved = 0;
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
        fsm: *fd.FSM,
        cam: *fd.Camera,
    });

    while (entity_iter.next()) |comps| {
        if (!comps.input.active) {
            continue;
        }

        const pos_before = comps.pos.*;
        updateMovement(comps.pos, comps.rot, comps.fwd, ctx.dt, ctx.frame_data);
        updateSnapToTerrain(ctx.physics_world, comps.pos);
        updateDeathFromDarkness(entity_iter.entity(), ctx);
        // updateWinFromArrival(entity_iter.entity(), ctx);
        const pos_after = comps.pos.*;
        const state = ctx.blob_array.getBlobAsValue(comps.fsm.blob_lookup, StateIdle);
        state.*.amount_moved += @fabs(pos_after.x - pos_before.x);
        state.*.amount_moved += @fabs(pos_after.y - pos_before.y);

        // HACK!!!
        // HACK!!!
        if (state.amount_moved < 0) {
            state.amount_moved = 0;
        }
        if (state.sfx_footstep_index > 1) {
            state.sfx_footstep_index = 0;
        }

        if (state.amount_moved > 3) {
            state.amount_moved = 0;

            // TODO proper audio resource management
            // const sfx_paths = [_][:0]const u8{
            //     "content/audio/material/PM_SDGS_113 Footstep Step Dry Grass Shrubs Pine Needles Meadow .wav",
            //     "content/audio/material/PM_SDGS_186 Footstep Step Dry Grass Shrubs Pine Needles Meadow .wav",
            // };
            // const sfx_path = sfx_paths[state.sfx_footstep_index];
            // state.sfx_footstep_index = 1 - state.sfx_footstep_index;
            // const sfx_footstep = ctx.audio_engine.createSoundFromFile(
            //     sfx_path,
            //     .{ .flags = .{ .stream = false } },
            // ) catch unreachable;
            // sfx_footstep.start() catch unreachable;
        }
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Position)
        .with(fd.EulerRotation)
        .with(fd.Forward)
        .with(fd.FSM)
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
