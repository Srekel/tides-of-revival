const std = @import("std");
const args = @import("args");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const zmesh = @import("zmesh");
const zphy = @import("zphysics");
const zglfw = @import("zglfw");
const graphics = @import("zforge").graphics;
const zstbi = @import("zstbi");
const ztracy = @import("ztracy");
// const AK = @import("wwise-zig");
// const AK_ID = @import("wwise-ids");
const audio_manager = @import("audio/audio_manager_mock.zig");
const zm = @import("zmath");

const AssetManager = @import("core/asset_manager.zig").AssetManager;
const config = @import("config/config.zig");
const EventManager = @import("core/event_manager.zig").EventManager;
const fd = @import("config/flecs_data.zig");
const fr = @import("config/flecs_relation.zig");
const fsm = @import("fsm/fsm.zig");
const IdLocal = @import("core/core.zig").IdLocal;
const input = @import("input.zig");
const prefab_manager = @import("prefab_manager.zig");
const physics_manager = @import("managers/physics_manager.zig");

const renderer = @import("renderer/renderer.zig");
const util = @import("util.zig");
const Variant = @import("core/core.zig").Variant;
const window = @import("renderer/window.zig");

const patch_types = @import("worldpatch/patch_types.zig");
const world_patch_manager = @import("worldpatch/world_patch_manager.zig");
// const quality = @import("data/quality.zig");

