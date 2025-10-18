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
const zaudio = @import("zaudio");
const zphy = @import("zphysics");
const egl_math = @import("../../core/math.zig");
const AK = @import("wwise-zig");
const AK_ID = @import("wwise-ids");
const context = @import("../../core/context.zig");
const im3d = @import("im3d");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    audio: *zaudio.Engine,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
};

pub fn create(create_ctx: StateContext) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(StateContext) catch unreachable;
    update_ctx.* = StateContext.view(create_ctx);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = playerStateIdle;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.id(fd.Forward), .inout = .InOut },
            .{ .id = ecs.id(fd.Player), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_PC, fd.FSM_PC_Idle), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 6);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "playerStateIdle",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

var boost_active_time: f64 = 0;
var boost_next_cooldown: f64 = 0;
fn updateMovement(ctx: *StateContext, pos: *fd.Position, rot: *fd.Rotation, fwd: *fd.Forward, dt: f32, input_state: *const input.FrameData) void {
    const environment_info = ctx.ecsu_world.getSingleton(fd.EnvironmentInfo).?;
    const boosting = boost_active_time > environment_info.world_time;

    var speed_scalar: f32 = 1.35;
    if (input_state.held(config.input.move_fast)) {
        speed_scalar = 8;
    } else if (input_state.held(config.input.move_slow)) {
        speed_scalar = 0.5;
    }

    if (boosting) {
        speed_scalar = 500;
    }

    if (!boosting) {
        const yaw = input_state.get(config.input.look_yaw).number;
        const rot_yaw = zm.quatFromNormAxisAngle(zm.Vec{ 0, 1, 0, 0 }, yaw * 0.0025);
        const rot_in = rot.asZM();
        const rot_new = zm.qmul(rot_in, rot_yaw);
        rot.fromZM(rot_new);

        // if (input_state.just_pressed(config.input.interact) and boost_next_cooldown < environment_info.world_time) {
        //     boost_next_cooldown = environment_info.world_time + 0.2;
        //     boost_active_time = environment_info.world_time + 1;
        // }
    }

    if (environment_info.journey_time_multiplier != 1) {
        return;
    }

    var speed = zm.f32x4s(speed_scalar);
    const transform = zm.matFromQuat(rot.asZM());
    const forward = zm.util.getAxisZ(transform);
    zm.store(fwd.elems()[0..], forward, 3);

    const query = ctx.physics_world.getNarrowPhaseQuery();

    const ray_origin = [_]f32{
        pos.x + fwd.x * 2,
        pos.y + 200,
        pos.z + fwd.z * 2,
        0,
    };
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };
    const ray = zphy.RRayCast{
        .origin = ray_origin,
        .direction = ray_dir,
    };
    const result = query.castRay(
        ray,
        .{
            .broad_phase_layer_filter = @ptrCast(&config.physics.NonMovingBroadPhaseLayerFilter{}),
        },
    );

    if (result.has_hit) {
        const bodies = ctx.physics_world.getBodiesUnsafe();
        const body_hit_opt = zphy.tryGetBody(bodies, result.hit.body_id);
        if (body_hit_opt) |body_hit| {
            const hit_normal = body_hit.getWorldSpaceSurfaceNormal(result.hit.sub_shape_id, ray.getPointOnRay(result.hit.fraction));
            const steepness = @max(0.0, hit_normal[1] - 0.5) / 0.5;
            speed *= zm.f32x4s(steepness);

            // im3d.Im3d.DrawCone(
            //     &.{
            //         .x = pos.x + fwd.x * 2,
            //         .y = pos.y,
            //         .z = pos.z + fwd.z * 2,
            //     },
            //     &.{ .x = 0, .y = 1, .z = 0 },
            //     1 + steepness * steepness,
            //     0.5,
            //     3,
            // );
        }
    }

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

        const movement = move_dir * speed * zm.f32x4s(dt);
        cpos += movement;
        // std.debug.print("yaw{}\n", .{yaw});

        zm.store(pos.elems()[0..], cpos, 3);
    }
}

