const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../core/blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../config/flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config/config.zig");
const zphy = @import("zphysics");
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
const util = @import("../../util.zig");
const context = @import("../../core/context.zig");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    prefab_mgr: *PrefabManager,
};

pub fn create(create_ctx: StateContext) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(StateContext) catch unreachable;
    update_ctx.* = StateContext.view(create_ctx);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = cameraStateFps;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_CAM, fd.FSM_CAM_Fps), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 5);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "cameraStateFps",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    // {
    //     var system_desc = ecs.system_desc_t{};
    //     system_desc.callback = updateInteract;
    //     system_desc.ctx = update_ctx;
    //     system_desc.query.terms = [_]ecs.term_t{
    //         .{ .id = ecs.id(fd.Input), .inout = .InOut },
    //         .{ .id = ecs.id(fd.Camera), .inout = .InOut },
    //         .{ .id = ecs.id(fd.Transform), .inout = .InOut },
    //         .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
    //         .{ .id = ecs.pair(fd.FSM_CAM, fd.FSM_CAM_Fps), .inout = .InOut },
    //     } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 5);
    //     _ = ecs.SYSTEM(
    //         create_ctx.ecsu_world.world,
    //         "updateInteract",
    //         ecs.OnUpdate,
    //         &system_desc,
    //     );
    // }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateJourney;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.id(fd.Journey), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 6);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateJourney",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn cameraStateFps(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    const transforms = ecs.field(it, fd.Transform, 2).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;

    const environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    if (environment_info.journey_time_multiplier != 1) {
        // return; // HACK?!
    }

    const movement_pitch = ctx.input_frame_data.get(config.input.look_pitch).number;
    for (inputs, cameras, transforms, rotations) |input_comp, cam, transform, *rot| {
        _ = transform; // autofix
        _ = input_comp; // autofix
        if (!cam.active) {
            continue;
        }

        const rot_pitch = zm.quatFromNormAxisAngle(zm.Vec{ 1, 0, 0, 0 }, movement_pitch * 0.0025);
        const rot_in = rot.asZM();
        const rot_new = zm.qmul(rot_in, rot_pitch);
        rot.fromZM(rot_new);

        const rpy = zm.quatToRollPitchYaw(rot_new);
        const rpy_constrained = .{
            std.math.clamp(rpy[0], -0.9, 0.9),
            rpy[1],
            rpy[2],
        };
        const constrained_z = zm.quatFromRollPitchYaw(rpy_constrained[0], rpy_constrained[1], rpy_constrained[2]);
        rot.fromZM(constrained_z);
    }
}

// fn updateInteract(it: *ecs.iter_t) callconv(.C) void {
//     const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

//     const inputs = ecs.field(it, fd.Input, 0).?;
//     const cameras = ecs.field(it, fd.Camera, 1).?;
//     const transforms = ecs.field(it, fd.Transform, 2).?;
//     const rotations = ecs.field(it, fd.Rotation, 3).?;

//     const input_frame_data = ctx.input_frame_data;
//     const physics_world_low = ctx.physics_world_low;
//     // TODO: No, interaction shouldn't be in camera.. :)
//     if (!input_frame_data.just_pressed(config.input.interact)) {
//         return;
//     }

//     for (inputs, cameras, transforms, rotations) |input_comp, cam, transform, *rot| {
//         _ = input_comp; // autofix
//         _ = cam; // autofix
//         _ = rot; // autofix
//         const z_mat = zm.loadMat43(transform.matrix[0..]);
//         const z_pos = zm.util.getTranslationVec(z_mat);
//         const z_fwd = zm.util.getAxisZ(z_mat);

//         const query = physics_world_low.getNarrowPhaseQuery();
//         const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
//         const ray_dir = [_]f32{ z_fwd[0] * 50, z_fwd[1] * 50, z_fwd[2] * 50, 0 };
//         const result = query.castRay(.{
//             .origin = ray_origin,
//             .direction = ray_dir,
//         }, .{});

//         if (result.has_hit) {
//             const post_pos = fd.Position.init(
//                 ray_origin[0] + ray_dir[0] * result.hit.fraction,
//                 ray_origin[1] + ray_dir[1] * result.hit.fraction,
//                 ray_origin[2] + ray_dir[2] * result.hit.fraction,
//             );
//             var post_transform = fd.Transform.initFromPosition(post_pos);
//             post_transform.setScale([_]f32{ 0.05, 2, 0.05 });