pub fn run() void {
    zstbi.init(std.heap.page_allocator);
    defer zstbi.deinit();

    // Audio
    var audio_mgr = audio_manager.AudioManager.create(std.heap.page_allocator) catch unreachable;
    defer audio_mgr.destroy() catch unreachable;

    // AK.SoundEngine.registerGameObjWithName(std.heap.page_allocator, config.audio_player_oid, "Player") catch unreachable;
    // defer AK.SoundEngine.unregisterGameObj(config.audio_player_oid) catch {};
    // AK.SoundEngine.setDefaultListeners(&.{config.audio_player_oid}) catch unreachable;

    // const bank_id = AK.SoundEngine.loadBankString(std.heap.page_allocator, "Player_SoundBank", .{}) catch unreachable;
    // defer AK.SoundEngine.unloadBankID(bank_id, null, .{}) catch {};

    // Flecs
    // ecs.zflecs_init();
    // defer ecs.zflecs_fini();
    var ecsu_world = ecsu.World.init();
    defer ecsu_world.deinit();
    ecsu_world.progress(0);
    // _ = ecs.log_set_level(0);
    fd.registerComponents(ecsu_world);
    fr.registerRelations(ecsu_world);

    // Frame Stats
    var stats = renderer.FrameStats.init();

    // Window
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    main_window.window.setInputMode(.cursor, .disabled);

    // Initialize Renderer
    var renderer_ctx = renderer.Renderer{};
    renderer_ctx.init(main_window, std.heap.page_allocator) catch unreachable;
    defer renderer_ctx.exit();
    const reload_desc = renderer.ReloadDesc{ .mType = .{ .SHADER = true, .RESIZE = true, .RENDERTARGET = true } };
    renderer_ctx.onLoad(reload_desc) catch unreachable;
    defer renderer_ctx.onUnload(reload_desc);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    zmesh.init(arena);
    defer zmesh.deinit();

    // Misc
    var prefab_mgr = prefab_manager.PrefabManager.init(&renderer_ctx, ecsu_world, std.heap.page_allocator);
    defer prefab_mgr.deinit();
    config.prefab.initPrefabs(&prefab_mgr, ecsu_world);

    var event_mgr = EventManager.create(std.heap.page_allocator);
    defer event_mgr.destroy();

    // Watermark Logo
    {
        const logo_texture = renderer_ctx.loadTexture("textures/ui/tides_logo_ui.dds");
        const logo_size: f32 = 100;
        const top = 20.0;
        const bottom = 20.0 + logo_size;
        const left = @as(f32, @floatFromInt(main_window.frame_buffer_size[0])) - 20.0 - logo_size;
        const right = @as(f32, @floatFromInt(main_window.frame_buffer_size[0])) - 20.0;

        var logo_ent = ecsu_world.newEntity();
        logo_ent.set(fd.UIImage{ .rect = [4]f32{ top, bottom, left, right }, .material = .{
            .color = [4]f32{ 1, 1, 1, 1 },
            .texture = logo_texture,
        } });
    }

    // Input
    // Run it once to make sure we don't get huge diff values for cursor etc. the first frame.
    const input_target_defaults = config.input.createDefaultTargetDefaults(std.heap.page_allocator);
    const input_keymap = config.input.createKeyMap(std.heap.page_allocator);
    var input_frame_data = input.FrameData.create(std.heap.page_allocator, input_keymap, input_target_defaults, main_window.window);
    input.doTheThing(std.heap.page_allocator, &input_frame_data);

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

    const GameloopContext = struct {
        arena_system_lifetime: std.mem.Allocator,
        arena_system_update: std.mem.Allocator,
        arena_frame: std.mem.Allocator,
        heap_allocator: std.mem.Allocator,
        asset_mgr: *AssetManager,
        audio_mgr: *audio_manager.AudioManager,
        ecsu_world: ecsu.World,
        event_mgr: *EventManager,
        input_frame_data: *input.FrameData,
        main_window: *window.Window,
        physics_world: *zphy.PhysicsSystem,
        prefab_mgr: *prefab_manager.PrefabManager,
        renderer: *renderer.Renderer,
        stats: *renderer.FrameStats,
        world_patch_mgr: *world_patch_manager.WorldPatchManager,
    };

    var root_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var arena_system_lifetime = std.heap.ArenaAllocator.init(root_allocator.allocator());
    var arena_system_update = std.heap.ArenaAllocator.init(root_allocator.allocator());
    var arena_frame = std.heap.ArenaAllocator.init(root_allocator.allocator());
    defer {
        const check = root_allocator.deinit();
        std.debug.assert(check == .ok);
    }
    defer arena_system_lifetime.deinit();
    defer arena_system_update.deinit();
    defer arena_frame.deinit();

    var physics_mgr = physics_manager.create(arena_system_lifetime.allocator(), root_allocator.allocator());
    defer physics_manager.destroy(&physics_mgr);

    var gameloop_context: GameloopContext = .{
        .arena_system_lifetime = arena_system_lifetime.allocator(),
        .arena_system_update = arena_system_update.allocator(),
        .arena_frame = arena_frame.allocator(),
        .heap_allocator = root_allocator.allocator(),
        .asset_mgr = &asset_mgr,
        .audio_mgr = &audio_mgr,
        .ecsu_world = ecsu_world,
        .event_mgr = &event_mgr,
        .input_frame_data = &input_frame_data,
        .main_window = main_window,
        .physics_world = physics_mgr.physics_world,
        .prefab_mgr = &prefab_mgr,
        .renderer = &renderer_ctx,
        .stats = &stats,
        .world_patch_mgr = world_patch_mgr,
    };

    config.system.createSystems(&gameloop_context);

    ecsu_world.setSingleton(fd.EnvironmentInfo{
        .paused = false,
        .time_of_day_percent = 0,
        .sun_height = 0,
        .world_time = 0,
        .active_camera = null,
        .sun = null,
        .sky_light = null,
        .player = null,
    });

    // ███████╗███╗   ██╗████████╗██╗████████╗██╗███████╗███████╗
    // ██╔════╝████╗  ██║╚══██╔══╝██║╚══██╔══╝██║██╔════╝██╔════╝
    // █████╗  ██╔██╗ ██║   ██║   ██║   ██║   ██║█████╗  ███████╗
    // ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║   ██║██╔══╝  ╚════██║
    // ███████╗██║ ╚████║   ██║   ██║   ██║   ██║███████╗███████║
    // ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   ╚═╝   ╚═╝╚══════╝╚══════╝

    const player_spawn = null;
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

    const player_pos = if (player_spawn) |ps| ps.pos else fd.Position.init(100, 100, 100);
    config.entity.init(player_pos, &prefab_mgr, ecsu_world, &renderer_ctx);

    const matball_prefab = prefab_mgr.getPrefab(config.prefab.matball_id).?;
    const matball_position = fd.Position.init(player_pos.x, player_pos.y + 100.0, player_pos.z);
    var matball_ent = prefab_mgr.instantiatePrefab(ecsu_world, matball_prefab);
    matball_ent.set(matball_position);
    matball_ent.set(fd.Rotation{});
    matball_ent.set(fd.Scale.createScalar(1.0));
    matball_ent.set(fd.Transform.initFromPosition(matball_position));

    // ████████╗██╗███╗   ███╗███████╗██╗     ██╗███╗   ██╗███████╗███████╗
    // ╚══██╔══╝██║████╗ ████║██╔════╝██║     ██║████╗  ██║██╔════╝██╔════╝
    //    ██║   ██║██╔████╔██║█████╗  ██║     ██║██╔██╗ ██║█████╗  ███████╗
    //    ██║   ██║██║╚██╔╝██║██╔══╝  ██║     ██║██║╚██╗██║██╔══╝  ╚════██║
    //    ██║   ██║██║ ╚═╝ ██║███████╗███████╗██║██║ ╚████║███████╗███████║
    //    ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝

    var tl_giant_ant_spawn_ctx: ?config.timeline.WaveSpawnContext = null;

    if (player_spawn != null) {
        tl_giant_ant_spawn_ctx = config.timeline.WaveSpawnContext{
            .ecsu_world = ecsu_world,
            .physics_world = gameloop_context.physics_world,
            .prefab_mgr = &prefab_mgr,
            .event_mgr = &event_mgr,
            .timeline_system = config.system.timeline_sys,
            .root_ent = player_spawn.?.city_ent,
        };

        config.timeline.initTimelines(&tl_giant_ant_spawn_ctx.?);
    }

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
    _ = ecs.import_c(ecsu_world.world, ecs.FlecsStatsImport, "FlecsStats");
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
        const done = update_full(gameloop_context);

        ztracy.FrameMark();

        if (done) {
            // Clear out systems. Needed to clear up memory.
            // NOTE: I'm not sure why this need to be done explicitly, I think
            //       systems should get destroyed when world is deleted.
            const query_systems = ecs.query_init(ecsu_world.world, &.{
                .terms = [_]ecs.term_t{
                    .{ .id = ecs.System },
                } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 1),
            }) catch unreachable;

            var system_ents = std.ArrayList(ecs.entity_t).initCapacity(arena_system_lifetime.allocator(), 100) catch unreachable;
            var query_systems_iter = ecs.query_iter(ecsu_world.world, query_systems);
            while (ecs.query_next(&query_systems_iter)) {
                system_ents.appendSliceAssumeCapacity(query_systems_iter.entities());
            }

            for (system_ents.items) |ent| {
                ecsu_world.delete(ent);
            }

            break;
        }
    }
}

