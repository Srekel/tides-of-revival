const std = @import("std");
const prefab_manager = @import("../prefab_manager.zig");
const config = @import("config.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("flecs_data.zig");
const gfx = @import("../renderer/gfx_d3d12.zig");
const ID = core.ID;
const IdLocal = core.IdLocal;

const DEBUG_CAMERA_ACTIVE = false;

pub fn init(player_pos: fd.Position, prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    const sun_light = ecsu_world.newEntity();
    sun_light.set(fd.Rotation.initFromEulerDegrees(50.0, -30.0, 0.0));
    sun_light.set(fd.DirectionalLight{
        .color = .{ .r = 0.5, .g = 0.5, .b = 0.8 },
        .intensity = 0.5,
    });

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
    player_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("player_controller") });
    player_ent.set(fd.WorldLoader{
        .range = 2,
        .physics = true,
    });
    player_ent.set(fd.Input{ .active = !DEBUG_CAMERA_ACTIVE, .index = 0 });
    player_ent.set(fd.Health{ .value = 100 });
    // if (player_spawn) |ps| {
    //     player_ent.addPair(fr.Hometown, ps.city_ent);
    // }

    player_ent.set(fd.Interactor{ .active = true, .wielded_item_ent_id = bow_ent.id });

    const debug_camera_ent = ecsu_world.newEntity();
    debug_camera_ent.set(fd.Position{ .x = player_pos.x + 100, .y = player_pos.y + 100, .z = player_pos.z + 100 });
    // debug_camera_ent.setPair(fd.Position, fd.LocalSpace, .{ .x = player_pos.x + 100, .y = player_pos.y + 100, .z = player_pos.z + 100 });
    debug_camera_ent.set(fd.Rotation{});
    debug_camera_ent.set(fd.Scale{});
    debug_camera_ent.set(fd.Transform{});
    debug_camera_ent.set(fd.Dynamic{});
    debug_camera_ent.set(fd.CICamera{
        .near = 0.1,
        .far = 10000,
        .active = DEBUG_CAMERA_ACTIVE,
        .class = 0,
    });
    debug_camera_ent.set(fd.WorldLoader{
        .range = 2,
        .props = true,
    });
    debug_camera_ent.set(fd.Input{ .active = DEBUG_CAMERA_ACTIVE, .index = 1 });
    debug_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("debug_camera") });

    const sphere_prefab = prefab_mgr.getPrefabByPath("content/prefabs/primitives/primitive_sphere.gltf").?;
    const player_camera_ent = prefab_mgr.instantiatePrefab(ecsu_world, sphere_prefab);
    player_camera_ent.childOf(player_ent);
    player_camera_ent.setName("playercamera");
    player_camera_ent.set(fd.Position{ .x = 0, .y = 1.7, .z = 0 });
    player_camera_ent.set(fd.Rotation{});
    player_camera_ent.set(fd.Scale.createScalar(1));
    player_camera_ent.set(fd.Transform{});
    player_camera_ent.set(fd.Dynamic{});
    player_camera_ent.set(fd.Forward{});
    player_camera_ent.set(fd.CICamera{
        .near = 0.1,
        .far = 10000,
        .active = !DEBUG_CAMERA_ACTIVE,
        .class = 1,
    });
    player_camera_ent.set(fd.Input{ .active = false, .index = 0 });
    player_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("fps_camera") });
    player_camera_ent.set(fd.PointLight{
        .color = .{ .r = 1, .g = 0.95, .b = 0.75 },
        .range = 5.0,
        .intensity = 1.0,
    });
    bow_ent.childOf(player_camera_ent);

    var environment_info = ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    environment_info.active_camera = player_camera_ent;
}