//             const cylinder_prefab = ctx.prefab_mgr.getPrefab(config.prefab.cylinder_id).?;
//             const post_ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, cylinder_prefab);
//             post_ent.set(post_pos);
//             post_ent.set(fd.Rotation{});
//             post_ent.set(fd.Scale.create(0.05, 2, 0.05));
//             post_ent.set(post_transform);

//             // const light_pos = fd.Position.init(0.0, 1.0, 0.0);
//             // const light_transform = fd.Transform.init(post_pos.x, post_pos.y + 2.0, post_pos.z);
//             // const light_ent = ecsu_world.newEntity();
//             // light_ent.childOf(post_ent);
//             // light_ent.set(light_pos);
//             // light_ent.set(light_transform);
//             // light_ent.set(fd.Light{ .radiance = .{ .r = 1, .g = 0.4, .b = 0.0 }, .range = 20 });
//         }
//     }
// }

fn updateJourney(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    const transforms = ecs.field(it, fd.Transform, 2).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;
    const positions = ecs.field(it, fd.Position, 4).?;
    const journeys = ecs.field(it, fd.Journey, 5).?;

    const input_frame_data = ctx.input_frame_data;
    const physics_world_low = ctx.physics_world_low;
    // TODO: No, interaction shouldn't be in camera.. :)
    for (inputs, cameras, transforms, rotations, positions, journeys) |input_comp, cam, transform, *rot, *pos, *journey| {
        _ = pos; // autofix
        _ = journey; // autofix
        _ = input_comp; // autofix
        _ = cam; // autofix
        _ = rot; // autofix

        // if (journey.target_position) {
        //     continue;
        // }
        var environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;

        if (environment_info.journey_time_end) |journey_time| {
            // std.log.info("time:{d}", .{environment_info.world_time});
            if (journey_time < environment_info.world_time) {
                std.log.info("done time:{d}", .{environment_info.world_time});
                environment_info.journey_time_end = null;
                environment_info.journey_time_multiplier = 1;
            }
        }

        if (!input_frame_data.just_pressed(config.input.interact)) {
            return;
        }

        const z_mat = zm.loadMat43(transform.matrix[0..]);
        const z_pos = zm.util.getTranslationVec(z_mat);
        const z_fwd = zm.util.getAxisZ(z_mat);

        const dist = 4000;
        const query = physics_world_low.getNarrowPhaseQuery();
        const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
        const ray_dir = [_]f32{ z_fwd[0] * dist, z_fwd[1] * dist, z_fwd[2] * dist, 0 };
        const result = query.castRay(.{
            .origin = ray_origin,
            .direction = ray_dir,
        }, .{});

        if (result.has_hit) {
            const height_next = ray_origin[1] + ray_dir[1] * result.hit.fraction;
            if (!(config.ocean_level + 5 < height_next and height_next < 500)) {
                return;
            }

            var player_pos = environment_info.player.?.getMut(fd.Position).?;
            const height_prev = player_pos.y;
            player_pos.x = ray_origin[0] + ray_dir[0] * result.hit.fraction;
            player_pos.y = height_next;
            player_pos.z = ray_origin[2] + ray_dir[2] * result.hit.fraction;

            const walk_meter_per_second = 1.35;
            const height_term = @max(1.0, height_prev * 0.01 + height_next * 0.01);
            const walk_winding = 1.2;
            const height_factor = height_term;
            const dist_as_the_crow_flies = result.hit.fraction * dist;
            const dist_travel = walk_winding * dist_as_the_crow_flies;
            const time_fudge = 4.0 / 24.0;
            const duration = time_fudge * height_factor * dist_travel / walk_meter_per_second;
            environment_info.journey_time_multiplier = 1000;
            environment_info.journey_time_end = environment_info.world_time + duration;
            std.log.info("time:{d} distcrow:{d} dist:{d} duration_h:{d} height_factor{d} end:{d}", .{
                environment_info.world_time,
                dist_as_the_crow_flies,
                dist_travel,
                duration / 3600.0,
                height_factor,
                environment_info.journey_time_end.?,
            });
        }
    }
}