var once_per_duration_test: f64 = 0;

fn update_full(gameloop_context: anytype) bool {
    var input_frame_data = gameloop_context.input_frame_data;
    const ecsu_world = gameloop_context.ecsu_world;
    var world_patch_mgr = gameloop_context.world_patch_mgr;
    const main_window = gameloop_context.main_window;
    const renderer_ctx = gameloop_context.renderer;
    var stats = gameloop_context.stats;

    const trazy_zone = ztracy.ZoneNC(@src(), "Game Loop Update", 0x00_00_00_ff);
    defer trazy_zone.End();

    const window_status = window.update() catch unreachable;
    if (window_status == .no_windows) {
        return true;
    }
    if (input_frame_data.just_pressed(config.input.exit)) {
        return true;
    }

    if (input_frame_data.just_pressed(config.input.reload_shaders)) {
        renderer_ctx.reloadShaders();
    }

    if (input_frame_data.just_pressed(config.input.toggle_vsync)) {
        renderer_ctx.toggleVSync();
    }

    if (main_window.frame_buffer_size[0] != renderer_ctx.window_width or main_window.frame_buffer_size[1] != renderer_ctx.window_height) {
        renderer_ctx.window_width = main_window.frame_buffer_size[0];
        renderer_ctx.window_height = main_window.frame_buffer_size[1];

        const reload_desc = graphics.ReloadDesc{
            .mType = .{ .RESIZE = true },
        };
        renderer_ctx.requestReload(reload_desc);
    }

    // TODO(gmodarelli): Add these view modes to tides_renderer
    // // TODO: Move to The Debuginator
    // if (input_frame_data.just_pressed(config.input.view_mode_lit)) {
    //     gfx_state.setViewMode(.lit);
    // }

    // if (input_frame_data.just_pressed(config.input.view_mode_albedo)) {
    //     gfx_state.setViewMode(.albedo);
    // }

    // if (input_frame_data.just_pressed(config.input.view_mode_world_normal)) {
    //     gfx_state.setViewMode(.world_normal);
    // }

    // if (input_frame_data.just_pressed(config.input.view_mode_metallic)) {
    //     gfx_state.setViewMode(.metallic);
    // }

    // if (input_frame_data.just_pressed(config.input.view_mode_roughness)) {
    //     gfx_state.setViewMode(.roughness);
    // }

    // if (input_frame_data.just_pressed(config.input.view_mode_ao)) {
    //     gfx_state.setViewMode(.ao);
    // }

    // if (input_frame_data.just_pressed(config.input.view_mode_depth)) {
    //     gfx_state.setViewMode(.depth);
    // }

    // TODO: Move this to system
    for (0..100) |_| {
        world_patch_mgr.tickOne();
    }
    update(ecsu_world, stats.delta_time);

    stats.update();

    return false;
}

fn update(ecsu_world: ecsu.World, dt: f32) void {
    const environment_info = ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const dt_game = dt * environment_info.time_multiplier;
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

    once_per_duration_test += dt_game;
    if (once_per_duration_test > 1) {
        // PUT YOUR ONCE-PER-SECOND-ISH STUFF HERE!
        once_per_duration_test = 0;
        // _ = AK.SoundEngine.postEventID(AK_ID.EVENTS.FOOTSTEP, DemoGameObjectID, .{}) catch unreachable;
    }

    // AK.SoundEngine.renderAudio(false) catch unreachable;
    ecsu_world.progress(@floatCast(dt_game));
}
