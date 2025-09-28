const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const input = @import("../input.zig");
const config = @import("../config/config.zig");
const context = @import("../core/context.zig");

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    state: struct {},
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{};

    _ = ecsu.registerSystem(create_ctx.ecsu_world.world, "moveForward", moveForward, update_ctx, &[_]ecs.term_t{
        .{ .id = ecs.id(fd.Locomotion), .inout = .In },
        .{ .id = ecs.id(fd.Forward), .inout = .In },
        .{ .id = ecs.id(fd.Position), .inout = .InOut },
    });

    _ = ecsu.registerSystem(create_ctx.ecsu_world.world, "snapToTerrain", snapToTerrain, update_ctx, &[_]ecs.term_t{
        .{ .id = ecs.id(fd.Locomotion), .inout = .In },
        .{ .id = ecs.id(fd.Position), .inout = .InOut },
        .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
    });

    _ = ecsu.registerSystem(create_ctx.ecsu_world.world, "updateBodies", updateBodies, update_ctx, &[_]ecs.term_t{
        .{ .id = ecs.id(fd.PhysicsBody), .inout = .In },
        .{ .id = ecs.id(fd.Position), .inout = .In },
        .{ .id = ecs.id(fd.Rotation), .inout = .In },
        .{ .id = ecs.id(fd.Locomotion), .inout = .InOutNone },
    });
}

fn moveForward(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    _ = ctx; // autofix

    const locomotions = ecs.field(it, fd.Locomotion, 0).?;
    const forwards = ecs.field(it, fd.Forward, 1).?;
    const positions = ecs.field(it, fd.Position, 2).?;
    for (locomotions, forwards, positions) |*locomotion, fwd, *pos| {
        if (!locomotion.enabled) {
            continue;
        }

        if (locomotion.affected_by_gravity) {
            locomotion.speed_y -= 20 * it.delta_time;
            pos.y += locomotion.speed_y * it.delta_time;
        }

        pos.x += locomotion.speed * it.delta_time * fwd.x;
        pos.z += locomotion.speed * it.delta_time * fwd.z;
    }
}

fn snapToTerrain(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const locomotions = ecs.field(it, fd.Locomotion, 0).?;
    const positions = ecs.field(it, fd.Position, 1).?;
    const rotations = ecs.field(it, fd.Rotation, 2).?;

    const slerp_factor: f32 = 0.01;
    const up_z = zm.f32x4(0, 1, 0, 0);
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };

    const bodies_all_sim = ctx.physics_world.getBodiesUnsafe();
    const bodies_all_low = ctx.physics_world_low.getBodiesUnsafe();

    const cast_ray_args: zphy.NarrowPhaseQuery.CastRayArgs = .{
        .broad_phase_layer_filter = @ptrCast(&config.physics.NonMovingBroadPhaseLayerFilter{}),
    };

    for (locomotions, positions, rotations) |*locomotion, *pos, *rot| {
        if (!locomotion.snap_to_terrain) {
            continue;
        }
        if (!locomotion.enabled) {
            continue;
        }

        const ray_origin = [_]f32{ pos.x, pos.y + 200, pos.z, 0 };
        const ray = zphy.RRayCast{
            .origin = ray_origin,
            .direction = ray_dir,
        };

        var ray_physics_world = ctx.physics_world;
        var ray_bodies_all = bodies_all_sim;
        var query = ray_physics_world.getNarrowPhaseQuery();
        var result = query.castRay(ray, cast_ray_args);
        if (!result.has_hit) {
            ray_physics_world = ctx.physics_world_low;
            ray_bodies_all = bodies_all_low;
            query = ctx.physics_world_low.getNarrowPhaseQuery();
            result = query.castRay(ray, cast_ray_args);
        }

        if (result.has_hit and locomotion.affected_by_gravity) {
            const dist = result.hit.fraction * ray_dir[1] * -1;
            if (dist > 200.1) {
                result.has_hit = false;
            } else {
                locomotion.affected_by_gravity = false;
            }
        }

        if (result.has_hit) {
            pos.y = ray_origin[1] + ray_dir[1] * result.hit.fraction + 0.1;

            const body_hit = zphy.tryGetBody(ray_bodies_all, result.hit.body_id).?;
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

            const rot_curr_z = rot.asZM();
            const rot_new_z = zm.slerp(rot_curr_z, rot_slope_z, slerp_factor); // TODO SmoothDamp
            const rot_new_normalized_z = zm.normalize4(rot_new_z);

            // var rot: [4]f32 = undefined;
            zm.storeArr4(rot.elems(), rot_new_normalized_z);
            // pos.y =

            // NOTE: Should this use MoveKinematic?
            // body_interface.setPositionRotationAndVelocity(
            //     body.body_id,
            //     pos.elems().*,
            //     rot,
            //     zero_vec3,
            //     zero_vec3,
            // );
        } else {
            // body_interface.setPosition(body.body_id, pos.elems().*, .dont_activate);
        }
    }
}

fn updateBodies(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const bodies = ecs.field(it, fd.PhysicsBody, 0).?;
    const positions = ecs.field(it, fd.Position, 1).?;
    const rotations = ecs.field(it, fd.Rotation, 2).?;

    const body_interface = ctx.physics_world.getBodyInterfaceMut();
    const handedness_offset = std.math.pi;
    const up_world_z = zm.f32x4(0.0, 1.0, 0.0, 1.0);
    const jolt_rot_z = zm.quatFromAxisAngle(up_world_z, handedness_offset);
    const zero_vec3 = [3]f32{ 0, 0, 0 };
    var temp_rot: [4]f32 = undefined;

    // TODO: Use BodyLockMultiRead
    // const body_lock_interface = ctx.physics_world.getBodyLockInterfaceNoLock();
    // _ = body_lock_interface; // autofix
    // var read_lock_self: zphy.BodyLockRead = .{};
    // _ = read_lock_self; // autofix

    for (bodies, positions, rotations) |body, pos, rot| {
        var body_rot_z = rot.asZM();
        body_rot_z = zm.qmul(body_rot_z, jolt_rot_z);
        const normalized_z = zm.normalize4(body_rot_z);
        zm.storeArr4(&temp_rot, normalized_z);

        // read_lock_self.lock(body_lock_interface, body.body_id);
        // defer read_lock_self.unlock();

        body_interface.setPositionRotationAndVelocity(
            body.body_id,
            pos.elemsConst().*,
            temp_rot,
            zero_vec3,
            zero_vec3,
        );
    }
}
