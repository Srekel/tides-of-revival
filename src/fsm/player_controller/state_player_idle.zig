const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const IdLocal = @import("../../core/core.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../core/blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const fr = @import("../../config/flecs_relation.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config/config.zig");
const zphy = @import("zphysics");
const egl_math = @import("../../core/math.zig");
const audio_manager = @import("../../audio/audio_manager.zig");
const AK = @import("wwise-zig");
const AK_ID = @import("wwise-ids");

pub const NonMovingBroadPhaseLayerFilter = extern struct {
    usingnamespace zphy.BroadPhaseLayerFilter.Methods(@This());
    __v: *const zphy.BroadPhaseLayerFilter.VTable = &vtable,

    const vtable = zphy.BroadPhaseLayerFilter.VTable{
        .shouldCollide = shouldCollide,
    };
    fn shouldCollide(self: *const zphy.BroadPhaseLayerFilter, layer: zphy.BroadPhaseLayer) callconv(.C) bool {
        _ = self;
        if (layer == config.broad_phase_layers.moving) {
            return false;
        }
        return true;
    }
};

fn updateMovement(state: *StateIdle, pos: *fd.Position, rot: *fd.Rotation, fwd: *fd.Forward, dt: zm.F32x4, input_state: *const input.FrameData, ctx: fsm.StateFuncContext) void {
    const environment_info = ctx.ecsu_world.getSingleton(fd.EnvironmentInfo).?;
    const boosting = state.boost_active_time > environment_info.world_time;

    var speed_scalar: f32 = 1.7;
    if (input_state.held(config.input.move_fast)) {
        speed_scalar = 6;
    } else if (input_state.held(config.input.move_slow)) {
        speed_scalar = 0.5;
    }

    speed_scalar *= 2.0;
    if (boosting) {
        speed_scalar = 50;
    }

    if (!boosting) {
        const yaw = input_state.get(config.input.look_yaw).number;
        const rot_yaw = zm.quatFromNormAxisAngle(zm.Vec{ 0, 1, 0, 0 }, yaw * 0.0025);
        const rot_in = rot.asZM();
        const rot_new = zm.qmul(rot_in, rot_yaw);
        rot.fromZM(rot_new);

        if (input_state.just_pressed(config.input.interact) and state.boost_next_cooldown < environment_info.world_time) {
            state.boost_next_cooldown = environment_info.world_time + 10;
            state.boost_active_time = environment_info.world_time + 0.2;
        }
    }

    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.matFromQuat(rot.asZM());
    const forward = zm.util.getAxisZ(transform);

    zm.store(fwd.elems()[0..], forward, 3);

    const right = zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
    // const movement = speed * dt * forward;

    var cpos = zm.load(pos.elems()[0..], zm.Vec, 3);

    var move_dir = zm.f32x4s(0);
    if (input_state.held(config.input.move_forward)) {
        move_dir += forward;
    } else if (input_state.held(config.input.move_backward)) {
        move_dir -= forward;
    }

    if (input_state.held(config.input.move_right)) {
        move_dir += right;
    } else if (input_state.held(config.input.move_left)) {
        move_dir -= right;
    }

    if (zm.lengthSq3(move_dir)[0] > 0) {
        move_dir = zm.normalize3(move_dir);

        const movement = move_dir * speed * dt;
        cpos += movement;
        // std.debug.print("yaw{}\n", .{yaw});

        zm.store(pos.elems()[0..], cpos, 3);
    }
}

fn updateSnapToTerrain(physics_world: *zphy.PhysicsSystem, pos: *fd.Position) void {
    const query = physics_world.getNarrowPhaseQuery();

    const ray_origin = [_]f32{ pos.x, pos.y + 200, pos.z, 0 };
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };
    var result = query.castRay(
        .{
            .origin = ray_origin,
            .direction = ray_dir,
        },
        .{
            .broad_phase_layer_filter = @ptrCast(&NonMovingBroadPhaseLayerFilter{}),
        },
    );

    if (result.has_hit) {
        pos.y = ray_origin[1] + ray_dir[1] * result.hit.fraction;
    }
}

