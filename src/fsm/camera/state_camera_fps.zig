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
const renderer = @import("../../renderer/renderer.zig");
const im3d = @import("im3d");
const zaudio = @import("zaudio");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    audio: *zaudio.Engine,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    prefab_mgr: *PrefabManager,
    renderer: *renderer.Renderer,
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
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateRest;
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
            "updateRest",
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
    const physics_world = ctx.physics_world;
    const physics_world_low = ctx.physics_world_low;
    const ui_dt = ecs.get_world_info(it.world).delta_time_raw;

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_comp = ecs.get(ctx.ecsu_world.world, player_ent, fd.Player).?;
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
        var vignette_settings = &ctx.renderer.post_processing_pass.vignette_settings;
        var player_pos = environment_info.player.?.getMut(fd.Position).?;
        const MIN_DIST_TO_ENEMY_SQ = 200 * 200;

        if (environment_info.rest_state != .not) {
            environment_info.can_journey = .invalid;
            continue;
        }

        switch (environment_info.journey_state) {
            .not => {
                environment_info.can_journey = .no;
                const z_mat = zm.loadMat43(transform.matrix[0..]);
                const z_pos = zm.util.getTranslationVec(z_mat);
                const z_fwd = zm.util.getAxisZ(z_mat);

                const dist = 5000;
                var bodies = physics_world.getBodiesUnsafe();
                var query = physics_world.getNarrowPhaseQuery();
                const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
                const ray_dir = [_]f32{ z_fwd[0] * dist, z_fwd[1] * dist, z_fwd[2] * dist, 0 };
                const ray = zphy.RRayCast{
                    .origin = ray_origin,
                    .direction = ray_dir,
                };

                var result = query.castRay(ray, .{});
                if (!result.has_hit) {
                    bodies = physics_world_low.getBodiesUnsafe();
                    query = physics_world_low.getNarrowPhaseQuery();
                    result = query.castRay(ray, .{});

                    if (!result.has_hit) {
                        environment_info.can_journey = .invalid;
                        continue;
                    }
                }

                const body_hit_opt = zphy.tryGetBody(bodies, result.hit.body_id);
                if (body_hit_opt == null) {
                    environment_info.can_journey = .invalid;
                    continue;
                }

                const body_hit = body_hit_opt.?;
                const hit_pos = ray.getPointOnRay(result.hit.fraction);
                const hit_normal = body_hit.getWorldSpaceSurfaceNormal(result.hit.sub_shape_id, hit_pos);

                var color = im3d.Im3d.Color.init5b(1, 1, 1, 1);
                // defer im3d.Im3d.DrawLine(
                //     &.{
                //         .x = hit_pos[0],
                //         .y = hit_pos[1],
                //         .z = hit_pos[2],
                //     },
                //     &.{
                //         .x = hit_pos[0] + hit_normal[0] * 250,
                //         .y = hit_pos[1] + hit_normal[1] * 250,
                //         .z = hit_pos[2] + hit_normal[2] * 250,
                //     },
                //     1,
                //     color,
                // );

                const height_next = ray_origin[1] + ray_dir[1] * result.hit.fraction;
                if (config.ocean_level + 10 > height_next) {
                    // std.log.info("can't journey due to height {d}", .{height_next});
                    color.setG(0);
                    color.setB(0);
                    environment_info.can_journey = .invalid;
                    return;
                }

                if (height_next > 700) {
                    // std.log.info("can't journey due to height {d}", .{height_next});
                    color.setG(0);
                    color.setB(0);
                    environment_info.can_journey = .no;
                    return;
                }

                const height_prev = player_pos.y;

                const walk_meter_per_second = 1.35;
                const height_term = @max(1.0, height_prev * 0.01 + height_next * 0.01);
                const walk_winding = 1.2;
                const height_factor = height_term;
                const dist_as_the_crow_flies = result.hit.fraction * dist;
                const dist_travel = walk_winding * dist_as_the_crow_flies;
                const time_fudge = 4.0 / 24.0;
                const duration = time_fudge * height_factor * dist_travel / walk_meter_per_second;

                if (dist_as_the_crow_flies < 100) {
                    // TODO trigger sound
                    // std.log.info("can't journey due to distance {d}", .{dist_as_the_crow_flies});
                    color.setG(0);
                    color.setB(0);
                    environment_info.can_journey = .invalid;
                    continue;
                }

                const next_time_of_day = environment_info.world_time + duration;
                const time_of_day_percent = std.math.modf(next_time_of_day / (4 * 60 * 60)).fpart;
                const is_day = time_of_day_percent > 0.95 or time_of_day_percent < 0.45;
                if (!is_day) {
                    // TODO trigger sound
                    color.setG(0);
                    color.setB(0);
                    // std.log.info("can't journey due to time {d} duration {d} percent {d}", .{ environment_info.world_time, duration, time_of_day_percent });
                    continue;
                }

                if (dist_as_the_crow_flies > 40000) {
                    // TODO trigger sound
                    // std.log.info("can't journey due to distance {d}", .{dist_as_the_crow_flies});
                    color.setG(0);
                    color.setB(0);
                    environment_info.can_journey = .no;
                    continue;
                }

                const hit_normal_z = zm.loadArr3(hit_normal);
                const up_z = zm.f32x4(0, 1, 0, 0);
                const dot = zm.dot3(up_z, hit_normal_z)[0];
                if (dot < 0.5) {
                    // TODO trigger sound
                    // std.log.info("can't journey due to slope {d}", .{hit_normal[1]});
                    color.setG(0);
                    color.setB(0);
                    environment_info.can_journey = .no;
                    continue;
                }

                const slime_ent = ecs.lookup(ctx.ecsu_world.world, "mama_slime");
                if (slime_ent != 0 and ecs.is_alive(ctx.ecsu_world.world, slime_ent)) {
                    const slime_transform_opt = ecs.get(ctx.ecsu_world.world, slime_ent, fd.Transform);
                    if (slime_transform_opt) |slime_transform| {
                        const slime_pos = slime_transform.getPos();
                        const slime_pos_z = zm.loadArr3(slime_pos[0..3].*);
                        const self_pos_z = player_pos.asZM();
                        const vec_to_slime = (slime_pos_z - self_pos_z) * zm.Vec{ 1, 0, 1, 0 };
                        const dist_to_slime_sq = zm.lengthSq3(vec_to_slime)[0];
                        if (dist_to_slime_sq < MIN_DIST_TO_ENEMY_SQ) {
                            // std.log.info("can't journey due to near1 {d:.2}", .{dist_to_slime_sq});
                            return;
                        }
                    }
                    // {
                    //     const self_pos_z = zm.Vec{
                    //         ray_origin[0] + ray_dir[0] * result.hit.fraction,
                    //         height_next,
                    //         ray_origin[2] + ray_dir[0] * result.hit.fraction,
                    //         0,
                    //     };
                    //     const vec_to_slime = (slime_pos_z - self_pos_z) * zm.Vec{ 1, 0, 1, 0 };
                    //     const dist_to_slime_sq = zm.lengthSq3(vec_to_slime)[0];
                    //     if (dist_to_slime_sq < MIN_DIST_TO_ENEMY_SQ) {
                    //         // std.log.info("can't journey due to near2 {d:.2}", .{dist_to_slime_sq});
                    //         return;
                    //     }
                    // }
                }

                const duration_percent = std.math.clamp(duration / 5000, 0, 1);
                environment_info.journey_time_percent_predict = duration_percent;

                environment_info.can_journey = .yes;
                if (!input_frame_data.just_pressed(config.input.interact)) {
                    return;
                }

                environment_info.journey_destination = .{
                    ray_origin[0] + ray_dir[0] * result.hit.fraction,
                    height_next,
                    ray_origin[2] + ray_dir[2] * result.hit.fraction,
                };

                environment_info.journey_time_multiplier = 100 + dist_as_the_crow_flies * 0.5;
                environment_info.journey_time_end = environment_info.world_time + duration;
                std.log.info("time:{d} distcrow:{d} dist:{d} duration_h:{d} height_factor{d} end:{d}", .{
                    environment_info.world_time,
                    dist_as_the_crow_flies,
                    dist_travel,
                    duration / 3600.0,
                    height_factor,
                    environment_info.journey_time_end.?,
                });

                environment_info.journey_time_multiplier = 10 + dist_as_the_crow_flies * 0.25;
                environment_info.player_state_time = 0;
                environment_info.journey_state = .transition_in;
            },
            .transition_in => {
                environment_info.player_state_time += ui_dt * 4;
                if (environment_info.player_state_time >= 1) {
                    environment_info.player_state_time = 1;

                    player_pos.x = environment_info.journey_destination[0];
                    player_pos.y = environment_info.journey_destination[1];
                    player_pos.z = environment_info.journey_destination[2];

                    environment_info.journey_state = .journeying;
                }
                vignette_settings.feather = 1 - environment_info.player_state_time * 1.0;
                vignette_settings.radius = 1 - environment_info.player_state_time * 1.0;
                player_comp.ambience_birds.setVolume(std.math.lerp(player_comp.ambience_birds.getVolume(), 1 - environment_info.player_state_time, environment_info.player_state_time));
            },
            .journeying => {
                if (environment_info.journey_time_end.? < environment_info.world_time) {
                    std.log.info("done time:{d}", .{environment_info.world_time});
                    environment_info.journey_time_end = null;
                    environment_info.journey_time_multiplier = 1;
                    environment_info.journey_state = .transition_out;
                }
            },
            .transition_out => {
                environment_info.player_state_time -= ui_dt * 2;
                if (environment_info.player_state_time <= 0) {
                    environment_info.player_state_time = 0;
                    environment_info.journey_state = .not;
                }
                vignette_settings.feather = 1 - environment_info.player_state_time * 0.9;
                vignette_settings.radius = 1 - environment_info.player_state_time * 0.9;
            },
        }

        // if (environment_info.journey_time_end) |journey_time| {
        //     // std.log.info("time:{d}", .{environment_info.world_time});
        //     if (journey_time < environment_info.world_time) {
        //         std.log.info("done time:{d}", .{environment_info.world_time});
        //         environment_info.journey_time_end = null;
        //         environment_info.journey_time_multiplier = 1;
        //     }

        //     const slime_ent = ecs.lookup(ctx.ecsu_world.world, "mama_slime");
        //     if (ecs.is_alive(ctx.ecsu_world.world, slime_ent)) {
        //         const slime_pos = ecs.get(ctx.ecsu_world.world, slime_ent, fd.Position).?;
        //         const slime_pos_z = slime_pos.asZM();
        //         const self_pos_z = player_pos.asZM();
        //         const vec_to_slime = (slime_pos_z - self_pos_z) * zm.Vec{ 1, 0, 1, 0 };
        //         const dist_to_slime_sq = zm.lengthSq3(vec_to_slime)[0];
        //         if (dist_to_slime_sq < MIN_DIST_TO_ENEMY_SQ) {
        //             environment_info.journey_time_end = null;
        //             environment_info.journey_time_multiplier = 1;
        //             return;
        //         }
        //     }
        // }
    }
}

