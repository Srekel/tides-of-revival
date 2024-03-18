const std = @import("std");
const args = @import("args");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const zmesh = @import("zmesh");
const zphy = @import("zphysics");
const zglfw = @import("zglfw");
const zstbi = @import("zstbi");
const ztracy = @import("ztracy");
const AK = @import("wwise-zig");
const AK_ID = @import("wwise-ids");
const audio_manager = @import("audio/audio_manager.zig");
const zm = @import("zmath");
const zignav = @import("zignav");

const AssetManager = @import("core/asset_manager.zig").AssetManager;
const config = @import("config/config.zig");
const fd = @import("config/flecs_data.zig");
const fr = @import("config/flecs_relation.zig");
const fsm = @import("fsm/fsm.zig");
const IdLocal = @import("core/core.zig").IdLocal;
const input = @import("input.zig");
const prefab_manager = @import("prefab_manager.zig");
const util = @import("util.zig");
const Variant = @import("core/core.zig").Variant;
const window = @import("renderer/window.zig");
const EventManager = @import("core/event_manager.zig").EventManager;
const renderer = @import("renderer/tides_renderer.zig");

const patch_types = @import("worldpatch/patch_types.zig");
const world_patch_manager = @import("worldpatch/world_patch_manager.zig");
// const quality = @import("data/quality.zig");

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

    // GFX
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    main_window.window.setInputMode(.cursor, .disabled);

    // Initialize Tides Renderer
    const nativeWindowHandle = zglfw.native.getWin32Window(main_window.window) catch unreachable;
    var app_settings = renderer.AppSettings{
        .width = 1920,
        .height = 1080,
        .window_native_handle = @as(*anyopaque, @constCast(nativeWindowHandle)),
        .v_sync_enabled = true,
        .output_mode = .SDR,
    };
    const success = renderer.initRenderer(&app_settings);
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
    var prefab_mgr = prefab_manager.PrefabManager.init(ecsu_world, std.heap.page_allocator);
    defer prefab_mgr.deinit();
    config.prefab.initPrefabs(&prefab_mgr, ecsu_world);

    var event_mgr = EventManager.create(std.heap.page_allocator);
    defer event_mgr.destroy();

    // Watermark Logo
    {
        const logo_texture = renderer.loadTexture("textures/ui/tides_logo_ui.dds");
        const logo_size: f32 = 100;
        const top = 20.0;
        const bottom = 20.0 + logo_size;
        const left = @as(f32, @floatFromInt(app_settings.width)) - 20.0 - logo_size;
        const right = @as(f32, @floatFromInt(app_settings.width)) - 20.0;

        var logo_ent = ecsu_world.newEntity();
        logo_ent.set(fd.UIImageComponent{ .rect = [4]f32{ top, bottom, left, right }, .material = .{
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

    // Recast
    var nav_ctx: zignav.Recast.rcContext = undefined;
    nav_ctx.init(false);
    defer nav_ctx.deinit();

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
    system_context.put(config.prefab_mgr, &prefab_mgr);
    //
    const GameloopContext = struct {
        allocator: std.mem.Allocator,
        asset_mgr: *AssetManager,
        audio_mgr: *audio_manager.AudioManager,
        ecsu_world: ecsu.World,
        event_mgr: *EventManager,
        input_frame_data: *input.FrameData,
        physics_world: *zphy.PhysicsSystem,
        prefab_mgr: *prefab_manager.PrefabManager,
        world_patch_mgr: *world_patch_manager.WorldPatchManager,
        stats: *renderer.FrameStats,
        app_settings: *renderer.AppSettings,
        main_window: *window.Window,
        lights_buffer_indices: *renderer.HackyLightBuffersIndices,
        ui_buffer_indices: *renderer.HackyUIBuffersIndices,
    };

    // HACK(gmodarelli): Passing the current frame buffer indices for lights
    var lights_buffer_indices = renderer.HackyLightBuffersIndices{
        .directional_lights_buffer_index = std.math.maxInt(u32),
        .point_lights_buffer_index = std.math.maxInt(u32),
        .directional_lights_count = 0,
        .point_lights_count = 0,
    };

    // HACK(gmodarelli): Passing the current frame UI buffer indices for UI Images
    var ui_buffer_indices = renderer.HackyUIBuffersIndices{
        .ui_instance_buffer_index = std.math.maxInt(u32),
        .ui_instance_count = 0,
    };

    var gameloop_context: GameloopContext = .{
        .allocator = std.heap.page_allocator,
        .audio_mgr = &audio_mgr,
        .ecsu_world = ecsu_world,
        .event_mgr = &event_mgr,
        .input_frame_data = &input_frame_data,
        .physics_world = undefined,
        .prefab_mgr = &prefab_mgr,
        .world_patch_mgr = world_patch_mgr,
        .asset_mgr = &asset_mgr,
        .stats = &stats,
        .app_settings = &app_settings,
        .main_window = main_window,
        .lights_buffer_indices = &lights_buffer_indices,
        .ui_buffer_indices = &ui_buffer_indices,
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

    const player_spawn = blk: {
        var builder = ecsu.QueryBuilder.init(ecsu_world);
        _ = builder
            .with(fd.SpawnPoint)
            .with(fd.Position);

        var filter = builder.buildFilter();
        defer filter.deinit();

        var entity_iter = filter.iterator(struct { spawn_point: *fd.SpawnPoint, pos: *fd.Position });
        while (entity_iter.next()) |comps| {
            const city_ent = ecs.get_target(
                ecsu_world.world,
                entity_iter.entity(),
                fr.Hometown,
                0,
            );
            const spawnpoint_ent = entity_iter.entity();
            ecs.iter_fini(entity_iter.iter);
            break :blk .{
                .pos = comps.pos.*,
                .spawnpoint_ent = spawnpoint_ent,
                .city_ent = city_ent,
            };
        }
        break :blk null;
    };

    const player_pos = if (player_spawn) |ps| ps.pos else fd.Position.init(100, 100, 100);
    config.entity.init(player_pos, &prefab_mgr, ecsu_world);

    const matball_prefab = prefab_mgr.getPrefab(config.prefab.matball_id).?;
    const matball_position = fd.Position.init(player_pos.x, player_pos.y + 100.0, player_pos.z);
    var matball_ent = prefab_mgr.instantiatePrefab(ecsu_world, matball_prefab);
    const static_mesh_component = matball_ent.getMut(fd.StaticMeshComponent);
    if (static_mesh_component) |static_mesh| {
        static_mesh.material_count = 1;
        static_mesh.materials[0] = fd.PBRMaterial.init();
        static_mesh.materials[0].albedo = renderer.loadTexture("textures/debug/round_aluminum_panel_albedo.dds");
        static_mesh.materials[0].arm = renderer.loadTexture("textures/debug/round_aluminum_panel_arm.dds");
        static_mesh.materials[0].normal = renderer.loadTexture("textures/debug/round_aluminum_panel_normal.dds");
    }
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
        const done = update_full(
            gameloop_context,
            &(tl_giant_ant_spawn_ctx.?),
        );
        if (done) {
            break;
        }
    }
}

var once_per_duration_test: f32 = 0;

fn update_full(gameloop_context: anytype, tl_giant_ant_spawn_ctx: ?*config.timeline.WaveSpawnContext) bool {
    var input_frame_data = gameloop_context.input_frame_data;
    const ecsu_world = gameloop_context.ecsu_world;
    var world_patch_mgr = gameloop_context.world_patch_mgr;
    var app_settings = gameloop_context.app_settings;
    const main_window = gameloop_context.main_window;
    var stats = gameloop_context.stats;
    const lights_buffer_indices = gameloop_context.lights_buffer_indices;
    const ui_buffer_indices = gameloop_context.ui_buffer_indices;

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
        var reload_desc = renderer.ReloadDesc{
            .reload_type = .{ .SHADER = true },
        };
        _ = renderer.requestReload(&reload_desc);
    }

    if (main_window.frame_buffer_size[0] != app_settings.width or main_window.frame_buffer_size[1] != app_settings.height) {
        app_settings.width = main_window.frame_buffer_size[0];
        app_settings.height = main_window.frame_buffer_size[1];

        var reload_desc = renderer.ReloadDesc{
            .reload_type = .{ .RESIZE = true },
        };
        renderer.onUnload(&reload_desc);
        if (!renderer.onLoad(&reload_desc)) {
            unreachable;
        }
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

    world_patch_mgr.tickOne();
    update(ecsu_world, stats.delta_time);

    if (tl_giant_ant_spawn_ctx) |ctx| {
        _ = ctx;
        // TODO(gmodarelli): Add UILabel to tides_renderer
        // var ui_label = gfx.UILabel{
        //     .label = undefined,
        //     .font_size = 24,
        //     .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
        //     .rect = .{ .left = 20, .top = 400, .bottom = 420, .right = 600 },
        // };

        // var buffer = [_]u8{0} ** 64;
        // ui_label.label = std.fmt.bufPrint(buffer[0..], "Stage: {d}", .{ctx.stage}) catch unreachable;
        // gfx_state.drawUILabel(ui_label) catch unreachable;
    }

    const camera_ent = util.getActiveCameraEnt(ecsu_world);
    const camera_component = camera_ent.get(fd.Camera).?;
    const camera_transform = camera_ent.get(fd.Transform).?;
    const z_view = zm.loadMat(camera_component.view[0..]);
    const z_proj = zm.loadMat(camera_component.projection[0..]);

    var frame_data: renderer.FrameData = undefined;
    frame_data.position = camera_transform.getPos00();
    frame_data.directional_lights_buffer_index = lights_buffer_indices.directional_lights_buffer_index;
    frame_data.point_lights_buffer_index = lights_buffer_indices.point_lights_buffer_index;
    frame_data.directional_lights_count = lights_buffer_indices.directional_lights_count;
    frame_data.point_lights_count = lights_buffer_indices.point_lights_count;
    frame_data.ui_instance_buffer_index = ui_buffer_indices.ui_instance_buffer_index;
    frame_data.ui_instance_count = ui_buffer_indices.ui_instance_count;

    const static_mesh_component = config.prefab.default_cube.getMut(fd.StaticMeshComponent).?;
    frame_data.skybox_mesh_handle = static_mesh_component.*.mesh_handle;
    zm.storeMat(&frame_data.view_matrix, z_view);
    zm.storeMat(&frame_data.proj_matrix, z_proj);

    stats.update();
    renderer.draw(frame_data);

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

    AK.SoundEngine.renderAudio(false) catch unreachable;
    ecsu_world.progress(dt_game);
}
