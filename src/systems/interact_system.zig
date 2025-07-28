const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");
const ztracy = @import("ztracy");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const fr = @import("../config/flecs_relation.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");
const config = @import("../config/config.zig");
const input = @import("../input.zig");
const EventManager = @import("../core/event_manager.zig").EventManager;
const PrefabManager = @import("../prefab_manager.zig").PrefabManager;
const context = @import("../core/context.zig");
const audio_manager = @import("../audio/audio_manager_mock.zig");
const renderer = @import("../renderer/renderer.zig");
const window = @import("../renderer/window.zig");
const AK = @import("wwise-zig");
const AK_ID = @import("wwise-ids");

const TextureHandle = renderer.TextureHandle;

pub const MovingBroadPhaseLayerFilter = extern struct {
    usingnamespace zphy.BroadPhaseLayerFilter.Methods(@This());
    __v: *const zphy.BroadPhaseLayerFilter.VTable = &vtable,

    const vtable = zphy.BroadPhaseLayerFilter.VTable{
        .shouldCollide = shouldCollide,
    };
    fn shouldCollide(self: *const zphy.BroadPhaseLayerFilter, layer: zphy.BroadPhaseLayer) callconv(.C) bool {
        _ = self;
        if (layer == config.broad_phase_layers.moving) {
            return true;
        }
        return false;
    }
};

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    event_mgr: *EventManager,
    input_frame_data: *input.FrameData,
    main_window: *window.Window,
    physics_world: *zphy.PhysicsSystem,
    prefab_mgr: *PrefabManager,
    renderer: *renderer.Renderer,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    event_mgr: *EventManager,
    input_frame_data: *input.FrameData,
    main_window: *window.Window,
    physics_world: *zphy.PhysicsSystem,
    prefab_mgr: *PrefabManager,
    renderer: *renderer.Renderer,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    state: struct {
        crosshair_ent: ecsu.Entity,
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const crosshair_texture = create_ctx.renderer.loadTexture("textures/ui/crosshair085_ui.dds");
    var crosshair_ent = create_ctx.ecsu_world.newEntity();
    crosshair_ent.set(fd.UIImage{ .rect = [4]f32{ 0, 0, 0, 0 }, .material = .{
        .color = [4]f32{ 1, 1, 1, 1 },
        .texture = crosshair_texture,
    } });

    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .crosshair_ent = crosshair_ent,
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateCrosshair;
        system_desc.ctx = update_ctx;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateCrosshair",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateInteractors;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Interactor), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateInteractors",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateArrows;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.PhysicsBody), .inout = .InOut },
            .{ .id = ecs.id(fd.Projectile), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateArrows",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    create_ctx.event_mgr.registerListener(config.events.frame_collisions_id, onEventFrameCollisions, update_ctx);
}