fn updateDeathFromDarkness(entity: ecs.entity_t, ctx: fsm.StateFuncContext) void {
    const transform = ecs.get(ctx.ecsu_world.world, entity, fd.Transform);
    const pos = transform.?.getPos00();

    const environment_info = ctx.ecsu_world.getSingleton(fd.EnvironmentInfo).?;
    if (environment_info.sun_height > -0.5) {
        return;
    }

    const FilterCallback = struct {
        transform: *fd.Transform,
        light: *const fd.Light,
    };

    var safe_from_darkness = false;
    var filter = ctx.ecsu_world.filter(FilterCallback);
    defer filter.deinit();
    var filter_it = filter.iterator(FilterCallback);
    while (filter_it.next()) |comps| {
        const filter_ent = ecsu.Entity.init(filter_it.world().world, filter_it.entity());
        if (filter_ent.hasPair(ecs.ChildOf, entity)) {
            continue;
        }

        const dist = egl_math.dist3_xz(pos, comps.transform.getPos00());
        if (dist < comps.light.range) {
            safe_from_darkness = true;
            ecs.iter_fini(filter_it.iter);
            break;
        }
    }

    if (!safe_from_darkness) {
        std.debug.panic("dead", .{});
    }
}

fn updateWinFromArrival(entity_id: ecs.entity_t, ctx: fsm.StateFuncContext) void {
    const ent = ecsu.Entity.init(ctx.ecsu_world.world, entity_id);
    const transform = ecs.get(ctx.ecsu_world.world, entity_id, fd.Transform);
    const pos = transform.?.getPos00();

    const FilterCallback = struct {
        pos: *fd.Position,
        city: *const fd.CompCity,
    };

    var filter = ctx.ecsu_world.filter(FilterCallback);
    defer filter.deinit();
    var filter_it = filter.iterator(FilterCallback);
    while (filter_it.next()) |comps| {
        if (ent.hasPair(fr.Hometown, filter_it.entity())) {
            continue;
        }

        const dist = egl_math.dist3_xz(pos, comps.pos.elemsConst().*);
        if (dist < 20) {
            std.debug.panic("win", .{});
            ecs.iter_fini(filter_it.iter);
            break;
        }
    }
}

pub const StateIdle = struct {
    amount_moved: f32,
    boost_next_cooldown: f32,
    boost_active_time: f32,
    sfx_footstep_index: u32,
};

const StatePlayerIdle = struct {
    query: ecsu.Query,
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
        rot: *fd.Rotation,
        fwd: *fd.Forward,
        fsm: *fd.FSM,
        // cam: *fd.Camera,
    });

    while (entity_iter.next()) |comps| {
        if (!comps.input.active) {
            continue;
        }
        const state = ctx.blob_array.getBlobAsValue(comps.fsm.blob_lookup, StateIdle);

        const pos_before = comps.pos.asZM();
        updateMovement(state, comps.pos, comps.rot, comps.fwd, ctx.dt, ctx.input_frame_data, ctx);
        updateSnapToTerrain(ctx.physics_world, comps.pos);
        // updateDeathFromDarkness(entity_iter.entity(), ctx);
        // updateWinFromArrival(entity_iter.entity(), ctx);
        const pos_after = comps.pos.asZM();
        state.*.amount_moved += zm.length3(pos_after - pos_before)[0];

        // HACK!!!
        if (state.amount_moved < 0) {
            state.amount_moved = 0;
        }
        if (state.sfx_footstep_index > 1) {
            state.sfx_footstep_index = 0;
        }

        if (state.amount_moved > 3) {
            state.amount_moved = 0;

            _ = AK.SoundEngine.postEventID(AK_ID.EVENTS.FOOTSTEP, config.audio_player_oid, .{}) catch unreachable;
        }

        var fwd_xz_z = comps.fwd.asZM();
        fwd_xz_z[1] = 0;
        fwd_xz_z = zm.normalize3(fwd_xz_z);
        const ak_pos = AK.AkSoundPosition{
            .position = .{
                .x = comps.pos.x,
                .y = comps.pos.y,
                .z = comps.pos.z,
            },
            .orientation_front = .{
                .x = fwd_xz_z[0],
                .z = fwd_xz_z[2],
            },
            .orientation_top = .{
                .y = 1.0,
            },
        };
        AK.SoundEngine.setPosition(config.audio_player_oid, ak_pos, .{}) catch unreachable;
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = ecsu.QueryBuilder.init(ctx.ecsu_world);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Position)
        .with(fd.Rotation)
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
