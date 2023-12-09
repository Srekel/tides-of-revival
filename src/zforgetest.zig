const std = @import("std");
const args = @import("args");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const zglfw = @import("zglfw");
const zmesh = @import("zmesh");
const zphy = @import("zphysics");
const zstbi = @import("zstbi");
const ztracy = @import("ztracy");
const AK = @import("wwise-zig");
const AK_ID = @import("wwise-ids");
const audio_manager = @import("audio/audio_manager.zig");
const zm = @import("zmath");

const AssetManager = @import("core/asset_manager.zig").AssetManager;
const config = @import("config/config.zig");
const fd = @import("config/flecs_data.zig");
const fr = @import("config/flecs_relation.zig");
const fsm = @import("fsm/fsm.zig");
const renderer = @import("renderer/tides_renderer.zig");
const IdLocal = @import("core/core.zig").IdLocal;
const input = @import("input.zig");
const prefab_manager = @import("prefab_manager.zig");
const util = @import("util.zig");
const Variant = @import("core/core.zig").Variant;
const window = @import("renderer/window.zig");
const EventManager = @import("core/event_manager.zig").EventManager;

const patch_types = @import("worldpatch/patch_types.zig");
const world_patch_manager = @import("worldpatch/world_patch_manager.zig");

const SystemState = struct {
    allocator: std.mem.Allocator,
    main_window: *window.Window,
    app_settings: renderer.AppSettings,
    input_frame_data: input.FrameData,
};

