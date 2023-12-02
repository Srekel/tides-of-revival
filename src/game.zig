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
const audio = @import("audio/audio_manager.zig");
const zm = @import("zmath");

const AssetManager = @import("core/asset_manager.zig").AssetManager;
const Variant = @import("core/core.zig").Variant;
const IdLocal = @import("core/core.zig").IdLocal;
const config = @import("config/config.zig");
const util = @import("util.zig");
const fd = @import("config/flecs_data.zig");
const fr = @import("config/flecs_relation.zig");
const fsm = @import("fsm/fsm.zig");
const gfx = @import("renderer/gfx_d3d12.zig");
const pm = @import("prefab_manager.zig");
const window = @import("renderer/window.zig");
const EventManager = @import("core/event_manager.zig").EventManager;

const patch_types = @import("worldpatch/patch_types.zig");
const world_patch_manager = @import("worldpatch/world_patch_manager.zig");
// const quality = @import("data/quality.zig");

const light_system = @import("systems/light_system.zig");
const camera_system = @import("systems/camera_system.zig");
const city_system = @import("systems/procgen/city_system.zig");
const input_system = @import("systems/input_system.zig");
const input = @import("input.zig");
const interact_system = @import("systems/interact_system.zig");
const physics_system = @import("systems/physics_system.zig");
const terrain_quad_tree_system = @import("systems/terrain_quad_tree.zig");
const patch_prop_system = @import("systems/patch_prop_system.zig");
const static_mesh_renderer_system = @import("systems/static_mesh_renderer_system.zig");
const state_machine_system = @import("systems/state_machine_system.zig");
const timeline_system = @import("systems/timeline_system.zig");