fn updateInteractors(it: *ecs.iter_t) callconv(.C) void {
    const system: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const interactors = ecs.field(it, fd.Interactor, 0).?;
    // const transforms = ecs.field(it, fd.transform, 1).?;

    const ecs_world = system.ecsu_world.world;
    var environment_info = system.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const world_time = environment_info.world_time;

    const wielded_use_primary_held = system.input_frame_data.held(config.input.wielded_use_primary);
    const wielded_use_secondary_held = system.input_frame_data.held(config.input.wielded_use_secondary);
    const wielded_use_held = wielded_use_primary_held or wielded_use_secondary_held;
    _ = wielded_use_held;
    const wielded_use_primary_pressed = system.input_frame_data.just_pressed(config.input.wielded_use_primary);
    const wielded_use_primary_released = system.input_frame_data.just_released(config.input.wielded_use_primary);
    const arrow_prefab = system.prefab_mgr.getPrefab(config.prefab.arrow_id).?;

    for (interactors) |interactor_comp| {
        const item_ent_id = interactor_comp.wielded_item_ent_id;
        var weapon_comp = ecs.get_mut(ecs_world, item_ent_id, fd.ProjectileWeapon).?;

        if (weapon_comp.chambered_projectile == 0 and weapon_comp.cooldown < world_time) {
            // Load new projectile
            var proj_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, arrow_prefab);
            proj_ent.set(fd.Position{ .x = -0.03, .y = 0, .z = -0.5 });
            proj_ent.set(fd.Transform.initFromPosition(.{ .x = -0.03, .y = 0, .z = -0.5 }));
            proj_ent.set(fd.Projectile{});
            proj_ent.childOf(item_ent_id);
            weapon_comp.chambered_projectile = proj_ent.id;
            continue;
        }

        const player_ent_id = ecs.lookup(ecs_world, "main_player");
        if (player_ent_id != 0) {
            const camera_ent = ecsu.Entity.init(ecs_world, ecs.lookup_child(ecs_world, player_ent_id, "playercamera"));
            if (camera_ent.isValid() and camera_ent.isAlive()) {
                var camera_comp = camera_ent.getMut(fd.Camera).?;
                const do_zoom = wielded_use_secondary_held or (wielded_use_primary_held and weapon_comp.chambered_projectile != 0 and weapon_comp.charge > 0.25);
                const target_fov: f32 =
                    if (do_zoom)
                        (0.25 - 0.15 * weapon_comp.charge * weapon_comp.charge)
                    else
                        0.25;
                camera_comp.fov = std.math.lerp(camera_comp.fov, target_fov * math.pi, 0.3);
            }
        }

        var item_pos = ecs.get_mut(ecs_world, item_ent_id, fd.Position).?;
        const target_pos_x: f32 = if (wielded_use_secondary_held or (wielded_use_primary_held and weapon_comp.chambered_projectile != 0)) 0.25 else 0.0;
        const target_pos_y: f32 = if (wielded_use_secondary_held or (wielded_use_primary_held and weapon_comp.chambered_projectile != 0)) 0 else -0.25;
        // const target_pos_z: f32 = if (wielded_use_secondary_held or (wielded_use_primary_held and weapon_comp.chambered_projectile != 0)) 0 else -0.15;
        item_pos.x = std.math.lerp(item_pos.x, target_pos_x, 0.03);
        item_pos.y = std.math.lerp(item_pos.y, target_pos_y, 0.03);
        // item_pos.z = std.math.lerp(item_pos.z, target_pos_z, 0.03);

        var item_rot = ecs.get_mut(ecs_world, item_ent_id, fd.Rotation).?;
        var axis = zm.f32x4s(0);
        var angle: f32 = 0;
        zm.quatToAxisAngle(item_rot.asZM(), &axis, &angle);
        const target_roll_angle: f32 = if (wielded_use_secondary_held or (wielded_use_primary_held and weapon_comp.chambered_projectile != 0)) -0.1 else -1.25;
        const target_rot_z = zm.quatFromNormAxisAngle(config.ROLL_Z, target_roll_angle);
        const final_rot_z = zm.slerp(item_rot.asZM(), target_rot_z, 0.1);
        item_rot.fromZM(final_rot_z);

        if (weapon_comp.chambered_projectile == 0) {
            continue;
        }

        var proj_ent = ecsu.Entity.init(ecs_world, weapon_comp.chambered_projectile);
        if (wielded_use_primary_released) {
            // Shoot arrow
            weapon_comp.cooldown = world_time + 0.2;
            const charge = weapon_comp.charge;
            weapon_comp.charge = 0;

            weapon_comp.chambered_projectile = 0;
            proj_ent.removePair(ecs.ChildOf, item_ent_id);

            const body_interface = system.physics_world.getBodyInterfaceMut();

            const proj_transform = proj_ent.get(fd.Transform).?;
            const proj_pos_world = proj_transform.getPos00();
            const proj_rot_world = proj_transform.getRotQuaternion();
            const proj_rot_world_flip_z = zm.quatFromAxisAngle(zm.f32x4(0.0, 1.0, 0.0, 0.0), std.math.pi);
            const proj_rot_world_z = zm.qmul(proj_rot_world_flip_z, zm.loadArr4(proj_rot_world));
            var proj_rot_world_physics: [4]f32 = undefined;
            zm.storeArr4(&proj_rot_world_physics, proj_rot_world_z);

            const proj_shape_settings = zphy.BoxShapeSettings.create(.{ 0.15, 0.15, 1.0 }) catch unreachable;
            defer proj_shape_settings.release();

            const proj_shape = proj_shape_settings.createShape() catch unreachable;

            const proj_body_id = body_interface.createAndAddBody(.{
                .position = .{ proj_pos_world[0], proj_pos_world[1], proj_pos_world[2], 0 },
                .rotation = proj_rot_world_physics,
                .shape = proj_shape,
                .motion_type = .dynamic,
                .object_layer = config.object_layers.moving,
                .motion_quality = .linear_cast,
                .user_data = proj_ent.id,
            }, .activate) catch unreachable;

            //  Assign to flecs component
            proj_ent.set(fd.PhysicsBody{
                .body_id = proj_body_id,
                .shape_opt = proj_shape,
            });

            // Light
            proj_ent.set(fd.PointLight{
                .color = .{ .r = 1, .g = 1, .b = 0.5 },
                .range = 5.0,
                .intensity = 0.5,
            });

            // Speed
            const speed = 30 + charge * 180;
            proj_ent.set(fd.Speed{ .value = speed });

            // Send it flying
            const item_transform = ecs.get(ecs_world, item_ent_id, fd.Transform).?;
            const world_transform_z = zm.loadMat43(&item_transform.matrix);
            const forward_z = zm.util.getAxisZ(world_transform_z);
            const up_z = zm.f32x4(0, 1, 0, 0);
            const velocity_z = forward_z * zm.f32x4s(speed) + up_z * zm.f32x4s(1 + charge * 2);
            var velocity: [3]f32 = undefined;
            zm.storeArr3(&velocity, velocity_z);
            body_interface.setLinearVelocity(proj_body_id, velocity);

            // _ = AK.SoundEngine.postEventID(AK_ID.EVENTS.BOWFIRE, config.audio_player_oid, .{}) catch unreachable;
        } else if (wielded_use_primary_held) {
            // Pull string
            if (wielded_use_primary_pressed) {
                // playingID = AK.SoundEngine.postEventID(AK_ID.EVENTS.BOWPULL, config.audio_player_oid, .{}) catch unreachable;
            }

            environment_info.time_multiplier = 0.25;
            var proj_pos = ecs.get_mut(ecs_world, proj_ent.id, fd.Position).?;

            proj_pos.z = zm.lerpV(proj_pos.z, -0.7, 0.02);
            weapon_comp.charge = zm.mapLinearV(proj_pos.z, -0.4, -0.8, 0, 1);
        } else {
            // Relax string
            // if (playingID != 0) {
            //     AK.SoundEngine.executeActionOnPlayingID(
            //         .stop,
            //         playingID,
            //         .{ .transition_duration = 200 },
            //     );
            //     playingID = 0;
            // }
            var proj_pos = ecs.get_mut(ecs_world, proj_ent.id, fd.Position).?;
            proj_pos.z = zm.lerpV(proj_pos.z, -0.4, 0.1);
        }
    }
}

