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

const DEBUG_CAMERA_ACTIVE = false;

pub fn init(player_pos: fd.Position, prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World, rctx: *renderer.Renderer) void {
    // ██╗     ██╗ ██████╗ ██╗  ██╗████████╗██╗███╗   ██╗ ██████╗
    // ██║     ██║██╔════╝ ██║  ██║╚══██╔══╝██║████╗  ██║██╔════╝
    // ██║     ██║██║  ███╗███████║   ██║   ██║██╔██╗ ██║██║  ███╗
    // ██║     ██║██║   ██║██╔══██║   ██║   ██║██║╚██╗██║██║   ██║
    // ███████╗██║╚██████╔╝██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝
    // ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

    const sun_ent = ecsu_world.newEntity();
    sun_ent.set(fd.Rotation.initFromEulerDegrees(50.0, 30.0, 0.0));
    sun_ent.set(fd.DirectionalLight{
        .color = .{ .r = 1.0, .g = 1.0, .b = 1.0 },
        .intensity = 10.0,
        .shadow_range = 100.0,
    });

    const sky_light_ent = ecsu_world.newEntity();
    {
        var sky_light_component = fd.SkyLight{
            .hdri = renderer.TextureHandle.nil,
            .intensity = 0.3,
        };

        var desc = std.mem.zeroes(graphics.TextureDesc);
        desc.bBindless = false;
        sky_light_component.hdri = rctx.loadTextureWithDesc(desc, "textures/env/kloofendal_43d_clear_puresky_2k_cube_radiance.dds");

        sky_light_ent.set(sky_light_component);
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

    const debug_camera_ent = ecsu_world.newEntity();
    debug_camera_ent.set(fd.Position{ .x = player_pos.x, .y = player_pos.y, .z = player_pos.z });
    // debug_camera_ent.setPair(fd.Position, fd.LocalSpace, .{ .x = player_pos.x + 100, .y = player_pos.y + 100, .z = player_pos.z + 100 });
    debug_camera_ent.set(fd.Rotation{});
    debug_camera_ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
    debug_camera_ent.set(fd.Rotation{});
    debug_camera_ent.set(fd.Scale{});
    debug_camera_ent.set(fd.Transform{});
    debug_camera_ent.set(fd.Dynamic{});
    debug_camera_ent.set(fd.Camera.create(0.1, 25000, 0.25 * std.math.pi, DEBUG_CAMERA_ACTIVE, 0));
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
    player_camera_ent.set(fd.Scale.createScalar(1));
    player_camera_ent.set(fd.Transform{});
    player_camera_ent.set(fd.Dynamic{});
    player_camera_ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
    player_camera_ent.addPair(fd.FSM_CAM, fd.FSM_CAM_Fps);
    player_camera_ent.set(fd.Camera.create(0.1, 25000, 0.25 * std.math.pi, !DEBUG_CAMERA_ACTIVE, 1));
    player_camera_ent.set(fd.Input{ .active = false, .index = 0 });
    player_camera_ent.set(fd.PointLight{
        .color = .{ .r = 1, .g = 0.95, .b = 0.75 },
        .range = 5.0,
        .intensity = 1.0,
    });
    bow_ent.childOf(player_camera_ent);

    //  ██████╗  ██████╗███████╗ █████╗ ███╗   ██╗
    // ██╔═══██╗██╔════╝██╔════╝██╔══██╗████╗  ██║
    // ██║   ██║██║     █████╗  ███████║██╔██╗ ██║
    // ██║   ██║██║     ██╔══╝  ██╔══██║██║╚██╗██║
    // ╚██████╔╝╚██████╗███████╗██║  ██║██║ ╚████║
    //  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝
    //

    {
        const plane_prefab = prefab_mgr.getPrefab(config.prefab.plane_id).?;
        const lod_group = plane_prefab.get(fd.LodGroup);
        const mesh_handle = lod_group.?.lods[0].mesh_handle;
        const ocean_plane_scale: f32 = @floatFromInt(config.km_size);
        const ocean_tiles_x = config.world_size_x / config.km_size;
        const ocean_tiles_z = config.world_size_z / config.km_size;

        for (0..ocean_tiles_z) |z| {
            for (0..ocean_tiles_x) |x| {
                const ocean_plane_position = fd.Position.init(
                    @as(f32, @floatFromInt(x)) * ocean_plane_scale + ocean_plane_scale * 0.5,
                    config.sea_level,
                    @as(f32, @floatFromInt(z)) * ocean_plane_scale + ocean_plane_scale * 0.5,
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
                ocean_plane_ent.set(fd.Water{ .mesh_handle = mesh_handle });
            }
        }
    }

    // ██╗     ███████╗██╗   ██╗███████╗██╗         ██████╗  █████╗ ██╗     ███████╗████████╗████████╗███████╗
    // ██║     ██╔════╝██║   ██║██╔════╝██║         ██╔══██╗██╔══██╗██║     ██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝
    // ██║     █████╗  ██║   ██║█████╗  ██║         ██████╔╝███████║██║     █████╗     ██║      ██║   █████╗
    // ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║         ██╔═══╝ ██╔══██║██║     ██╔══╝     ██║      ██║   ██╔══╝
    // ███████╗███████╗ ╚████╔╝ ███████╗███████╗    ██║     ██║  ██║███████╗███████╗   ██║      ██║   ███████╗
    // ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝    ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝

    {
        const plane_prefab = prefab_mgr.getPrefab(config.prefab.plane_id).?;
        const position = fd.Position.init(50.0, 10.0, -50.0);
        var ent = prefab_mgr.instantiatePrefab(ecsu_world, plane_prefab);
        ent.set(position);
        ent.set(fd.Rotation{});
        ent.set(fd.Scale.createScalar(100.0));
        ent.set(fd.Transform.initWithScale(position.x, position.y, position.z, 100.0));
    }

    var position_x: f32 = 10.0;
    for (prefab.prefabs) |prefab_id| {
        const prefab_ent = prefab_mgr.getPrefab(prefab_id).?;
        const lod_group = prefab_ent.get(fd.LodGroup);
        const mesh_handle = lod_group.?.lods[0].mesh_handle;
        const mesh = rctx.getMesh(mesh_handle);
        const aabbMin = mesh.geometry.*.mAabbMin;
        const aabbMax = mesh.geometry.*.mAabbMax;
        _ = aabbMax;
        const radius = mesh.geometry.*.mRadius;
        // const extent = (aabbMax[0] - aabbMin[0]);

        position_x += radius + 1.0;

        const position = fd.Position.init(position_x, 10.0 - aabbMin[1], -20.0);
        var ent = prefab_mgr.instantiatePrefab(ecsu_world, prefab_ent);
        ent.set(position);
        ent.set(fd.Rotation{});
        ent.set(fd.Scale.createScalar(1.0));
        ent.set(fd.Transform.initFromPosition(position));

        position_x += radius + 1.0;
    }

    var environment_info = ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    environment_info.active_camera = player_camera_ent;
    environment_info.sun = sun_ent;
    environment_info.sky_light = sky_light_ent;
    environment_info.player = player_ent;
}