var slime_cooldown: f64 = 1;
var slime_burst = false;

fn updateRest(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    const transforms = ecs.field(it, fd.Transform, 2).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;
    const positions = ecs.field(it, fd.Position, 4).?;
    const journeys = ecs.field(it, fd.Journey, 5).?;

    const input_frame_data = ctx.input_frame_data;
    const physics_world_low = ctx.physics_world_low;
    const physics_world = ctx.physics_world;
    var environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    var vignette_settings = &ctx.renderer.post_processing_pass.vignette_settings;

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_comp = ecs.get(ctx.ecsu_world.world, player_ent, fd.Player).?;

    // TODO: No, interaction shouldn't be in camera.. :)
    for (inputs, cameras, transforms, rotations, positions, journeys) |input_comp, cam, transform, *rot, *pos, *journey| {
        _ = rot; // autofix
        _ = pos; // autofix
        _ = journey; // autofix
        _ = input_comp; // autofix
        _ = cam; // autofix

        const z_mat = zm.loadMat43(transform.matrix[0..]);
        const z_pos = zm.util.getTranslationVec(z_mat);
        const z_fwd = zm.util.getAxisZ(z_mat);

        const near_mama = blk: {
            const slime_ent = ecs.lookup(ctx.ecsu_world.world, "mama_slime");
            if (slime_ent != 0 and ecs.is_alive(ctx.ecsu_world.world, slime_ent)) {
                const MIN_DIST_TO_ENEMY_SQ = 200 * 200;
                const slime_pos = ecs.get(ctx.ecsu_world.world, slime_ent, fd.Position).?;
                const target_pos_z = slime_pos.asZM();
                const player_pos = environment_info.player.?.get(fd.Position).?;
                const self_pos_z = player_pos.asZM();
                const vec_to_target = (target_pos_z - self_pos_z) * zm.Vec{ 1, 0, 1, 0 };
                const dist_to_target_sq = zm.lengthSq3(vec_to_target)[0];
                if (dist_to_target_sq < MIN_DIST_TO_ENEMY_SQ) {
                    // std.log.info("can't journey due to near {d:.2}", .{dist_to_target_sq});
                    break :blk true;
                }
            }

            break :blk false;
        };

        if (environment_info.journey_time_end != null) {
            continue;
        }

        const time_of_day_percent = std.math.modf(environment_info.world_time / (4 * 60 * 60)).fpart;
        const is_night = time_of_day_percent < 0.8 and time_of_day_percent > 0.5;
        const is_morning = time_of_day_percent < 0.1;
        const ui_dt = ecs.get_world_info(it.world).delta_time_raw;

        const DIST_TO_LIGHT = 30;
        var it_inner = ecs.each(ctx.ecsu_world.world, fd.PointLight);
        const has_nearby_light: bool = blk: {
            while (ecs.each_next(&it_inner)) {
                for (it_inner.entities()) |ent_light| {
                    const transform_light_opt = ecs.get(ctx.ecsu_world.world, ent_light, fd.Transform);
                    if (transform_light_opt) |transform_light| {
                        const light_pos = transform_light.getPos();
                        const light_pos_z = zm.loadArr3(light_pos[0..3].*);
                        if (zm.lengthSq3(z_pos - light_pos_z)[0] < DIST_TO_LIGHT * DIST_TO_LIGHT) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        };

        slime_cooldown -= it.delta_time;
        const can_burst = slime_burst or (!has_nearby_light and is_night);
        // if (!is_day and !has_nearby_light and slime_cooldown < 0) {
        if (can_burst and slime_cooldown < 0) {
            var it_slimes = ecs.each(ctx.ecsu_world.world, fd.SettlementEnemy);
            var slime_count: usize = 0;
            while (ecs.each_next(&it_slimes)) {
                slime_count += it_slimes.entities().len;
            }

            if (slime_count > 15) {
                slime_burst = false;
                slime_cooldown = 60;
            } else {
                slime_burst = true;
                slime_cooldown = 1;
            }
            std.log.info("slimes {d} cooldown {d}", .{ slime_count, slime_cooldown });
            const offset = .{
                std.crypto.random.float(f32) * 15,
                0,
                std.crypto.random.float(f32) * 15,
            };
            for (0..3) |i| {
                // spawn slime
                const i_f: f32 = @floatFromInt(i);
                var pos_slime = fd.Position.init(
                    z_pos[0] + z_fwd[0] * (15 + 3 * i_f + std.crypto.random.float(f32) * 3 + offset[0]),
                    z_pos[1],
                    z_pos[2] + z_fwd[2] * (15 + 3 * i_f + std.crypto.random.float(f32) * 3 + offset[0]),
                );

                const query = physics_world.getNarrowPhaseQuery();
                const ray_origin = [_]f32{
                    pos_slime.x,
                    pos_slime.y + 300,
                    pos_slime.z,
                    0,
                };
                const ray_dir = [_]f32{ 0, -500, 0, 0 };
                const ray = zphy.RRayCast{
                    .origin = ray_origin,
                    .direction = ray_dir,
                };
                const result = query.castRay(ray, .{});
                if (result.has_hit) {
                    const hit_pos = ray.getPointOnRay(result.hit.fraction);
                    pos_slime.y = hit_pos[1] - (3 + 1 * i_f);
                }

                var ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, config.prefab.slime);
                ent.set(pos_slime);

                const base_scale = 1 + std.crypto.random.float(f32) * 2;
                const rot_slime = fd.Rotation.initFromEulerDegrees(0, std.crypto.random.float(f32) * 360, 0);
                ent.set(fd.Scale.create(1, 1, 1));
                ent.set(rot_slime);
                ent.set(fd.Transform{});
                ent.set(fd.Dynamic{});
                ent.set(fd.Locomotion{
                    .affected_by_gravity = true,
                    .snap_to_terrain = true,
                    .speed = 5 + std.crypto.random.float(f32) * 10,
                    .speed_y = 15 + std.crypto.random.float(f32) * 10,
                });
                ent.set(fd.Enemy{
                    .base_scale = base_scale,
                    .aggressive = true,
                    .idling = false,
                    .left_bias = std.crypto.random.float(f32) > 0.5,
                    .birth_time = environment_info.world_time,
                });
                ent.add(fd.SettlementEnemy);
                ent.addPair(fd.FSM_ENEMY, fd.FSM_ENEMY_Slime);
                ent.set(fd.Health{ .value = 10 * base_scale * base_scale });

                const body_interface = ctx.physics_world.getBodyInterfaceMut();

                const shape_settings = zphy.SphereShapeSettings.create(1.5 * 1) catch unreachable;
                defer shape_settings.release();

                const root_shape_settings = zphy.DecoratedShapeSettings.createRotatedTranslated(
                    &shape_settings.asShapeSettings().*,
                    rot_slime.elemsConst().*,
                    .{ 0, 0, 0 },
                ) catch unreachable;
                defer root_shape_settings.release();
                const root_shape = root_shape_settings.createShape() catch unreachable;

                const body_id = body_interface.createAndAddBody(.{
                    .position = .{ pos_slime.x, pos_slime.y, pos_slime.z, 0 },
                    .rotation = rot_slime.elemsConst().*,
                    .shape = root_shape,
                    .motion_type = .kinematic,
                    .object_layer = config.physics.object_layers.moving,
                    .motion_quality = .discrete,
                    .user_data = ent.id,
                    .angular_damping = 0.975,
                    .inertia_multiplier = 10,
                    .friction = 0.5,
                }, .activate) catch unreachable;
                ent.set(fd.PhysicsBody{ .body_id = body_id, .shape_opt = root_shape });

                const light_ent = ctx.ecsu_world.newEntity();
                light_ent.childOf(ent);
                light_ent.set(fd.Position{ .x = 0, .y = 15, .z = 0 });
                light_ent.set(fd.Rotation.initFromEulerDegrees(0, std.crypto.random.float(f32), 0));
                light_ent.set(fd.Scale.createScalar(1));
                light_ent.set(fd.Transform{});
                light_ent.set(fd.Dynamic{});

                light_ent.set(fd.PointLight{
                    .color = .{ .r = 0.2, .g = 1, .b = 0.3 },
                    .range = 20,
                    .intensity = 4,
                });
            }
        }

        switch (environment_info.rest_state) {
            .not => {

                // Campfire
                // const query = physics_world.getNarrowPhaseQuery();
                // const ray_origin = [_]f32{
                //     z_pos[0] + z_fwd[0] * 2,
                //     z_pos[1] - 1,
                //     z_pos[2] + z_fwd[2] * 2,
                //     0,
                // };
                // const ray_dir = [_]f32{ 0, -2, 0, 0 };
                // const ray = zphy.RRayCast{
                //     .origin = ray_origin,
                //     .direction = ray_dir,
                // };
                // const result = query.castRay(ray, .{});

                const dist = 7;
                const query = physics_world_low.getNarrowPhaseQuery();
                const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
                const ray_dir = [_]f32{ z_fwd[0] * dist, z_fwd[1] * dist, z_fwd[2] * dist, 0 };
                const ray = zphy.RRayCast{
                    .origin = ray_origin,
                    .direction = ray_dir,
                };
                const result = query.castRay(ray, .{});

                if (!result.has_hit) {
                    environment_info.can_rest = .invalid;
                    continue;
                }

                const bodies = ctx.physics_world_low.getBodiesUnsafe();
                const body_hit_opt = zphy.tryGetBody(bodies, result.hit.body_id);
                if (body_hit_opt == null) {
                    environment_info.can_rest = .invalid;
                    continue;
                }

                const body_hit = body_hit_opt.?;
                const hit_pos = ray.getPointOnRay(result.hit.fraction);
                const hit_normal = body_hit.getWorldSpaceSurfaceNormal(result.hit.sub_shape_id, hit_pos);
                const hit_normal_z = zm.loadArr3(hit_normal);
                const up_z = zm.f32x4(0, 1, 0, 0);
                const dot = zm.dot3(up_z, hit_normal_z)[0];
                if (dot < 0.8) {
                    // TODO trigger sound
                    // std.log.info("can't journey due to slope {d}", .{hit_normal[1]});
                    // color.setG(0);
                    // color.setB(0);
                    environment_info.can_rest = .no;
                    continue;
                }

                // const color = if (result.has_hit) im3d.Im3d.Color.init5b(1, 1, 1, 1) else im3d.Im3d.Color.init5b(1, 0, 0, 1);
                // defer im3d.Im3d.DrawLine(
                //     &.{
                //         .x = ray_origin[0],
                //         .y = ray_origin[1],
                //         .z = ray_origin[2],
                //     },
                //     &.{
                //         .x = ray_origin[0] + ray_dir[0],
                //         .y = ray_origin[1] + ray_dir[1],
                //         .z = ray_origin[2] + ray_dir[2],
                //     },
                //     1,
                //     color,
                // );

                environment_info.can_rest = .yes;

                if (input_frame_data.just_pressed(config.input.rest)) {
                    std.log.info("rest time:{d:.2} mult:{d:.2}", .{ environment_info.world_time, environment_info.journey_time_multiplier });
                    environment_info.rest_state = .transition_in;
                    environment_info.player_state_time = 0;
                    vignette_settings.feather = 1;
                    vignette_settings.radius = 1;

                    if (!has_nearby_light) {
                        var campfire_ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, config.prefab.campfire);
                        campfire_ent.set(fd.Position{
                            .x = hit_pos[0],
                            .y = hit_pos[1] - 0.1,
                            .z = hit_pos[2],
                        });
                        campfire_ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
                        campfire_ent.set(fd.Rotation{});
                        campfire_ent.set(fd.Scale{});
                        campfire_ent.set(fd.Transform{});
                        campfire_ent.set(fd.Dynamic{});
                        campfire_ent.set(fd.PointLight{
                            .color = .{ .r = 1, .g = 0.8, .b = 0.2 },
                            .range = 10.0,
                            .intensity = 10.0,
                        });

                        player_comp.fx_fire.start() catch unreachable;
                        player_comp.fx_fire.setVolume(0);
                    }
                }
            },
            .initial_rest => {
                environment_info.player_state_time += ui_dt * 0.2;
                environment_info.journey_time_multiplier = 500;
                if (environment_info.player_state_time >= 1) {
                    environment_info.player_state_time = 1;
                    if (!is_morning) {
                        environment_info.journey_time_multiplier = 1;
                        environment_info.rest_state = .transition_out;
                    }
                }
                vignette_settings.feather = environment_info.player_state_time * 0.9;
                vignette_settings.radius = environment_info.player_state_time * 0.9;
            },
            .transition_in => {
                environment_info.player_state_time += ui_dt * 2;
                if (environment_info.player_state_time >= 1) {
                    environment_info.journey_time_multiplier = 350;
                    environment_info.player_state_time = 1;
                    environment_info.rest_state = if (is_morning) .resting_during_morning else .resting_until_morning;
                }
                player_comp.ambience_birds.setVolume(std.math.lerp(player_comp.ambience_birds.getVolume(), 1 - environment_info.player_state_time, environment_info.player_state_time));
                player_comp.fx_fire.setVolume(environment_info.player_state_time);
                vignette_settings.feather = 1 - environment_info.player_state_time * 0.3;
                vignette_settings.radius = 1 - environment_info.player_state_time * 0.3;
            },
            .resting_during_morning => {
                const exit_rest = near_mama or !is_morning or input_frame_data.just_pressed(config.input.rest);
                if (exit_rest) {
                    environment_info.rest_state = .resting_until_morning;
                }
            },
            .resting_until_morning => {
                const exit_rest = near_mama or is_morning or input_frame_data.just_pressed(config.input.rest);
                if (exit_rest) {
                    std.log.info("rest time:{d:.2} mult:{d:.2}", .{ environment_info.world_time, environment_info.journey_time_multiplier });
                    environment_info.rest_state = .transition_out;
                    environment_info.journey_time_multiplier = 1;
                }
            },
            .transition_out => {
                environment_info.player_state_time -= ui_dt * 2;
                if (environment_info.player_state_time <= 0) {
                    environment_info.player_state_time = 0;
                    environment_info.rest_state = .not;
                    player_comp.fx_fire.stop() catch unreachable;
                }
                player_comp.fx_fire.setVolume(environment_info.player_state_time);
                vignette_settings.feather = 1 - environment_info.player_state_time * 0.3;
                vignette_settings.radius = 1 - environment_info.player_state_time * 0.3;
            },
        }
    }
}