pub fn run() void {
    const tracy_zone = ztracy.ZoneNC(@src(), "Game Run", 0x00_ff_00_00);
    defer tracy_zone.End();

    zstbi.init(std.heap.page_allocator);
    defer zstbi.deinit();

    var audio_mgr = audio.AudioManager.create(std.heap.page_allocator) catch unreachable;
    defer audio_mgr.destroy() catch unreachable;

    AK.SoundEngine.registerGameObjWithName(std.heap.page_allocator, config.audio_player_oid, "Player") catch unreachable;
    defer AK.SoundEngine.unregisterGameObj(config.audio_player_oid) catch {};
    AK.SoundEngine.setDefaultListeners(&.{config.audio_player_oid}) catch unreachable;

    const bank_id = AK.SoundEngine.loadBankString(std.heap.page_allocator, "Player_SoundBank", .{}) catch unreachable;
    defer AK.SoundEngine.unloadBankID(bank_id, null, .{}) catch {};

    // ecs.zflecs_init();
    // defer ecs.zflecs_fini();
    var ecsu_world = ecsu.World.init();
    defer ecsu_world.deinit();
    ecsu_world.progress(0);
    // _ = ecs.log_set_level(0);
    fd.registerComponents(ecsu_world);
    fr.registerRelations(ecsu_world);

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    main_window.setInputMode(.cursor, .disabled);

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(gfx_state, std.heap.page_allocator);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    zmesh.init(arena);
    defer zmesh.deinit();

    var prefab_manager = pm.PrefabManager.init(&ecsu_world, std.heap.page_allocator);
    defer prefab_manager.deinit();
    config.prefab.initPrefabs(&prefab_manager, &ecsu_world, std.heap.page_allocator, gfx_state);

    var event_manager = EventManager.create(std.heap.page_allocator);
    defer event_manager.destroy();

    const input_target_defaults = config.input.createDefaultTargetDefaults(std.heap.page_allocator);
    const input_keymap = config.input.createKeyMap(std.heap.page_allocator);
    var input_frame_data = input.FrameData.create(std.heap.page_allocator, input_keymap, input_target_defaults, main_window);
    var input_sys = try input_system.create(
        IdLocal.init("input_sys"),
        std.heap.page_allocator,
        ecsu_world,
        &input_frame_data,
    );
    defer input_system.destroy(input_sys);

    var asset_manager = AssetManager.create(std.heap.page_allocator);
    defer asset_manager.destroy();

    var world_patch_mgr = world_patch_manager.WorldPatchManager.create(std.heap.page_allocator, &asset_manager);
    world_patch_mgr.debug_server.run();
    defer world_patch_mgr.destroy();
    patch_types.registerPatchTypes(world_patch_mgr);

    var system_context = util.Context.init(std.heap.page_allocator);
    system_context.putConst(config.allocator, &std.heap.page_allocator);
    system_context.put(config.ecsu_world, &ecsu_world);
    system_context.put(config.event_manager, &event_manager);
    system_context.put(config.world_patch_mgr, world_patch_mgr);
    system_context.put(config.prefab_manager, &prefab_manager);

    var physics_world: *zphy.PhysicsSystem = undefined;

    var gameloop_context = .{
        .allocator = std.heap.page_allocator,
        .audio_mgr = &audio_mgr,
        .ecsu_world = ecsu_world,
        .event_manager = &event_manager,
        .input_frame_data = &input_frame_data,
        .physics_world = physics_world, // TODO: Optional
        .prefab_manager = &prefab_manager,
        .gfx = gfx_state,
    };

    var physics_sys = try physics_system.create(
        IdLocal.init("physics_system"),
        system_context,
    );
    defer physics_system.destroy(physics_sys);
    gameloop_context.physics_world = physics_sys.physics_world;

    var state_machine_sys = try state_machine_system.create(
        IdLocal.init("state_machine_sys"),
        std.heap.page_allocator,
        state_machine_system.SystemCtx.view(gameloop_context),
    );
    defer state_machine_system.destroy(state_machine_sys);

    system_context.put(config.input_frame_data, &input_frame_data);
    system_context.putOpaque(config.physics_world, physics_sys.physics_world);

    var interact_sys = try interact_system.create(
        IdLocal.init("interact_sys"),
        interact_system.SystemCtx.view(gameloop_context),
    );
    defer interact_system.destroy(interact_sys);

    var timeline_sys = try timeline_system.create(
        IdLocal.init("timeline_sys"),
        system_context,
    );
    defer timeline_system.destroy(timeline_sys);

    var city_sys = try city_system.create(
        IdLocal.init("city_system"),
        std.heap.page_allocator,
        gfx_state,
        ecsu_world,
        physics_sys.physics_world,
        &asset_manager,
        &prefab_manager,
    );
    defer city_system.destroy(city_sys);

    var camera_sys = try camera_system.create(
        IdLocal.init("camera_system"),
        std.heap.page_allocator,
        gfx_state,
        ecsu_world,
        &input_frame_data,
    );
    defer camera_system.destroy(camera_sys);

    var patch_prop_sys = try patch_prop_system.create(
        IdLocal.initFormat("patch_prop_system_{}", .{0}),
        std.heap.page_allocator,
        ecsu_world,
        world_patch_mgr,
        &prefab_manager,
    );
    defer patch_prop_system.destroy(patch_prop_sys);

    var light_sys = try light_system.create(
        IdLocal.initFormat("light_system_{}", .{0}),
        std.heap.page_allocator,
        gfx_state,
        &ecsu_world,
        &input_frame_data,
    );
    defer light_system.destroy(light_sys);

    var static_mesh_renderer_sys = try static_mesh_renderer_system.create(
        IdLocal.initFormat("static_mesh_renderer_system_{}", .{0}),
        std.heap.page_allocator,
        gfx_state,
        &ecsu_world,
        &input_frame_data,
    );
    defer static_mesh_renderer_system.destroy(static_mesh_renderer_sys);

    var terrain_quad_tree_sys = try terrain_quad_tree_system.create(
        IdLocal.initFormat("terrain_quad_tree_system{}", .{0}),
        std.heap.page_allocator,
        gfx_state,
        ecsu_world,
        world_patch_mgr,
    );
    defer terrain_quad_tree_system.destroy(terrain_quad_tree_sys);

    city_system.createEntities(city_sys);

    // Make sure systems are initialized and any initial system entities are created.
    update(ecsu_world, gfx_state);

    // ███████╗███╗   ██╗████████╗██╗████████╗██╗███████╗███████╗
    // ██╔════╝████╗  ██║╚══██╔══╝██║╚══██╔══╝██║██╔════╝██╔════╝
    // █████╗  ██╔██╗ ██║   ██║   ██║   ██║   ██║█████╗  ███████╗
    // ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║   ██║██╔══╝  ╚════██║
    // ███████╗██║ ╚████║   ██║   ██║   ██║   ██║███████╗███████║
    // ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   ╚═╝   ╚═╝╚══════╝╚══════╝

    const sun_light = ecsu_world.newEntity();
    sun_light.set(fd.Rotation.initFromEulerDegrees(50.0, -30.0, 0.0));
    sun_light.set(fd.DirectionalLight{
        .color = .{ .r = 0.5, .g = 0.5, .b = 0.8 },
        .intensity = 0.5,
    });

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
            // tl_giant_ant_spawn_ctx.root_ent = city_ent;
            break :blk .{
                .pos = comps.pos.*,
                .spawnpoint_ent = spawnpoint_ent,
                .city_ent = city_ent,
            };
        }
        break :blk null;
    };

    const DEBUG_CAMERA_ACTIVE = false;

    const player_pos = if (player_spawn) |ps| ps.pos else fd.Position.init(100, 100, 100);
    // const player_pos = fd.Position.init(100, 100, 100);
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
        .window = main_window,
        .active = DEBUG_CAMERA_ACTIVE,
        .class = 0,
    });
    debug_camera_ent.set(fd.WorldLoader{
        .range = 2,
        .props = true,
    });
    debug_camera_ent.set(fd.Input{ .active = DEBUG_CAMERA_ACTIVE, .index = 1 });
    debug_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("debug_camera") });

    // // ██████╗  ██████╗ ██╗    ██╗
    // // ██╔══██╗██╔═══██╗██║    ██║
    // // ██████╔╝██║   ██║██║ █╗ ██║
    // // ██╔══██╗██║   ██║██║███╗██║
    // // ██████╔╝╚██████╔╝╚███╔███╔╝
    // // ╚═════╝  ╚═════╝  ╚══╝╚══╝

    const bow_ent = prefab_manager.instantiatePrefab(&ecsu_world, config.prefab.bow);
    bow_ent.set(fd.Position{ .x = 0.25, .y = 0, .z = 1 });
    bow_ent.set(fd.ProjectileWeapon{});

    var proj_ent = ecsu_world.newEntity();
    proj_ent.set(fd.Projectile{});

    // // ██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗
    // // ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗
    // // ██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝
    // // ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗
    // // ██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║
    // // ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

    const player_ent = prefab_manager.instantiatePrefab(&ecsu_world, config.prefab.player);
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

    const sphere_prefab = prefab_manager.getPrefabByPath("content/prefabs/primitives/primitive_sphere.gltf").?;
    const player_camera_ent = prefab_manager.instantiatePrefab(&ecsu_world, sphere_prefab);
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
        .window = main_window,
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
            .physics_world = physics_sys.physics_world,
            .prefab_manager = &prefab_manager,
            .event_manager = &event_manager,
            .timeline_system = timeline_sys,
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

    ecsu_world.setSingleton(fd.EnvironmentInfo{
        .paused = false,
        .time_of_day_percent = 0,
        .sun_height = 0,
        .world_time = 0,
    });

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
        gfx.beginFrame(gfx_state);

        const trazy_zone = ztracy.ZoneNC(@src(), "Game Loop Update", 0x00_00_00_ff);
        defer trazy_zone.End();

        const window_status = window.update(gfx_state) catch unreachable;
        if (window_status == .no_windows) {
            break;
        }
        if (input_frame_data.just_pressed(config.input.exit)) {
            break;
        }

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

        const camera_comps = getActiveCamera(ecsu_world);
        if (camera_comps) |comps| {
            gfx.endFrame(gfx_state, comps.camera, comps.transform.getPos00());
        } else {
            const camera = fd.Camera{
                .near = 0.01,
                .far = 100.0,
                .fov = 1,
                .view = undefined,
                .projection = undefined,
                .view_projection = undefined,
                .window = undefined,
                .active = true,
                .class = 0,
            };

            const transform = fd.Transform{
                .matrix = undefined,
            };

            gfx.endFrame(gfx_state, &camera, transform.getPos00());
        }
    }
}

var once_per_duration_test: f32 = 0;

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

fn getActiveCamera(ecsu_world: ecsu.World) ?struct { camera: *const fd.Camera, transform: *const fd.Transform } {
    var builder = ecsu.QueryBuilder.init(ecsu_world);
    _ = builder
        .withReadonly(fd.Camera)
        .withReadonly(fd.Transform);

    var filter = builder.buildFilter();
    defer filter.deinit();

    const CameraQueryComps = struct {
        cam: *const fd.Camera,
        transform: *const fd.Transform,
    };

    var entity_iter_camera = filter.iterator(CameraQueryComps);
    while (entity_iter_camera.next()) |comps| {
        if (comps.cam.active) {
            ecs.iter_fini(entity_iter_camera.iter);
            return .{ .camera = comps.cam, .transform = comps.transform };
        }
    }

    return null;
}
