const std = @import("std");
const prefab = @import("prefab.zig");
const prefab_manager = @import("../prefab_manager.zig");
const config = @import("config.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("flecs_data.zig");
const renderer = @import("../renderer/renderer.zig");
const ID = core.ID;
const IdLocal = core.IdLocal;
const zforge = @import("zforge");
const zm = @import("zmath");
const graphics = zforge.graphics;
const zphy = @import("zphysics");

const DEBUG_CAMERA_ACTIVE = false;

pub fn init(player_pos: fd.Position, prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World, ctx: anytype) void {
    // ██╗     ██╗ ██████╗ ██╗  ██╗████████╗██╗███╗   ██╗ ██████╗
    // ██║     ██║██╔════╝ ██║  ██║╚══██╔══╝██║████╗  ██║██╔════╝
    // ██║     ██║██║  ███╗███████║   ██║   ██║██╔██╗ ██║██║  ███╗
    // ██║     ██║██║   ██║██╔══██║   ██║   ██║██║╚██╗██║██║   ██║
    // ███████╗██║╚██████╔╝██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝
    // ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

    const sun_ent = ecsu_world.newEntity();
    sun_ent.set(fd.Rotation.initFromEulerDegrees(0.0, 0.0, 0.0));
    sun_ent.set(fd.DirectionalLight{
        .color = .{ .r = 1.0, .g = 1.0, .b = 1.0 },
        .intensity = 5.0,
        .shadow_intensity = 1.0,
        .cast_shadows = true,
    });

    const moon_ent = ecsu_world.newEntity();
    moon_ent.set(fd.Rotation.initFromEulerDegrees(45.0, 0.0, 45.0));
    moon_ent.set(fd.DirectionalLight{
        .color = .{ .r = 0.79, .g = 0.93, .b = 1.0 },
        .intensity = 1.0,
        .shadow_intensity = 0.0,
        .cast_shadows = false,
    });

    const height_fog_ent = ecsu_world.newEntity();
    {
        const height_fog_component = fd.HeightFog{
            .color = fd.ColorRGB.init(0.3, 0.35, 0.45),
            .density = 0.00005,
        };

        height_fog_ent.set(height_fog_component);
    }

    // ██████╗  ██████╗ ██╗    ██╗
    // ██╔══██╗██╔═══██╗██║    ██║
    // ██████╔╝██║   ██║██║ █╗ ██║
    // ██╔══██╗██║   ██║██║███╗██║
    // ██████╔╝╚██████╔╝╚███╔███╔╝
    // ╚═════╝  ╚═════╝  ╚══╝╚══╝

    const bow_ent = prefab_mgr.instantiatePrefab(ecsu_world, config.prefab.bow);
    bow_ent.set(fd.Position{ .x = 0.25, .y = 0, .z = 1 });
    bow_ent.set(fd.ProjectileWeapon{});

    var proj_ent = ecsu_world.newEntity();
    proj_ent.set(fd.Projectile{});

    // ██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗
    // ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗
    // ██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝
    // ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗
    // ██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║
    // ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

    const player_ent = prefab_mgr.instantiatePrefab(ecsu_world, config.prefab.player);
    player_ent.setName("main_player");
    player_ent.set(player_pos);
    player_ent.set(fd.Rotation.initFromEulerDegrees(0, 90, 0));
    player_ent.set(fd.Transform.initFromPosition(player_pos));
    player_ent.set(fd.Forward{});
    player_ent.set(fd.Velocity{});
    player_ent.set(fd.Dynamic{});
    player_ent.set(fd.WorldLoader{
        .range = 2,
        .physics = true,
        .navmesh = true,
        // .props = true,
    });
    player_ent.set(fd.Input{ .active = !DEBUG_CAMERA_ACTIVE, .index = 0 });
    player_ent.set(fd.Health{ .value = 100 });
    player_ent.addPair(fd.FSM_PC, fd.FSM_PC_Idle);
    // if (player_spawn) |ps| {
    //     player_ent.addPair(fr.Hometown, ps.city_ent);
    // }

    player_ent.set(fd.Interactor{ .active = true, .wielded_item_ent_id = bow_ent.id });
    player_ent.set(fd.Journey{});

    var player_comp = fd.Player{};
    player_comp.music = ctx.audio.createSoundFromFile("content/audio/music/the_first_forayst.mp3", .{ .flags = .{ .stream = true } }) catch unreachable;
    player_comp.music.?.setVolume(3);
    player_comp.vo_intro = ctx.audio.createSoundFromFile("content/audio/hill3/intro.wav", .{}) catch unreachable;
    player_comp.vo_intro.setVolume(4);
    player_comp.vo_exited_village = ctx.audio.createSoundFromFile("content/audio/hill3/exited_village.wav", .{}) catch unreachable;
    player_comp.vo_exited_village.setVolume(4);

    player_ent.set(player_comp);

    const debug_camera_ent = ecsu_world.newEntity();
    debug_camera_ent.set(fd.Position{ .x = player_pos.x, .y = player_pos.y, .z = player_pos.z });
    // debug_camera_ent.setPair(fd.Position, fd.LocalSpace, .{ .x = player_pos.x + 100, .y = player_pos.y + 100, .z = player_pos.z + 100 });
    debug_camera_ent.set(fd.Rotation{});
    debug_camera_ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
    debug_camera_ent.set(fd.Rotation{});
    debug_camera_ent.set(fd.Scale{});
    debug_camera_ent.set(fd.Transform{});
    debug_camera_ent.set(fd.Dynamic{});
    debug_camera_ent.set(fd.Camera.create(0.1, 25000, std.math.degreesToRadians(60), DEBUG_CAMERA_ACTIVE, 0));
    debug_camera_ent.set(fd.WorldLoader{
        .range = 2,
        .props = true,
    });
    debug_camera_ent.set(fd.Input{ .active = DEBUG_CAMERA_ACTIVE, .index = 1 });
    debug_camera_ent.addPair(fd.FSM_CAM, fd.FSM_CAM_Freefly);

    const sphere_prefab = prefab_mgr.getPrefab(config.prefab.sphere_id).?;
    const player_camera_ent = prefab_mgr.instantiatePrefab(ecsu_world, sphere_prefab);
    player_camera_ent.childOf(player_ent);
    player_camera_ent.setName("playercamera");
    player_camera_ent.set(fd.Position{ .x = 0, .y = 1.7, .z = 0 });
    player_camera_ent.set(fd.Rotation{});
    player_camera_ent.set(fd.Scale.createScalar(0.5));
    player_camera_ent.set(fd.Transform{});
    player_camera_ent.set(fd.Dynamic{});
    player_camera_ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
    player_camera_ent.addPair(fd.FSM_CAM, fd.FSM_CAM_Fps);
    player_camera_ent.set(fd.Camera.create(0.1, 25000, std.math.degreesToRadians(60), !DEBUG_CAMERA_ACTIVE, 1));
    player_camera_ent.set(fd.Input{ .active = false, .index = 0 });
    player_camera_ent.set(fd.PointLight{
        .color = .{ .r = 1, .g = 0.95, .b = 0.75 },
        .range = 10.0,
        .intensity = 10.0,
    });
    player_camera_ent.set(fd.Journey{});
    bow_ent.childOf(player_camera_ent);

    //  ██████╗  ██████╗███████╗ █████╗ ███╗   ██╗
    // ██╔═══██╗██╔════╝██╔════╝██╔══██╗████╗  ██║
    // ██║   ██║██║     █████╗  ███████║██╔██╗ ██║
    // ██║   ██║██║     ██╔══╝  ██╔══██║██║╚██╗██║
    // ╚██████╔╝╚██████╗███████╗██║  ██║██║ ╚████║
    //  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝

    {
        const ocean_plane_scale: f32 = @floatFromInt(config.km_size);
        const padding = 4;
        const ocean_tiles_x = 2 * padding + config.world_size_x / config.km_size;
        const ocean_tiles_z = 2 * padding + config.world_size_z / config.km_size;

        for (0..ocean_tiles_z) |z| {
            for (0..ocean_tiles_x) |x| {
                const ocean_plane_position = fd.Position.init(
                    (@as(f32, @floatFromInt(x)) - padding) * ocean_plane_scale + ocean_plane_scale * 0.5,
                    config.ocean_level,
                    (@as(f32, @floatFromInt(z)) - padding) * ocean_plane_scale + ocean_plane_scale * 0.5,
                );
                var ocean_plane_ent = ecsu_world.newEntity();
                ocean_plane_ent.set(ocean_plane_position);
                ocean_plane_ent.set(fd.Rotation{});
                ocean_plane_ent.set(fd.Scale.createScalar(ocean_plane_scale));
                ocean_plane_ent.set(fd.Transform.initWithScale(
                    ocean_plane_position.x,
                    ocean_plane_position.y,
                    ocean_plane_position.z,
                    ocean_plane_scale,
                ));
                ocean_plane_ent.set(fd.Water{});
            }
        }
    }

    // // ██╗     ███████╗██╗   ██╗███████╗██╗         ██████╗  █████╗ ██╗     ███████╗████████╗████████╗███████╗
    // // ██║     ██╔════╝██║   ██║██╔════╝██║         ██╔══██╗██╔══██╗██║     ██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝
    // // ██║     █████╗  ██║   ██║█████╗  ██║         ██████╔╝███████║██║     █████╗     ██║      ██║   █████╗
    // // ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║         ██╔═══╝ ██╔══██║██║     ██╔══╝     ██║      ██║   ██╔══╝
    // // ███████╗███████╗ ╚████╔╝ ███████╗███████╗    ██║     ██║  ██║███████╗███████╗   ██║      ██║   ███████╗
    // // ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝    ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝

    // {
    //     const plane_prefab = prefab_mgr.getPrefab(config.prefab.plane_id).?;
    //     const position = fd.Position.init(50.0, 10.0, -50.0);
    //     var ent = prefab_mgr.instantiatePrefab(ecsu_world, plane_prefab);
    //     ent.set(position);
    //     ent.set(fd.Rotation{});
    //     ent.set(fd.Scale.createScalar(100.0));
    //     ent.set(fd.Transform.initWithScale(position.x, position.y, position.z, 100.0));
    // }

    // var position_x: f32 = 10.0;
    // for (prefab.prefabs) |prefab_id| {
    //     const prefab_ent = prefab_mgr.getPrefab(prefab_id).?;
    //     const lod_group = prefab_ent.get(fd.LodGroup);
    //     const mesh_handle = lod_group.?.lods[0].mesh_handle;
    //     const mesh = rctx.getLegacyMesh(mesh_handle);
    //     const aabbMin = mesh.geometry.*.mAabbMin;
    //     const aabbMax = mesh.geometry.*.mAabbMax;
    //     _ = aabbMax;
    //     const radius = mesh.geometry.*.mRadius;
    //     // const extent = (aabbMax[0] - aabbMin[0]);

    //     position_x += radius + 1.0;

    //     const position = fd.Position.init(position_x, 10.0 - aabbMin[1], -20.0);
    //     var ent = prefab_mgr.instantiatePrefab(ecsu_world, prefab_ent);
    //     ent.set(position);
    //     ent.set(fd.Rotation{});
    //     ent.set(fd.Scale.createScalar(1.0));
    //     ent.set(fd.Transform.initFromPosition(position));

    //     position_x += radius + 1.0;
    // }

    var environment_info = ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    environment_info.active_camera = player_camera_ent;
    environment_info.player_camera = player_camera_ent;
    environment_info.sun = sun_ent;
    environment_info.moon = moon_ent;
    environment_info.height_fog = height_fog_ent;
    environment_info.player = player_ent;

    // ██╗      ██████╗ ██╗    ██╗    ██████╗ ██╗  ██╗██╗   ██╗███████╗██╗ ██████╗███████╗
    // ██║     ██╔═══██╗██║    ██║    ██╔══██╗██║  ██║╚██╗ ██╔╝██╔════╝██║██╔════╝██╔════╝
    // ██║     ██║   ██║██║ █╗ ██║    ██████╔╝███████║ ╚████╔╝ ███████╗██║██║     ███████╗
    // ██║     ██║   ██║██║███╗██║    ██╔═══╝ ██╔══██║  ╚██╔╝  ╚════██║██║██║     ╚════██║
    // ███████╗╚██████╔╝╚███╔███╔╝    ██║     ██║  ██║   ██║   ███████║██║╚██████╗███████║
    // ╚══════╝ ╚═════╝  ╚══╝╚══╝     ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝ ╚═════╝╚══════╝

    const loader_ent = ecsu_world.newEntityWithName("low_physics_loader");
    loader_ent.set(fd.Position{
        .x = config.world_size_x / 2,
        .y = 0,
        .z = config.world_size_z / 2,
    });
    loader_ent.set(fd.WorldLoader{
        .range = 2,
        .physics = true,
    });

    // ███████╗███╗   ██╗███████╗███╗   ███╗██╗   ██╗
    // ██╔════╝████╗  ██║██╔════╝████╗ ████║╚██╗ ██╔╝
    // █████╗  ██╔██╗ ██║█████╗  ██╔████╔██║ ╚████╔╝
    // ██╔══╝  ██║╚██╗██║██╔══╝  ██║╚██╔╝██║  ╚██╔╝
    // ███████╗██║ ╚████║███████╗██║ ╚═╝ ██║   ██║
    // ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝     ╚═╝   ╚═╝

    {
        var ent = prefab_mgr.instantiatePrefab(ecsu_world, config.prefab.slime);
        ent.setName("mama_slime");

        const spawn_pos = [3]f32{ 8000, 200, 8000 };
        ent.set(fd.Position{ .x = spawn_pos[0], .y = spawn_pos[1], .z = spawn_pos[2] });

        const scale: f32 = 1;
        ent.set(fd.Scale.createScalar(scale));
        ent.set(fd.Health{ .value = 100000 });
        ent.addPair(fd.FSM_ENEMY, fd.FSM_ENEMY_Slime);

        ent.set(fd.Enemy{ .base_scale = 10 });

        const body_interface = ctx.physics_world.getBodyInterfaceMut();

        const shape_settings = zphy.SphereShapeSettings.create(1.5 * scale) catch unreachable;
        defer shape_settings.release();

        var rot = [_]f32{ 1, 0, 0, 0 };
        const rot_z = zm.quatFromRollPitchYaw(std.math.pi / 2.0, 0, 0);
        zm.storeArr4(&rot, rot_z);
        const root_shape_settings = zphy.DecoratedShapeSettings.createRotatedTranslated(
            &shape_settings.asShapeSettings().*,
            rot,
            .{ 0, 0, 0 },
        ) catch unreachable;
        defer root_shape_settings.release();
        const root_shape = root_shape_settings.createShape() catch unreachable;

        const body_id = body_interface.createAndAddBody(.{
            .position = .{ spawn_pos[0], spawn_pos[1], spawn_pos[2], 0 },
            .rotation = .{ 0, 0, 0, 1 },
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

        ent.add(fd.SettlementEnemy);
        ent.set(fd.Locomotion{});
        ent.set(fd.Dynamic{});

        const light_ent = ecsu_world.newEntity();
        light_ent.childOf(ent);
        light_ent.set(fd.Position{ .x = 0, .y = 5, .z = 0 });
        light_ent.set(fd.Rotation{});
        light_ent.set(fd.Scale.createScalar(1));
        light_ent.set(fd.Transform{});
        light_ent.set(fd.Dynamic{});

        light_ent.set(fd.PointLight{
            .color = .{ .r = 0.2, .g = 1, .b = 0.3 },
            .range = 100,
            .intensity = 7,
        });
    }
}