fn updateArrows(it: *ecs.iter_t) callconv(.C) void {
    const system: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const bodies = ecs.field(it, fd.PhysicsBody, 0).?;
    const projecties = ecs.field(it, fd.Projectile, 1).?;

    const body_interface = system.physics_world.getBodyInterfaceMut();

    const up_world_z = zm.f32x4(0.0, 1.0, 0.0, 1.0);
    const cylinder_prefab = system.prefab_mgr.getPrefab(config.prefab.cylinder_id).?;
    for (bodies, projecties) |body, projectile| {
        _ = projectile; // autofix
        const velocity = body_interface.getLinearVelocity(body.body_id);
        const velocity_z = zm.loadArr3(velocity);
        if (zm.length3(velocity_z)[0] < 0.01) {
            continue;
        }
        const direction_z = zm.normalize3(velocity_z);
        if (@abs(direction_z[1]) > 0.99) {
            continue;
        }

        const right_z = zm.normalize3(zm.cross3(direction_z, up_world_z));
        const up_local_z = zm.normalize3(zm.cross3(right_z, direction_z));

        const look_to_z = zm.lookToRh(zm.f32x4(0, 0, 0, 0), direction_z, up_local_z);
        const look_to_jolt_z = zm.transpose(look_to_z);
        const rot_z = zm.matToQuat(look_to_jolt_z);
        var rot: [4]f32 = undefined;
        zm.storeArr4(&rot, rot_z);

        body_interface.setRotation(body.body_id, rot, .dont_activate);
        if (velocity[1] < 0) {
            const anti_force: [3]f32 = .{
                0, -1000, 0,
            };
            body_interface.addForce(body.body_id, anti_force);
        }

        // trail
        const world_pos = body_interface.getCenterOfMassPosition(body.body_id);
        var fx_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, cylinder_prefab);
        fx_ent.set(fd.Position{ .x = world_pos[0], .y = world_pos[1], .z = world_pos[2] });
        fx_ent.set(fd.Rotation{});
        fx_ent.set(fd.Scale.createScalar(1));
        fx_ent.set(fd.Transform.init(0, 0, 0));
        fx_ent.set(fd.Forward{});
        fx_ent.set(fd.Dynamic{});

        const tli_fx = config.events.TimelineInstanceData{
            .ent = fx_ent.id,
            .timeline = IdLocal.init("particle_trail"),
        };

        system.event_mgr.triggerEvent(config.events.onAddTimelineInstance_id, &tli_fx);
    }
}

