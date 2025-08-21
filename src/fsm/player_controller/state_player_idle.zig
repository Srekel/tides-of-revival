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
const audio_manager = @import("../../audio/audio_manager_mock.zig");
const AK = @import("wwise-zig");
const AK_ID = @import("wwise-ids");
const context = @import("../../core/context.zig");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    audio_mgr: *audio_manager.AudioManager,
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
            .{ .id = ecs.pair(fd.FSM_PC, fd.FSM_PC_Idle), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 5);
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

    var speed_scalar: f32 = 1.7;
    if (input_state.held(config.input.move_fast)) {
        speed_scalar = 6;
    } else if (input_state.held(config.input.move_slow)) {
        speed_scalar = 0.5;
    }

    speed_scalar *= 2.0;
    if (boosting) {
        speed_scalar = 500;
    }

    if (!boosting) {
        const yaw = input_state.get(config.input.look_yaw).number;
        const rot_yaw = zm.quatFromNormAxisAngle(zm.Vec{ 0, 1, 0, 0 }, yaw * 0.0025);
        const rot_in = rot.asZM();
        const rot_new = zm.qmul(rot_in, rot_yaw);
        rot.fromZM(rot_new);

        if (input_state.just_pressed(config.input.interact) and boost_next_cooldown < environment_info.world_time) {
            boost_next_cooldown = environment_info.world_time + 0.2;
            boost_active_time = environment_info.world_time + 1;
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

fn playerStateIdle(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const positions = ecs.field(it, fd.Position, 1).?;
    const rotations = ecs.field(it, fd.Rotation, 2).?;
    const forwards = ecs.field(it, fd.Forward, 3).?;

    for (inputs, positions, rotations, forwards) |input_comp, *pos, *rot, *fwd| {
        if (!input_comp.active) {
            continue;
        }

        // const pos_before = pos.asZM();
        updateMovement(ctx, pos, rot, fwd, it.delta_time, ctx.input_frame_data);
        updateSnapToTerrain(ctx.physics_world, pos);
    }
}
