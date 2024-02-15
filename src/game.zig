const std = @import("std");
const args = @import("args");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
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
const gfx = @import("renderer/gfx_d3d12.zig");
const IdLocal = @import("core/core.zig").IdLocal;
const input = @import("input.zig");
const prefab_manager = @import("prefab_manager.zig");
const util = @import("util.zig");
const Variant = @import("core/core.zig").Variant;
const window = @import("renderer/window.zig");
const EventManager = @import("core/event_manager.zig").EventManager;

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

    // GFX
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    main_window.setInputMode(.cursor, .disabled);

    const gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(gfx_state, std.heap.page_allocator);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    zmesh.init(arena);
    defer zmesh.deinit();

    // Misc
    var prefab_mgr = prefab_manager.PrefabManager.init(ecsu_world, std.heap.page_allocator);
    defer prefab_mgr.deinit();
    config.prefab.initPrefabs(&prefab_mgr, ecsu_world, std.heap.page_allocator, gfx_state);

    var event_mgr = EventManager.create(std.heap.page_allocator);
    defer event_mgr.destroy();

    // Input
    // Run it once to make sure we don't get huge diff values for cursor etc. the first frame.
    const input_target_defaults = config.input.createDefaultTargetDefaults(std.heap.page_allocator);
    const input_keymap = config.input.createKeyMap(std.heap.page_allocator);
    var input_frame_data = input.FrameData.create(std.heap.page_allocator, input_keymap, input_target_defaults, main_window);
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
        gfx: *gfx.D3D12State,
        gfx_state: *gfx.D3D12State,
        input_frame_data: *input.FrameData,
        physics_world: *zphy.PhysicsSystem,
        prefab_mgr: *prefab_manager.PrefabManager,
        world_patch_mgr: *world_patch_manager.WorldPatchManager,
    };

    var gameloop_context: GameloopContext = .{
        .allocator = std.heap.page_allocator,
        .audio_mgr = &audio_mgr,
        .ecsu_world = ecsu_world,
        .event_mgr = &event_mgr,
        .input_frame_data = &input_frame_data,
        .physics_world = undefined,
        .prefab_mgr = &prefab_mgr,
        .gfx = gfx_state,
        .world_patch_mgr = world_patch_mgr,
        .gfx_state = gfx_state,
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
            .gfx = gfx_state,
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
    var gfx_state = gameloop_context.gfx_state;
    const ecsu_world = gameloop_context.ecsu_world;
    var world_patch_mgr = gameloop_context.world_patch_mgr;

    const trazy_zone = ztracy.ZoneNC(@src(), "Game Loop Update", 0x00_00_00_ff);
    defer trazy_zone.End();

    gfx.beginFrame(gfx_state);

    const window_status = window.update(gfx_state) catch unreachable;
    if (window_status == .no_windows) {
        return true;
    }
    if (input_frame_data.just_pressed(config.input.exit)) {
        return true;
    }

    // TODO: Move to The Debuginator
    if (input_frame_data.just_pressed(config.input.view_mode_lit)) {
        gfx_state.setViewMode(.lit);
    }

    if (input_frame_data.just_pressed(config.input.view_mode_albedo)) {
        gfx_state.setViewMode(.albedo);
    }

    if (input_frame_data.just_pressed(config.input.view_mode_world_normal)) {
        gfx_state.setViewMode(.world_normal);
    }

    if (input_frame_data.just_pressed(config.input.view_mode_metallic)) {
        gfx_state.setViewMode(.metallic);
    }

    if (input_frame_data.just_pressed(config.input.view_mode_roughness)) {
        gfx_state.setViewMode(.roughness);
    }

    if (input_frame_data.just_pressed(config.input.view_mode_ao)) {
        gfx_state.setViewMode(.ao);
    }

    if (input_frame_data.just_pressed(config.input.view_mode_depth)) {
        gfx_state.setViewMode(.depth);
    }

    world_patch_mgr.tickOne();
    update(ecsu_world, gfx_state);

    if (tl_giant_ant_spawn_ctx) |ctx| {
        var ui_label = gfx.UILabel{
            .label = undefined,
            .font_size = 24,
            .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            .rect = .{ .left = 20, .top = 400, .bottom = 420, .right = 600 },
        };

        var buffer = [_]u8{0} ** 64;
        ui_label.label = std.fmt.bufPrint(buffer[0..], "Stage: {d}", .{ctx.stage}) catch unreachable;
        gfx_state.drawUILabel(ui_label) catch unreachable;
    }

    const camera_ent = util.getActiveCameraEnt(ecsu_world);
    gfx.endFrame(
        gfx_state,
        camera_ent.get(fd.Camera).?,
        camera_ent.get(fd.Transform).?.getPos00(),
    );

    return false;
}

fn update(ecsu_world: ecsu.World, gfx_state: *gfx.D3D12State) void {
    const stats = gfx_state.stats;
    const environment_info = ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const dt_actual: f32 = @floatCast(stats.delta_time);
    const dt_game = dt_actual * environment_info.time_multiplier;
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