fn updateCrosshair(it: *ecs.iter_t) callconv(.C) void {
    const system: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    var crosshair_color = [4]f32{ 0.8, 0.8, 0.8, 0.75 };

    var cam_ent = util.getActiveCameraEnt(system.ecsu_world);
    const cam_comps = cam_ent.getComps(struct {
        camera: *fd.Camera,
        fwd: *fd.Forward,
        transform: *fd.Transform,
    });
    if (cam_comps.camera.class == 1) {
        const query = system.physics_world.getNarrowPhaseQuery();

        const z_mat = zm.loadMat43(cam_comps.transform.matrix[0..]);
        var z_pos = zm.util.getTranslationVec(z_mat);
        const z_fwd = zm.util.getAxisZ(z_mat);
        z_pos[0] += z_fwd[0] * 0.1;
        z_pos[1] += z_fwd[1] * 0.1;
        z_pos[2] += z_fwd[2] * 0.1;

        const ray_distance = 100.0;
        const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
        const ray_dir = [_]f32{ z_fwd[0] * ray_distance, z_fwd[1] * ray_distance, z_fwd[2] * ray_distance, 0 };

        const result = query.castRay(
            .{
                .origin = ray_origin,
                .direction = ray_dir,
            },
            .{
                .broad_phase_layer_filter = @ptrCast(&MovingBroadPhaseLayerFilter{}),
            },
        );

        if (result.has_hit) {
            crosshair_color = [4]f32{ 1.0, 0.0, 0.0, 1.0 };
        }
    }

    const crosshair_size: f32 = 32;
    const crosshair_half_size: f32 = crosshair_size / 2;
    const screen_center_x: f32 = @as(f32, @floatFromInt(system.main_window.frame_buffer_size[0])) / 2;
    const screen_center_y: f32 = @as(f32, @floatFromInt(system.main_window.frame_buffer_size[1])) / 2;

    const top = screen_center_y - crosshair_half_size;
    const bottom = screen_center_y + crosshair_half_size;
    const left = screen_center_x - crosshair_half_size;
    const right = screen_center_x + crosshair_half_size;

    const ui_image = system.state.crosshair_ent.getMut(fd.UIImage).?;
    ui_image.*.rect = [4]f32{ top, bottom, left, right };
    ui_image.*.material.color = crosshair_color;
}

