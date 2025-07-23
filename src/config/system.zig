const std = @import("std");
const config = @import("config.zig");
const input = @import("../input.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const ID = @import("../core/core.zig").ID;
const util = @import("../util.zig");

const camera_system = @import("../systems/camera_system.zig");
const city_system = @import("../systems/procgen/city_system.zig");
const input_system = @import("../systems/input_system.zig");
const interact_system = @import("../systems/interact_system.zig");
// const navmesh_system = @import("../systems/ai/navmesh_system.zig");
const patch_prop_system = @import("../systems/patch_prop_system.zig");
const physics_system = @import("../systems/physics_system.zig");
const renderer_system = @import("../systems/renderer_system.zig");
const timeline_system = @import("../systems/timeline_system.zig");
const worldsim_systems = @import("../systems/worldsim_systems.zig");

const fsm_pc_idle = @import("../fsm/player_controller/state_player_idle.zig");
const fsm_cam_fps = @import("../fsm/camera/state_camera_fps.zig");
const fsm_cam_freefly = @import("../fsm/camera/state_camera_freefly.zig");
const fsm_enemy_idle = @import("../fsm/creature/state_giant_ant.zig");

// pub var timeline_sys: *timeline_system.SystemState = undefined;
// var camera_sys: *camera_system.SystemState = undefined;
// var city_sys: *city_system.SystemState = undefined;
// var input_sys: *input_system.SystemState = undefined;
// var interact_sys: *interact_system.SystemState = undefined;
// var navmesh_sys: *navmesh_system.SystemState = undefined;
// var patch_prop_sys: *patch_prop_system.SystemState = undefined;
// var physics_sys: *physics_system.SystemState = undefined;
// var renderer_sys: *renderer_system.SystemState = undefined;

pub fn createSystems(gameloop_context: anytype) void {
    input_system.create(input_system.SystemCreateCtx.view(gameloop_context));

    physics_system.create(physics_system.SystemCreateCtx.view(gameloop_context));

    fsm_pc_idle.create(fsm_pc_idle.StateContext.view(gameloop_context));
    fsm_cam_fps.create(fsm_cam_fps.StateContext.view(gameloop_context));
    fsm_cam_freefly.create(fsm_cam_freefly.StateContext.view(gameloop_context));
    fsm_enemy_idle.create(fsm_enemy_idle.StateContext.view(gameloop_context));

    interact_system.create(interact_system.SystemCreateCtx.view(gameloop_context));

    timeline_system.create(timeline_system.SystemCreateCtx.view(gameloop_context));

    // city_system.create(city_system.SystemCreateCtx.view(gameloop_context));

    patch_prop_system.create(patch_prop_system.SystemCreateCtx.view(gameloop_context));
    worldsim_systems.create(worldsim_systems.SystemCreateCtx.view(gameloop_context));

    // navmesh_sys = try navmesh_system.create(
    //     ID("navmesh_system"),
    //     navmesh_system.SystemCtx.view(gameloop_context),
    // );

    camera_system.create(camera_system.SystemCreateCtx.view(gameloop_context));
    renderer_system.create(renderer_system.SystemCreateCtx.view(gameloop_context));
}

pub fn setupSystems(gameloop_context: anytype) void {
    city_system.createEntities(gameloop_context.heap_allocator, gameloop_context.ecsu_world, gameloop_context.asset_mgr, gameloop_context.prefab_mgr);
}