pub fn run() void {
    const tracy_zone = ztracy.ZoneNC(@src(), "Game Run", 0x00_ff_00_00);
    defer tracy_zone.End();

    zstbi.init(std.heap.page_allocator);
    defer zstbi.deinit();

    // Audio
    var audio_mgr = audio_manager.AudioManager.create(std.heap.page_allocator) catch unreachable;
    defer audio_mgr.destroy() catch unreachable;

    AK.SoundEngine.registerGameObjWithName(std.heap.page_allocator, config.audio_player_oid, "Player") catch unreachable;
    defer AK.SoundEngine.unregisterGameObj(config.audio_player_oid) catch {};
    AK.SoundEngine.setDefaultListeners(&.{config.audio_player_oid}) catch unreachable;

    const bank_id = AK.SoundEngine.loadBankString(std.heap.page_allocator, "Player_SoundBank", .{}) catch unreachable;
    defer AK.SoundEngine.unloadBankID(bank_id, null, .{}) catch {};

    // Flecs
    var ecsu_world = ecsu.World.init();
    defer ecsu_world.deinit();
    ecsu_world.progress(0);
    fd.registerComponents(ecsu_world);
    fr.registerRelations(ecsu_world);

    var system_state: SystemState = undefined;
    system_state.allocator = std.heap.page_allocator;

    // GFX
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    system_state.main_window = window.createWindow("Tides of Revival: Z-Forge Wasn't Built In A Day") catch unreachable;
    system_state.main_window.window.setInputMode(.cursor, .disabled);

    // Initialize Tides Renderer
    const nativeWindowHandle = zglfw.native.getWin32Window(system_state.main_window.window) catch unreachable;
    system_state.app_settings = renderer.AppSettings{
        .width = 1920,
        .height = 1080,
        .window_native_handle = @as(*anyopaque, @constCast(nativeWindowHandle)),
        .v_sync_enabled = true,
    };
    var success = renderer.initRenderer(&system_state.app_settings);
    if (success != 0) {
        std.log.err("Failed to initialize Tides Renderer", .{});
        return;
    }
    var reload_desc = renderer.ReloadDesc{
        .reload_type = renderer.ReloadType.ALL,
    };
    defer renderer.exitRenderer();

    if (!renderer.onLoad(&reload_desc)) {
        unreachable;
    }
    defer renderer.onUnload(&reload_desc);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    zmesh.init(arena);
    defer zmesh.deinit();

    // Misc
    // TODO(gmodarelli): Replace dependency on gfx_state for prefab_manager
    // TODO(gmodarelli): Update the prefab manager to use The-Forge resource manager
    // var prefab_mgr = prefab_manager.PrefabManager.init(ecsu_world, std.heap.page_allocator);
    // defer prefab_mgr.deinit();
    // config.prefab.initPrefabs(&prefab_mgr, ecsu_world, std.heap.page_allocator, gfx_state);

    var event_mgr = EventManager.create(std.heap.page_allocator);
    defer event_mgr.destroy();

    // Input
    // Run it once to make sure we don't get huge diff values for cursor etc. the first frame.
    const input_target_defaults = config.input.createDefaultTargetDefaults(std.heap.page_allocator);
    const input_keymap = config.input.createKeyMap(std.heap.page_allocator);
    var input_frame_data = input.FrameData.create(std.heap.page_allocator, input_keymap, input_target_defaults, system_state.main_window.window);
    system_state.input_frame_data = input_frame_data;
    input.doTheThing(system_state.allocator, &system_state.input_frame_data);

    var asset_mgr = AssetManager.create(std.heap.page_allocator);
    defer asset_mgr.destroy();

    var world_patch_mgr = world_patch_manager.WorldPatchManager.create(std.heap.page_allocator, &asset_mgr);
    world_patch_mgr.debug_server.run();
    defer world_patch_mgr.destroy();
    patch_types.registerPatchTypes(world_patch_mgr);

    // ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗███████╗
    // ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║██╔════╝
    // ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║███████╗
    // ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
    // ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║███████║
    // ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

    // TODO: Remove system_context
    var system_context = util.Context.init(std.heap.page_allocator);
    system_context.putConst(config.allocator, &std.heap.page_allocator);
    system_context.put(config.ecsu_world, &ecsu_world);
    system_context.put(config.event_mgr, &event_mgr);
    system_context.put(config.world_patch_mgr, world_patch_mgr);
    // system_context.put(config.prefab_mgr, &prefab_mgr);

    var physics_world: *zphy.PhysicsSystem = undefined;

    var gameloop_context = .{
        .allocator = std.heap.page_allocator,
        .audio_mgr = &audio_mgr,
        .ecsu_world = ecsu_world,
        .event_mgr = &event_mgr,
        .input_frame_data = &input_frame_data,
        .physics_world = physics_world, // TODO: Optional
        // .prefab_mgr = &prefab_mgr,
        // .gfx = gfx_state,
        .world_patch_mgr = world_patch_mgr,
        // .gfx_state = gfx_state,
        .asset_mgr = &asset_mgr,
    };
    config.system.createSystems(&gameloop_context, &system_context);
    config.system.setupSystems();
    defer config.system.destroySystems();

    ecsu_world.setSingleton(fd.EnvironmentInfo{
        .paused = false,
        .time_of_day_percent = 0,
        .sun_height = 0,
        .world_time = 0,
        .active_camera = null,
    });

    // ███████╗███╗   ██╗████████╗██╗████████╗██╗███████╗███████╗
    // ██╔════╝████╗  ██║╚══██╔══╝██║╚══██╔══╝██║██╔════╝██╔════╝
    // █████╗  ██╔██╗ ██║   ██║   ██║   ██║   ██║█████╗  ███████╗
    // ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║   ██║██╔══╝  ╚════██║
    // ███████╗██║ ╚████║   ██║   ██║   ██║   ██║███████╗███████║
    // ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   ╚═╝   ╚═╝╚══════╝╚══════╝

    // TODO(gmodarelli): Enable when the city system has been updated
    // const player_spawn = blk: {
    //     var builder = ecsu.QueryBuilder.init(ecsu_world);
    //     _ = builder
    //         .with(fd.SpawnPoint)
    //         .with(fd.Position);

    //     var filter = builder.buildFilter();
    //     defer filter.deinit();

    //     var entity_iter = filter.iterator(struct { spawn_point: *fd.SpawnPoint, pos: *fd.Position });
    //     while (entity_iter.next()) |comps| {
    //         const city_ent = ecs.get_target(
    //             ecsu_world.world,
    //             entity_iter.entity(),
    //             fr.Hometown,
    //             0,
    //         );
    //         const spawnpoint_ent = entity_iter.entity();
    //         ecs.iter_fini(entity_iter.iter);
    //         break :blk .{
    //             .pos = comps.pos.*,
    //             .spawnpoint_ent = spawnpoint_ent,
    //             .city_ent = city_ent,
    //         };
    //     }
    //     break :blk null;
    // };

    // const player_pos = if (player_spawn) |ps| ps.pos else fd.Position.init(100, 100, 100);
    const player_pos = fd.Position.init(100, 100, 100);
    // config.entity.init(player_pos, &prefab_mgr, ecsu_world);
    config.entity.init(player_pos, ecsu_world);

    // // ███████╗██╗     ███████╗ ██████╗███████╗
    // // ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
    // // █████╗  ██║     █████╗  ██║     ███████╗
    // // ██╔══╝  ██║     ██╔══╝  ██║     ╚════██║
    // // ██║     ███████╗███████╗╚██████╗███████║
    // // ╚═╝     ╚══════╝╚══════╝ ╚═════╝╚══════╝

    // Flecs config
    // Delete children when parent is destroyed
    _ = ecsu_world.pair(ecs.OnDeleteTarget, ecs.OnDelete);

    // Enable web explorer
    _ = ecs.import_c(ecsu_world.world, ecs.FlecsMonitorImport, "FlecsMonitor");
    // _ = ecs.import_c(ecsu_world.world, ecs.FlecsUnitsImport, "FlecsUnits");
    const EcsRest = ecs.lookup_fullpath(ecsu_world.world, "flecs.rest.Rest");
    const EcsRestVal: ecs.EcsRest = .{};
    _ = ecs.set_id(ecsu_world.world, EcsRest, EcsRest, @sizeOf(ecs.EcsRest), &EcsRestVal);

    // ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
    // ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
    // ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
    // ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
    // ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
    //  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

    while (true) {
        // NOTE: There's no valuable distinction between update_full and update,
        // but probably not worth looking into deeper until we get a job system.
        const done = update_full(gameloop_context, &system_state);
        if (done) {
            break;
        }
    }

    // while (true) {
    //     const done = update(&system_state);
    //     if (done) {
    //         break;
    //     }
    // }
}