//  ██████╗ █████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗███████╗
// ██╔════╝██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
// ██║     ███████║██║     ██║     ██████╔╝███████║██║     █████╔╝ ███████╗
// ██║     ██╔══██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ╚════██║
// ╚██████╗██║  ██║███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗███████║
//  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

fn onEventFrameCollisions(ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void {
    _ = event_id;
    var system: *SystemUpdateContext = @alignCast(@ptrCast(ctx));
    const body_interface = system.physics_world.getBodyInterfaceMut();
    const frame_collisions_data = util.castOpaqueConst(config.events.FrameCollisionsData, event_data);
    const ecs_world = system.ecsu_world.world;
    const ecs_proj_id = ecs.id(fd.Projectile);

    var arena_state = std.heap.ArenaAllocator.init(system.heap_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var removed_entities = std.ArrayList(ecs.entity_t).initCapacity(arena, 32) catch unreachable;

    for (frame_collisions_data.contacts) |contact| {
        if (!body_interface.isAdded(contact.body_id2)) {
            continue;
        }

        const ent1 = contact.ent1;
        const ent2 = contact.ent2;
        if (std.mem.indexOfScalar(ecs.entity_t, removed_entities.items, ent1) != null) {
            // std.debug.print("fail1 {any}\n", .{ent1});
            continue;
        }
        if (std.mem.indexOfScalar(ecs.entity_t, removed_entities.items, ent2) != null) {
            // std.debug.print("fail2 {any}\n", .{ent2});
            continue;
        }

        const contact_base_offset_z = zm.loadArr4(contact.manifold.base_offset);
        const contact_point1_z = zm.loadArr4(contact.manifold.shape1_relative_contact.points[0]);
        const contact_point_world_z = contact_base_offset_z + contact_point1_z;
        _ = contact_point_world_z;

        const ent1_alive = ent1 != 0 and ecs.is_alive(ecs_world, ent1);
        const ent2_alive = ent2 != 0 and ecs.is_alive(ecs_world, ent2);
        const ent1_is_proj = ent1_alive and ecs.has_id(ecs_world, ent1, ecs_proj_id);
        const ent2_is_proj = ent2_alive and ecs.has_id(ecs_world, ent2, ecs_proj_id);
        if (ent1_is_proj and ent2_is_proj) {
            continue;
        }

        if (!ent1_is_proj and !ent2_is_proj) {
            continue;
        }

        const proj_ent = if (ent1_is_proj) ent1 else ent2;
        const hit_ent = if (ent1_is_proj) ent2 else ent1;
        const proj_body = if (ent1_is_proj) contact.body_id1 else contact.body_id2;
        const hit_body = if (ent1_is_proj) contact.body_id2 else contact.body_id1;
        // const proj_alive = (ent1_is_proj and ent1_alive) or (ent2_is_proj and ent2_alive);
        const hit_alive = (ent1_is_proj and ent2_alive) or (ent2_is_proj and ent1_alive);

        // std.debug.print("proj1 {any} body:{any}\n", .{contact.ent1, proj_body});
        const pos = body_interface.getCenterOfMassPosition(proj_body);
        const velocity = body_interface.getLinearVelocity(proj_body);
        body_interface.removeAndDestroyBody(proj_body);
        ecs.remove(ecs_world, proj_ent, fd.PhysicsBody);
        // ecs.remove(ecs_world, proj_ent, fd.PointLight);
        removed_entities.append(proj_ent) catch unreachable;

        system.event_mgr.triggerEvent(
            config.events.onAddTimelineInstance_id,
            &config.events.TimelineInstanceData{
                .ent = proj_ent,
                .timeline = IdLocal.init("despawn"),
            },
        );

        // const oid = 1000 + proj_ent;
        // AK.SoundEngine.registerGameObj(oid) catch unreachable;
        // defer AK.SoundEngine.unregisterGameObj(oid) catch {};
        // const ak_pos = AK.AkSoundPosition{
        //     .position = .{
        //         .x = pos[0],
        //         .y = pos[1],
        //         .z = pos[2],
        //     },
        //     .orientation_front = .{
        //         .z = 1.0,
        //     },
        //     .orientation_top = .{
        //         .y = 1.0,
        //     },
        // };
        // AK.SoundEngine.setPosition(oid, ak_pos, .{}) catch unreachable;
        // AK.SoundEngine.setSwitchID(AK_ID.SWITCHES.HITMATERIAL.GROUP, AK_ID.SWITCHES.HITMATERIAL.SWITCH.GRAVEL, oid) catch unreachable;

        if (hit_alive and ecs.has_id(ecs_world, hit_ent, ecs.id(fd.Health))) {
            const transform_target = ecs.get(ecs_world, hit_ent, fd.Transform).?;
            const transform_proj = ecs.get(ecs_world, proj_ent, fd.Transform).?;
            const transform_target_z = transform_target.asZM();
            var transform_proj_z = transform_proj.asZM();
            var translation_proj_z = zm.util.getTranslationVec(transform_proj_z);
            const forward_proj_z = zm.util.getAxisZ(transform_proj_z);
            translation_proj_z = translation_proj_z + forward_proj_z * zm.splat(zm.F32x4, 0.6);
            zm.util.setTranslationVec(&transform_proj_z, translation_proj_z);

            const transform_target_inv_z = zm.inverse(transform_target_z);
            const mat_z = zm.mul(transform_proj_z, transform_target_inv_z);
            const pos_z = zm.util.getTranslationVec(mat_z);
            const rot_z = zm.matToQuat(mat_z);
            var pos_proj = ecs.get_mut(ecs_world, proj_ent, fd.Position).?;
            var rot_proj = ecs.get_mut(ecs_world, proj_ent, fd.Rotation).?;
            pos_proj.fromZM(pos_z);
            rot_proj.fromZM(rot_z);

            ecs.add_id(ecs_world, proj_ent, system.ecsu_world.pair(ecs.ChildOf, hit_ent));

            var hit_health = ecs.get_mut(ecs_world, hit_ent, fd.Health).?;
            if (hit_health.value > 0) {
                const speed = ecs.get(ecs_world, proj_ent, fd.Speed).?.value;
                const damage = (speed - 30) * (speed - 30);
                std.log.info("speed {d:5.2} damage {d:5.2}\n", .{ speed, damage });
                hit_health.value -= damage;
                if (hit_health.value <= 0) {
                    body_interface.setMotionType(hit_body, .dynamic, .activate);
                    body_interface.addImpulseAtPosition(
                        hit_body,
                        .{
                            velocity[0] * 10,
                            velocity[1] * 0,
                            velocity[2] * 10,
                        },
                        pos,
                    );

                    // ecs.remove(ecs_world, hit_ent, fd.FSM);
                    ecs.remove(ecs_world, hit_ent, fd.PointLight);
                    ecs.remove(ecs_world, hit_ent, fd.SettlementEnemy);

                    const tli_despawn = config.events.TimelineInstanceData{
                        .ent = hit_ent,
                        .timeline = IdLocal.init("despawn"),
                    };
                    system.event_mgr.triggerEvent(config.events.onAddTimelineInstance_id, &tli_despawn);

                    removed_entities.append(hit_ent) catch unreachable;
                    body_interface.addImpulse(
                        hit_body,
                        .{ 0, 100, 0 },
                    );
                }
                // std.debug.print("lol2 {any}\n", .{hit_ent.id});
            }
            //     AK.SoundEngine.setSwitchID(AK_ID.SWITCHES.HITMATERIAL.GROUP, AK_ID.SWITCHES.HITMATERIAL.SWITCH.CREATURE, oid) catch unreachable;
        }
        // _ = AK.SoundEngine.postEventID(AK_ID.EVENTS.PROJECTILEHIT, oid, .{}) catch unreachable;
    }
}
