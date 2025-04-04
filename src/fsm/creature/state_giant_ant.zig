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
const context = @import("../../core/context.zig");

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

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
};

pub fn create(create_ctx: StateContext) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(StateContext) catch unreachable;
    update_ctx.* = StateContext.view(create_ctx);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = fsm_enemy_idle;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.id(fd.Forward), .inout = .InOut },
            .{ .id = ecs.id(fd.PhysicsBody), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_ENEMY, fd.FSM_ENEMY_Idle), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 5);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "fsm_enemy_idle",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn updateMovement(pos: *fd.Position, rot: *fd.Rotation, fwd: *fd.Forward, dt: zm.F32x4, player_pos: *const fd.Position) void {
    _ = rot;
    const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
    var self_pos_z = zm.loadArr3(pos.elems().*);
    const vec_to_player = player_pos_z - self_pos_z;
    const dir_to_player = zm.normalize3(vec_to_player);
    _ = dir_to_player;
    self_pos_z += fwd.asZM() * dt * zm.f32x4s(5);

    zm.store(pos.elems()[0..], self_pos_z, 3);
}

fn updateSnapToTerrain(
    physics_world: *zphy.PhysicsSystem,
    pos: *fd.Position,
    body: *fd.PhysicsBody,
    player_pos: *const fd.Position,
) void {
    const query = physics_world.getNarrowPhaseQuery();

    const ray_origin = [_]f32{ pos.x, pos.y + 200, pos.z, 0 };
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };
    const ray = zphy.RRayCast{
        .origin = ray_origin,
        .direction = ray_dir,
    };
    const result = query.castRay(
        ray,
        .{
            .broad_phase_layer_filter = @ptrCast(&NonMovingBroadPhaseLayerFilter{}),
        },
    );

    if (result.has_hit) {
        pos.y = ray_origin[1] + ray_dir[1] * result.hit.fraction + 0.1;

        const handedness_offset = std.math.pi;
        const up_z = zm.f32x4(0, 1, 0, 0);

        const body_lock_interface = physics_world.getBodyLockInterfaceNoLock();
        var read_lock_self: zphy.BodyLockRead = .{};
        read_lock_self.lock(body_lock_interface, body.body_id);
        defer read_lock_self.unlock();
        const body_self = read_lock_self.body.?;

        const bodies = physics_world.getBodiesUnsafe();
        const body_hit = zphy.tryGetBody(bodies, result.hit.body_id).?;
        const rot_slope_z = blk: {
            const hit_normal = body_hit.getWorldSpaceSurfaceNormal(result.hit.sub_shape_id, ray.getPointOnRay(result.hit.fraction));
            const hit_normal_z = zm.loadArr3(hit_normal);
            if (hit_normal[1] < 0.99) { // TODO: Find a good value, this was just arbitrarily picked :)
                const rot_axis_z = zm.cross3(up_z, hit_normal_z);
                const dot = zm.dot3(up_z, hit_normal_z)[0];
                const rot_angle = std.math.acos(dot);
                break :blk zm.quatFromAxisAngle(rot_axis_z, rot_angle);
            } else {
                break :blk zm.quatFromAxisAngle(up_z, 0);
            }
        };

        const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
        const self_pos_z = zm.loadArr3(pos.elems().*);
        const vec_to_player = player_pos_z - self_pos_z;
        const dist_to_player_sq = zm.lengthSq3(vec_to_player)[0];
        if (dist_to_player_sq > 1) {
            const skitter = dist_to_player_sq > (15 * 15) and std.math.modf(player_pos.y + pos.y * 0.25).fpart > 0.25;
            const dir_to_player = zm.normalize3(vec_to_player);
            const skitter_angle_offset: f32 = if (skitter) std.math.modf(player_pos.y + pos.y * 0.25).fpart * 3 - 1.5 else 0;
            const angle_to_player = std.math.atan2(dir_to_player[0], dir_to_player[2]) + skitter_angle_offset;
            const rot_towards_player_z = zm.quatFromAxisAngle(up_z, angle_to_player + handedness_offset);

            const rot_wanted_z = zm.qmul(rot_towards_player_z, rot_slope_z);
            const rot_curr_z = zm.loadArr4(body_self.getRotation());
            const slerp_factor: f32 = if (skitter) 0.01 else 0.01;
            const rot_new_z = zm.slerp(rot_curr_z, rot_wanted_z, slerp_factor); // TODO SmoothDamp
            const rot_new_normalized_z = zm.normalize4(rot_new_z);
            var rot: [4]f32 = undefined;
            zm.storeArr4(&rot, rot_new_normalized_z);

            // NOTE: Should this use MoveKinematic?
            const body_interface = physics_world.getBodyInterfaceMut();
            body_interface.setPositionRotationAndVelocity(
                body.body_id,
                pos.elems().*,
                rot,
                [3]f32{ 0, 0, 0 },
                [3]f32{ 0, 0, 0 },
            );
        }
        // } else if (gfx.end_screen_accumulated_time < 0) {
        //     gfx.end_screen_accumulated_time = 0;
        // }
    } else {
        const body_interface = physics_world.getBodyInterfaceMut();
        body_interface.setPosition(body.body_id, pos.elems().*, .dont_activate);
    }
}

fn fsm_enemy_idle(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const positions = ecs.field(it, fd.Position, 0).?;
    const rotations = ecs.field(it, fd.Rotation, 1).?;
    const forwards = ecs.field(it, fd.Forward, 2).?;
    const bodies = ecs.field(it, fd.PhysicsBody, 3).?;

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_pos = ecs.get(ctx.ecsu_world.world, player_ent, fd.Position).?;
    const body_interface = ctx.physics_world.getBodyInterfaceMut();

    for (positions, rotations, forwards, bodies) |*pos, *rot, *fwd, *body| {
        if (body_interface.getMotionType(body.body_id) == .kinematic) {
            updateMovement(pos, rot, fwd, zm.f32x4s(it.delta_time), player_pos);
            // updateSnapToTerrain(ctx.physics_world, pos, body, player_pos, ctx.gfx);
            updateSnapToTerrain(ctx.physics_world, pos, body, player_pos);
        }
    }
}
