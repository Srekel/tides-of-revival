const std = @import("std");
const config = @import("config.zig");
const input = @import("../input.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const ID = @import("../core/core.zig").ID;
const util = @import("../util.zig");

const camera_system = @import("../systems/camera_system.zig");
// const city_system = @import("../systems/procgen/city_system.zig");
const input_system = @import("../systems/input_system.zig");
// const interact_system = @import("../systems/interact_system.zig");
// const navmesh_system = @import("../systems/ai/navmesh_system.zig");
const patch_prop_system = @import("../systems/patch_prop_system.zig");
const physics_system = @import("../systems/physics_system.zig");
const renderer_system = @import("../systems/renderer_system.zig");
const state_machine_system = @import("../systems/state_machine_system.zig");
// const timeline_system = @import("../systems/timeline_system.zig");

// pub var timeline_sys: *timeline_system.SystemState = undefined;
// var camera_sys: *camera_system.SystemState = undefined;
// var city_sys: *city_system.SystemState = undefined;
// var input_sys: *input_system.SystemState = undefined;
// var interact_sys: *interact_system.SystemState = undefined;
// var navmesh_sys: *navmesh_system.SystemState = undefined;
// var patch_prop_sys: *patch_prop_system.SystemState = undefined;
// var physics_sys: *physics_system.SystemState = undefined;
// var renderer_sys: *renderer_system.SystemState = undefined;
// var state_machine_sys: *state_machine_system.SystemState = undefined;

pub fn createSystems(gameloop_context: anytype) void {
    input_system.create(input_system.SystemCreateCtx.view(gameloop_context));

    physics_system.create(physics_system.SystemCreateCtx.view(gameloop_context));

    // gameloop_context.physics_world = physics_sys.physics_world;

    state_machine_system.create(state_machine_system.SystemCreateCtx.view(gameloop_context));

    // interact_sys = try interact_system.create(
    //     ID("interact_sys"),
    //     interact_system.SystemCtx.view(gameloop_context),
    // );

    // timeline_sys = try timeline_system.create(
    //     ID("timeline_sys"),
    // );

    // city_sys = try city_system.create(
    //     ID("city_system"),
    //     std.heap.page_allocator,
    //     gameloop_context.ecsu_world,
    //     physics_sys.physics_world,
    //     gameloop_context.asset_mgr,
    //     gameloop_context.prefab_mgr,
    // );

    patch_prop_system.create(patch_prop_system.SystemCreateCtx.view(gameloop_context));

    // navmesh_sys = try navmesh_system.create(
    //     ID("navmesh_system"),
    //     navmesh_system.SystemCtx.view(gameloop_context),
    // );

    camera_system.create(camera_system.SystemCreateCtx.view(gameloop_context));
    renderer_system.create(renderer_system.SystemCreateCtx.view(gameloop_context));
}

pub fn setupSystems() void {
    // city_system.createEntities(city_sys);
}

pub fn destroySystems() void {
    // defer camera_system.destroy(camera_sys);
    // defer city_system.destroy(city_sys);
    // defer input_system.destroy(input_sys);
    // defer interact_system.destroy(interact_sys);
    // defer navmesh_system.destroy(navmesh_sys);
    // defer patch_prop_system.destroy(patch_prop_sys);
    // defer physics_system.destroy(physics_sys);
    // defer renderer_system.destroy(renderer_sys);
    // defer state_machine_system.destroy(state_machine_sys);
    // defer timeline_system.destroy(timeline_sys);
}
