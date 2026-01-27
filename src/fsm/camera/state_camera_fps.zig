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
            .{ .id = ecs.id(fd.CameraFPS), .inout = .In },
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
            .{ .id = ecs.id(fd.CameraFPS), .inout = .In },
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

fn updateJourney(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    const transforms = ecs.field(it, fd.Transform, 2).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;
    const positions = ecs.field(it, fd.Position, 4).?;
    // const journeys = ecs.field(it, fd.Journey, 5).?;

    const input_frame_data = ctx.input_frame_data;
    const physics_world = ctx.physics_world;
    const physics_world_low = ctx.physics_world_low;
    const ui_dt = ecs.get_world_info(it.world).delta_time_raw;

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_comp = ecs.get(ctx.ecsu_world.world, player_ent, fd.Player).?;
    const slime_ent = ecs.lookup(ctx.ecsu_world.world, "mama_slime");
    const up_z = zm.f32x4(0, 1, 0, 0);

    for (inputs, cameras, transforms, rotations, positions) |input_comp, cam, transform, *rot, *pos| {
        _ = rot; // autofix
        _ = pos; // autofix
        _ = input_comp; // autofix
        _ = cam; // autofix

        var environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
        var vignette_settings = &ctx.renderer.post_processing_pass.vignette_settings;
        var player_pos = environment_info.player.?.getMut(fd.Position).?;
        const MIN_DIST_TO_ENEMY_SQ = 200 * 200;

        if (environment_info.rest_state != .not) {
            environment_info.can_journey = .invalid;
            continue;
        }

        const z_mat = zm.loadMat43(transform.matrix[0..]);
        const z_pos = zm.util.getTranslationVec(z_mat);
        const z_fwd = zm.util.getAxisZ(z_mat);

        {
            // const journey_cam_rot = environment_info.journey_camera.?.getMut(fd.Rotation).?;

            // var journey_cam_pos = environment_info.journey_camera.?.getMut(fd.Position).?;
            const player_cam_transform = environment_info.player_camera.?.getMut(fd.Transform).?;
            // zm.storeArr3(journey_cam_pos.elems(), zm.util.getTranslationVec(player_cam_transform.asZM()));
            // const journey_cam_rot = environment_info.journey_camera.?.getMut(fd.Rotation).?;
            const player_cam_rot_z = zm.quatFromMat(player_cam_transform.asZM());
            // zm.storeArr4(journey_cam_rot.elems(), player_cam_rot_z);
            const rpy = zm.quatToRollPitchYaw(player_cam_rot_z);
            _ = rpy; // autofix
            // std.log.info("lol rpy {any}", .{rpy});
        }

        switch (environment_info.journey_state) {
            .not => {
                environment_info.can_journey = .yes;
                environment_info.journey_terrain = .good;
                environment_info.journey_dist = .good;
                environment_info.journey_time_of_day = .day;

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
                var hit_pos = ray.getPointOnRay(result.hit.fraction);
                var hit_normal = body_hit.getWorldSpaceSurfaceNormal(result.hit.sub_shape_id, hit_pos);

                var color = im3d.Im3d.Color.init5b(1, 1, 1, 1);
                const color_red = im3d.Im3d.Color.init5b(1, 0, 0, 1);
                _ = color_red; // autofix
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

                const dist_to_dest = result.hit.fraction * dist;
                var best_down_pos: [3]f32 = hit_pos;
                var best_down_hit_normal = hit_normal;

                if (ray_dir[1] > 0) {
                    for (0..5) |x| {
                        for (0..5) |z| {
                            const step_dist = dist_to_dest * 0.01;
                            const x_f: f32 = (@as(f32, @floatFromInt(x)) - 2) * step_dist;
                            const z_f: f32 = (@as(f32, @floatFromInt(z)) - 2) * step_dist;
                            const down_ray_origin = [_]f32{ hit_pos[0] + x_f, hit_pos[1] + 100, hit_pos[2] + z_f, 0 };
                            const down_ray_dir = [_]f32{ 0, -200, 0, 0 };

                            const down_ray = zphy.RRayCast{
                                .origin = down_ray_origin,
                                .direction = down_ray_dir,
                            };

                            bodies = physics_world.getBodiesUnsafe();
                            query = physics_world.getNarrowPhaseQuery();
                            var down_result = query.castRay(down_ray, .{});
                            if (!down_result.has_hit) {
                                bodies = physics_world_low.getBodiesUnsafe();
                                query = physics_world_low.getNarrowPhaseQuery();
                                down_result = query.castRay(down_ray, .{});

                                if (!down_result.has_hit) {
                                    continue;
                                }

                                const down_body_hit_opt = zphy.tryGetBody(bodies, down_result.hit.body_id);
                                if (down_body_hit_opt == null) {
                                    continue;
                                }

                                const down_body_hit = down_body_hit_opt.?;
                                const down_hit_normal = down_body_hit.getWorldSpaceSurfaceNormal(down_result.hit.sub_shape_id, hit_pos);
                                const down_hit_pos = down_ray.getPointOnRay(down_result.hit.fraction);
                                if (down_hit_pos[1] < 700 and down_hit_pos[1] > best_down_pos[1] and down_hit_normal[1] + 0.1 > hit_normal[1]) {
                                    // im3d.Im3d.DrawLine(
                                    //     &.{
                                    //         .x = down_hit_pos[0],
                                    //         .y = down_hit_pos[1],
                                    //         .z = down_hit_pos[2],
                                    //     },
                                    //     &.{
                                    //         .x = best_down_pos[0],
                                    //         .y = best_down_pos[1],
                                    //         .z = best_down_pos[2],
                                    //     },
                                    //     1,
                                    //     color,
                                    // );

                                    best_down_pos = down_hit_pos;
                                    best_down_hit_normal = down_hit_normal;
                                    // dist_to_dest =
                                    // im3d.Im3d.DrawLine(
                                    //     &.{
                                    //         .x = down_hit_pos[0],
                                    //         .y = down_hit_pos[1],
                                    //         .z = down_hit_pos[2],
                                    //     },
                                    //     &.{
                                    //         .x = down_hit_pos[0] + down_hit_normal[0] * 10,
                                    //         .y = down_hit_pos[1] + down_hit_normal[1] * 10,
                                    //         .z = down_hit_pos[2] + down_hit_normal[2] * 10,
                                    //     },
                                    //     1,
                                    //     color,
                                    // );
                                } else {
                                    // im3d.Im3d.DrawLine(
                                    //     &.{
                                    //         .x = down_hit_pos[0],
                                    //         .y = down_hit_pos[1],
                                    //         .z = down_hit_pos[2],
                                    //     },
                                    //     &.{
                                    //         .x = down_hit_pos[0] + down_hit_normal[0] * 5,
                                    //         .y = down_hit_pos[1] + down_hit_normal[1] * 5,
                                    //         .z = down_hit_pos[2] + down_hit_normal[2] * 5,
                                    //     },
                                    //     1,
                                    //     color_red,
                                    // );
                                }
                            }
                        }
                    }
                }

                hit_pos = best_down_pos;
                hit_normal = best_down_hit_normal;
                const height_next = hit_pos[1];

                if (config.ocean_level + 5 > height_next) {
                    // std.log.info("can't journey due to height {d}", .{height_next});
                    color.setG(0);
                    color.setB(0);
                    environment_info.can_journey = .invalid;
                    return;
                }

                const height_prev = player_pos.y;

                const walk_meter_per_second = 1.35;
                const height_term = @max(1.0, (height_prev - 200) * 0.01 + (height_next - 200) * 0.01);
                const walk_winding = 1.2;
                const height_factor = height_term;
                const dist_as_the_crow_flies = dist_to_dest;
                const dist_travel = walk_winding * dist_as_the_crow_flies;
                const time_fudge = 4.0 / 24.0;
                const duration = time_fudge * height_factor * dist_travel / walk_meter_per_second;

                const min_dist: f32 = if (ray_dir[1] < 0) 100 else (100 - ray_dir[1] * 70);
                if (dist_as_the_crow_flies < min_dist) {
                    // TODO trigger sound
                    // std.log.info("can't journey due to distance {d}", .{dist_as_the_crow_flies});
                    color.setG(0);
                    color.setB(0);
                    // environment_info.journey_dist = .good;
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
                    environment_info.can_journey = .no;
                    environment_info.journey_time_of_day = .night;
                    // std.log.info("can't journey due to time {d} duration {d} percent {d}", .{ environment_info.world_time, duration, time_of_day_percent });
                }

                // if (dist_as_the_crow_flies > 40000) {
                //     // TODO trigger sound
                //     // std.log.info("can't journey due to distance {d}", .{dist_as_the_crow_flies});
                //     color.setG(0);
                //     color.setB(0);
                //     environment_info.journey_dist = .far;
                //     environment_info.can_journey = .no;
                // }

                const hit_normal_z = zm.loadArr3(hit_normal);
                const dot = zm.dot3(up_z, hit_normal_z)[0];
                if (dot < 0.5) {
                    // TODO trigger sound
                    // std.log.info("can't journey due to slope {d}", .{hit_normal[1]});
                    color.setG(0);
                    color.setB(0);
                    environment_info.journey_terrain = .slopey;
                    environment_info.can_journey = .no;
                }

                if (height_next > 700) {
                    // std.log.info("can't journey due to height {d}", .{height_next});
                    color.setG(0);
                    color.setB(0);
                    environment_info.journey_terrain = .high;
                    environment_info.can_journey = .no;
                }

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
                            // return;
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
                environment_info.journey_duration_percent_predict = duration_percent;

                if (environment_info.can_journey == .no) {
                    continue;
                }

                environment_info.can_journey = .yes;
                if (!input_frame_data.just_pressed(config.input.interact)) {
                    return;
                }

                environment_info.journey_destination = hit_pos;

                environment_info.journey_time_end = environment_info.world_time + duration;
                std.log.info("time:{d} distcrow:{d} dist:{d} duration_h:{d} height_factor{d} end:{d}", .{
                    environment_info.world_time,
                    dist_as_the_crow_flies,
                    dist_travel,
                    duration / 3600.0,
                    height_factor,
                    environment_info.journey_time_end.?,
                });

                environment_info.journey_time_multiplier = 20 + dist_travel * height_factor * 0.05;
                environment_info.player_state_time = 0;
                environment_info.journey_state = .transition_in;
                environment_info.active_camera = environment_info.journey_camera;
                var player_cam = environment_info.player_camera.?.getMut(fd.Camera).?;
                var journey_cam = environment_info.journey_camera.?.getMut(fd.Camera).?;
                player_cam.active = false;
                journey_cam.active = true;
                var journey_cam_pos = environment_info.journey_camera.?.getMut(fd.Position).?;
                const player_cam_transform = environment_info.player_camera.?.getMut(fd.Transform).?;
                zm.storeArr3(journey_cam_pos.elems(), zm.util.getTranslationVec(player_cam_transform.asZM()));
                const journey_cam_rot = environment_info.journey_camera.?.getMut(fd.Rotation).?;
                const player_cam_rot_z = zm.quatFromMat(player_cam_transform.asZM());
                zm.storeArr4(journey_cam_rot.elems(), player_cam_rot_z);
            },
            .transition_in => {
                environment_info.player_state_time += ui_dt * 4;

                if (environment_info.player_state_time >= 1) {
                    environment_info.player_state_time = 1;

                    environment_info.journey_time_start = environment_info.world_time;
                    environment_info.journey_state = .journeying;
                }
                vignette_settings.feather = 1 - environment_info.player_state_time * 0.6;
                vignette_settings.radius = 1 - environment_info.player_state_time * 0.6;
                player_comp.ambience_birds.setVolume(std.math.lerp(player_comp.ambience_birds.getVolume(), 1 - environment_info.player_state_time, environment_info.player_state_time));

                var cam_pos = environment_info.journey_camera.?.getMut(fd.Position).?;
                zm.storeArr3(cam_pos.elems(), z_pos);
                cam_pos.y += environment_info.player_state_time * environment_info.player_state_time * 5;
            },
            .journeying => {
                const cam_fwd = environment_info.journey_camera.?.getMut(fd.Forward).?;
                var cam_pos = environment_info.journey_camera.?.getMut(fd.Position).?;
                var z_cam_pos = cam_pos.asZM();
                var z_dest = zm.loadArr3(environment_info.journey_destination);
                var z_start = z_pos;
                z_start[1] += 5;
                z_dest[1] += 5;

                var cam_y_prev = cam_pos.y;
                const percent = (environment_info.world_time - environment_info.journey_time_start.?) / (environment_info.journey_time_end.? - environment_info.journey_time_start.?);
                z_cam_pos = zm.lerp(z_start, z_dest, easeInOutSine(@as(f32, @floatCast(percent))));
                zm.storeArr3(cam_pos.elems(), z_cam_pos);

                var target_y: f32 = 0;
                for (0..2) |i_dir| {
                    const dir_mult: f32 = if (i_dir == 0) -1 else 1;
                    const ray_origin = [_]f32{
                        z_cam_pos[0] + cam_fwd.x * 30 * dir_mult,
                        z_cam_pos[1] + 500,
                        z_cam_pos[2] + cam_fwd.z * 30 * dir_mult,
                        0,
                    };
                    const ray_dir = [_]f32{ 0, -2000, 0, 0 };
                    const ray = zphy.RRayCast{
                        .origin = ray_origin,
                        .direction = ray_dir,
                    };
                    const query = physics_world_low.getNarrowPhaseQuery();
                    const result = query.castRay(ray, .{});
                    if (result.has_hit) {
                        const hit_pos = ray.getPointOnRay(result.hit.fraction);
                        cam_y_prev = @max(cam_y_prev, hit_pos[1] + 4);
                        target_y = @max(target_y, hit_pos[1] + 10);
                        target_y = @max(target_y, config.ocean_level + 10);
                    }
                }

                if (target_y == 0)
                    target_y = cam_pos.y;

                cam_pos.y = std.math.lerp(cam_y_prev, target_y, 0.03);
                z_cam_pos = cam_pos.asZM();

                // look at mama slime
                var ms_ray_dir_z: zm.Vec = .{ 1, 0, 0, 0 };
                if (slime_ent != 0 and ecs.is_alive(ctx.ecsu_world.world, slime_ent)) {
                    const slime_pos = ecs.get(ctx.ecsu_world.world, slime_ent, fd.Position).?;
                    const slime_pos_z = slime_pos.asZM();
                    const vec_to_slime = (slime_pos_z - z_cam_pos);
                    const ms_ray_origin = [_]f32{ cam_pos.x, cam_pos.y + 5, cam_pos.z, 0 };
                    const ms_ray_dir = [_]f32{
                        vec_to_slime[0] * 0.99,
                        vec_to_slime[1] * 0.99,
                        vec_to_slime[2] * 0.99,
                        0,
                    };
                    ms_ray_dir_z = zm.normalize3(zm.loadArr4(vec_to_slime));
                    const ms_ray = zphy.RRayCast{
                        .origin = ms_ray_origin,
                        .direction = ms_ray_dir,
                    };
                    const query = physics_world_low.getNarrowPhaseQuery();
                    const ms_result = query.castRay(ms_ray, .{});
                    if (!ms_result.has_hit) {
                        const journey_cam_transform = environment_info.journey_camera.?.get(fd.Transform).?;
                        const cam_right = zm.util.getAxisX(journey_cam_transform.asZM());
                        // const cam_up = zm.util.getAxisY(journey_cam_transform.asZM());
                        const dot_right = zm.dot3(zm.normalize3(ms_ray_dir), cam_right);
                        const rot_right = zm.quatFromAxisAngle(up_z, dot_right[0] * 0.01);
                        // const dot_up = zm.dot3(up_z, cam_up);
                        // const rot_up = zm.quatFromAxisAngle(up_z, dot_up[0] * 0.01);
                        // _ = rot_up; // autofix

                        // zm.storeArr3(journey_cam_pos.elems(), zm.util.getTranslationVec(player_cam_transform.asZM()));
                        // const journey_cam_rot = environment_info.journey_camera.?.getMut(fd.Rotation).?;
                        // const player_cam_rot_z = zm.quatFromMat(player_cam_transform.asZM());
                        // zm.storeArr4(journey_cam_rot.elems(), player_cam_rot_z);

                        // const lookat_z = zm.lookToLh(.{ 0, 0, 0, 0 }, zm.normalize3(ms_ray_dir), up_z);
                        // const lookat_z = zm.lookAtLh(z_cam_pos, slime_pos_z, up_z);
                        // const lookat_rot_z = zm.quatFromMat(lookat_z);
                        const journey_cam_rot = environment_info.journey_camera.?.getMut(fd.Rotation).?;
                        var journey_cam_rot_z = journey_cam_rot.asZM();
                        journey_cam_rot_z = zm.qmul(journey_cam_rot_z, rot_right);
                        // journey_cam_rot_z = zm.qmul(journey_cam_rot_z, rot_up);
                        journey_cam_rot.fromZM(journey_cam_rot_z);
                        const rpy = zm.quatToRollPitchYaw(journey_cam_rot.asZM());
                        const yaw = rpy[1];
                        _ = yaw; // autofix
                        // std.log.info("lol rpy {any}", .{rpy});
                        // journey_cam_rot.fromZM(zm.quatFromRollPitchYaw(0, yaw, 0));
                        // journey_cam_rot.fromZM(lookat_rot_z);
                    }
                }

                if (environment_info.journey_time_end.? < environment_info.world_time) {
                    std.log.info("done time:{d}", .{environment_info.world_time});
                    environment_info.journey_time_end = null;
                    environment_info.journey_time_multiplier = 1;
                    environment_info.journey_state = .transition_out;

                    player_pos.x = environment_info.journey_destination[0];
                    player_pos.y = environment_info.journey_destination[1];
                    player_pos.z = environment_info.journey_destination[2];
                    const journey_cam_rot = environment_info.journey_camera.?.getMut(fd.Rotation).?;
                    var journey_cam_fwd = journey_cam_rot.forward_z();
                    journey_cam_fwd[1] = 0;
                    journey_cam_fwd = zm.normalize3(journey_cam_fwd);

                    // get angle between polayer and flat journey cam
                    const player_rot_comp = environment_info.player.?.getMut(fd.Rotation).?;
                    const player_fwd = player_rot_comp.forward_z();
                    const player_right = player_rot_comp.right_z();
                    const dot_z = zm.dot3(player_fwd, journey_cam_fwd);
                    const clamped_dot_z = zm.clamp(dot_z, zm.splat(zm.Vec, -1), zm.splat(zm.Vec, 1));
                    const angle = zm.acos(clamped_dot_z);
                    const dot_right = zm.dot3(player_right, ms_ray_dir_z);
                    const real_angle = if (dot_right[0] > 0) angle[0] else -angle[0];
                    const new_player_rot_z = zm.quatFromAxisAngle(up_z, real_angle);
                    // const new_player_rot2_z = zm.qmul(new_player_rot_z, player_rot_comp.asZM());
                    const new_player_rot2_z = zm.qmul(player_rot_comp.asZM(), new_player_rot_z);

                    // const rpy = zm.quatToRollPitchYaw(journey_cam_rot.asZM());
                    // const yaw = rpy[1];
                    // rot.fromZM(zm.quatFromRollPitchYaw(0, yaw, 0));
                    player_rot_comp.fromZM(new_player_rot2_z);

                    // const rpy = zm.quatToRollPitchYaw(journey_cam_rot.asZM());
                    // const yaw = rpy[1];
                    // std.log.info("lol rpy {any}", .{rpy});
                    // journey_cam_rot.fromZM(zm.quatFromRollPitchYaw(0, yaw, 0));
                }
            },
            .transition_out => {
                environment_info.player_state_time -= ui_dt * 1;

                var cam_pos = environment_info.journey_camera.?.getMut(fd.Position).?;
                var cam_pos_z = zm.loadArr3(cam_pos.elems().*);
                cam_pos_z = zm.lerp(cam_pos_z, z_pos, 1 - environment_info.player_state_time);
                zm.storeArr3(cam_pos.elems(), cam_pos_z);
                // cam_pos.y += environment_info.player_state_time * 5;

                if (environment_info.player_state_time <= 0) {
                    environment_info.player_state_time = 0;
                    environment_info.journey_state = .not;
                    environment_info.active_camera = environment_info.player_camera;
                    var player_cam = environment_info.player_camera.?.getMut(fd.Camera).?;
                    var journey_cam = environment_info.journey_camera.?.getMut(fd.Camera).?;
                    player_cam.active = true;
                    journey_cam.active = false;
                }
                vignette_settings.feather = 1 - environment_info.player_state_time * 0.6;
                vignette_settings.radius = 1 - environment_info.player_state_time * 0.6;
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

fn easeInOutSine(x: f32) f32 {
    return -(@cos(std.math.pi * x) - 1) / 2;
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

    const input_frame_data = ctx.input_frame_data;
    const physics_world = ctx.physics_world;
    var environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    var vignette_settings = &ctx.renderer.post_processing_pass.vignette_settings;

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_comp = ecs.get(ctx.ecsu_world.world, player_ent, fd.Player).?;
    const slime_ent = ecs.lookup(ctx.ecsu_world.world, "mama_slime");

    // TODO: No, interaction shouldn't be in camera.. :)
    for (inputs, cameras, transforms, rotations, positions) |input_comp, cam, transform, *rot, *pos| {
        _ = rot; // autofix
        _ = pos; // autofix
        _ = input_comp; // autofix
        _ = cam; // autofix

        const z_mat = zm.loadMat43(transform.matrix[0..]);
        const z_pos = zm.util.getTranslationVec(z_mat);
        const z_fwd = zm.util.getAxisZ(z_mat);

        const near_mama = blk: {
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
                light_ent.set(fd.Position{ .x = 0, .y = 2, .z = 0 });
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

                const dist = 5;
                const query = physics_world.getNarrowPhaseQuery();
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

                const bodies = ctx.physics_world.getBodiesUnsafe();
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

                    // if (!has_nearby_light) {
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
                    player_comp.fx_fire.setPosition(hit_pos);
                    // }
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
                player_comp.fx_fire.setVolume(environment_info.player_state_time * 25);
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
                }
                vignette_settings.feather = 1 - environment_info.player_state_time * 0.3;
                vignette_settings.radius = 1 - environment_info.player_state_time * 0.3;
            },
        }
    }
}