fn updateSnapToTerrain(physics_world: *zphy.PhysicsSystem, pos: *fd.Position) void {
    const query = physics_world.getNarrowPhaseQuery();

    const ray_origin = [_]f32{ pos.x, pos.y + 200, pos.z, 0 };
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };
    const result = query.castRay(
        .{
            .origin = ray_origin,
            .direction = ray_dir,
        },
        .{
            .broad_phase_layer_filter = @ptrCast(&config.physics.NonMovingBroadPhaseLayerFilter{}),
        },
    );

    if (result.has_hit) {
        pos.y = ray_origin[1] + ray_dir[1] * result.hit.fraction;
    }
}

fn playVoiceOver(ctx: *StateContext, pos: *fd.Position, rot: *fd.Rotation, fwd: *fd.Forward, dt: f32, player: *fd.Player, input_frame_data: *input.FrameData) void {
    _ = pos; // autofix
    _ = rot; // autofix
    _ = fwd; // autofix
    _ = dt; // autofix
    const environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    _ = environment_info; // autofix

    if (input_frame_data.just_pressed(config.input.reload_shaders)) {
        player.music_played_counter = 10000;
        player.played_intro = true;
        player.played_exited_village = true;
        player.music.?.stop() catch unreachable;
        player.vo_intro.stop() catch unreachable;
        player.vo_exited_village.stop() catch unreachable;
    }

    if (player.amount_moved_total > player.music_played_counter) {
        player.music_played_counter += 2000;
        player.music.?.start() catch unreachable;
    }

    if (!player.played_intro and player.amount_moved_total > 20) {
        player.played_intro = true;
        player.vo_intro.start() catch unreachable;
    }

    if (!player.played_exited_village and player.amount_moved_total > 120) {
        player.played_exited_village = true;
        player.vo_exited_village.start() catch unreachable;
    }
}

fn playerStateIdle(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const positions = ecs.field(it, fd.Position, 1).?;
    const rotations = ecs.field(it, fd.Rotation, 2).?;
    const forwards = ecs.field(it, fd.Forward, 3).?;
    const players = ecs.field(it, fd.Player, 4).?;

    const environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;

    for (inputs, positions, rotations, forwards, players, it.entities()) |input_comp, *pos, *rot, *fwd, *player, ent| {
        _ = ent; // autofix
        if (!input_comp.active) {
            continue;
        }

        const pos_before = pos.asZM();
        updateMovement(ctx, pos, rot, fwd, it.delta_time, ctx.input_frame_data);
        updateSnapToTerrain(ctx.physics_world, pos);
        if (environment_info.journey_time_end != null) {
            continue;
        }
        playVoiceOver(ctx, pos, rot, fwd, it.delta_time, player, ctx.input_frame_data);

        const pos_after = pos.asZM();
        player.*.amount_moved += zm.length3(pos_after - pos_before)[0];
        player.*.amount_moved_total += zm.length3(pos_after - pos_before)[0];

        const step_length: f32 = if (ctx.input_frame_data.held(config.input.move_fast)) 3 else 0.8;
        if (player.amount_moved > step_length) {
            if (player.sfx_footstep_index > 1) {
                player.sfx_footstep_index = 0;
            }
            player.sfx_footstep_index += 1;
            player.amount_moved = 0;

            var sound_buffer: [256]u8 = undefined;
            const sound_path = std.fmt.bufPrintZ(
                sound_buffer[0..sound_buffer.len],
                "content/audio/footsteps/grass{d}.wav",
                .{player.sfx_footstep_index},
            ) catch unreachable;
            ctx.audio.playSound(sound_path, null) catch unreachable;
        }

        // var fwd_xz_z = comps.fwd.asZM();
        // fwd_xz_z[1] = 0;
        // fwd_xz_z = zm.normalize3(fwd_xz_z);
        // const ak_pos = AK.AkSoundPosition{
        //     .position = .{
        //         .x = comps.pos.x,
        //         .y = comps.pos.y,
        //         .z = comps.pos.z,
        //     },
        //     .orientation_front = .{
        //         .x = fwd_xz_z[0],
        //         .z = fwd_xz_z[2],
        //     },
        //     .orientation_top = .{
        //         .y = 1.0,
        //     },
        // };
        // AK.SoundEngine.setPosition(config.audio_player_oid, ak_pos, .{}) catch unreachable;

    }
}