fn update_full(gameloop_context: anytype, state: *SystemState) bool {
    var input_frame_data = gameloop_context.input_frame_data;
    // var gfx_state = gameloop_context.gfx_state;
    var ecsu_world = gameloop_context.ecsu_world;
    var world_patch_mgr = gameloop_context.world_patch_mgr;

    const trazy_zone = ztracy.ZoneNC(@src(), "Game Loop Update", 0x00_00_00_ff);
    defer trazy_zone.End();

    const window_status = window.update() catch unreachable;
    if (window_status == .no_windows) {
        return true;
    }
    if (input_frame_data.just_pressed(config.input.exit)) {
        return true;
    }

    if (state.main_window.frame_buffer_size[0] != state.app_settings.width or state.main_window.frame_buffer_size[1] != state.app_settings.height) {
        state.app_settings.width = state.main_window.frame_buffer_size[0];
        state.app_settings.height = state.main_window.frame_buffer_size[1];

        var reload_desc = renderer.ReloadDesc{
            .reload_type = .{ .RESIZE = true },
        };
        renderer.onUnload(&reload_desc);
        if (!renderer.onLoad(&reload_desc)) {
            unreachable;
        }
    }

    world_patch_mgr.tickOne();
    update(ecsu_world);

    const camera_ent = util.getActiveCameraEnt(ecsu_world);
    const camera_component = camera_ent.get(fd.Camera).?;
    var z_view = zm.loadMat(camera_component.view[0..]);
    var camera: renderer.Camera = undefined;
    zm.storeMat(&camera.view_matrix, z_view);

    renderer.draw(camera);

    return false;
}

fn update(ecsu_world: ecsu.World) void {
    // const stats = gfx_state.stats;
    const environment_info = ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const dt_game = 1.0 / 144.0;
    environment_info.time_multiplier = 1;

    const flecs_stats = ecs.get_world_info(ecsu_world.world);
    {
        const time_multiplier = 24 * 4.0; // day takes quarter of an hour of realtime.. uuh this isn't a great method
        const world_time = flecs_stats.*.world_time_total;
        const time_of_day_percent = std.math.modf(time_multiplier * world_time / (60 * 60 * 24));
        environment_info.time_of_day_percent = time_of_day_percent.fpart;
        environment_info.sun_height = @sin(0.5 * environment_info.time_of_day_percent * std.math.pi);
        environment_info.world_time = world_time;
    }

    AK.SoundEngine.renderAudio(false) catch unreachable;
    ecsu_world.progress(dt_game);
}

// pub fn update(state: *SystemState) bool {
//     input.doTheThing(state.allocator, &state.input_frame_data);
//
//     const window_status = window.update() catch unreachable;
//     if (window_status == .no_windows) {
//         return true;
//     }
//
//     if (state.main_window.frame_buffer_size[0] != state.app_settings.width or state.main_window.frame_buffer_size[1] != state.app_settings.height) {
//         state.app_settings.width = state.main_window.frame_buffer_size[0];
//         state.app_settings.height = state.main_window.frame_buffer_size[1];
//
//         var reload_desc = renderer.ReloadDesc{
//             .reload_type = .{ .RESIZE = true },
//         };
//         renderer.onUnload(&reload_desc);
//         if (!renderer.onLoad(&reload_desc)) {
//             unreachable;
//         }
//     }
//
//     if (state.input_frame_data.just_pressed(config.input.exit)) {
//         return true;
//     }
//
//     const view_mat_z = zm.lookAtLh(.{ 0.0, 0.0, -1.0, 1.0 }, .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 });
//     var camera: renderer.Camera = undefined;
//     zm.storeMat(&camera.view_matrix, view_mat_z);
//
//     renderer.draw(camera);
//
//     return false;
// }
