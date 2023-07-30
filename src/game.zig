const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");
const zaudio = @import("zaudio");
const zmesh = @import("zmesh");
const zphy = @import("zphysics");
const zstbi = @import("zstbi");
const ztracy = @import("ztracy");

const AssetManager = @import("core/asset_manager.zig").AssetManager;
const Variant = @import("variant.zig").Variant;
const IdLocal = @import("variant.zig").IdLocal;
const config = @import("config.zig");
const util = @import("util.zig");
const fd = @import("flecs_data.zig");
const fr = @import("flecs_relation.zig");
const fsm = @import("fsm/fsm.zig");
const gfx = @import("gfx_d3d12.zig");
const pm = @import("prefab_manager.zig");
const window = @import("window.zig");
const EventManager = @import("core/event_manager.zig").EventManager;

const patch_types = @import("worldpatch/patch_types.zig");
const world_patch_manager = @import("worldpatch/world_patch_manager.zig");
// const quality = @import("data/quality.zig");

const camera_system = @import("systems/camera_system.zig");
const city_system = @import("systems/procgen/city_system.zig");
const input_system = @import("systems/input_system.zig");
const input = @import("input.zig");
const interact_system = @import("systems/interact_system.zig");
const physics_system = @import("systems/physics_system.zig");
const terrain_quad_tree_system = @import("systems/terrain_quad_tree.zig");
const patch_prop_system = @import("systems/patch_prop_system.zig");
const procmesh_system = @import("systems/procedural_mesh_system.zig");
const static_mesh_renderer_system = @import("systems/static_mesh_renderer_system.zig");
const state_machine_system = @import("systems/state_machine_system.zig");
const timeline_system = @import("systems/timeline_system.zig");
// const terrain_system = @import("systems/terrain_system.zig");
// const gui_system = @import("systems/gui_system.zig");

const SpawnContext = struct {
    flecs_world: *flecs.World,
    physics_world: *zphy.PhysicsSystem,
    // player_pos: [3]f32,
};

var spider_prefab: flecs.Entity = undefined;
var bow_prefab: flecs.Entity = undefined;
var arrow_prefab: flecs.Entity = undefined;

fn spawnSpider(entity: flecs.EntityId, data: *anyopaque) void {
    _ = entity;
    const ctx = util.castOpaque(SpawnContext, data);
    // TODO(gmodarelli): Maybe we need a function to instantiate a prefab
    // TODO(gmodarelli): This should be in flecs_relations.zig
    const is_a = flecs.Entity.init(ctx.flecs_world.world, flecs.c.Constants.EcsIsA);

    const player_ent_id = flecs.c.ecs_lookup(ctx.flecs_world.world, "player");
    const player_ent = flecs.Entity{ .id = player_ent_id, .world = ctx.flecs_world.world };
    const player_pos = player_ent.get(fd.Position).?;

    var ent = ctx.flecs_world.newEntity();
    ent.addPair(is_a, spider_prefab);

    var spawn_pos = [3]f32{
        player_pos.x + 10,
        player_pos.y + 2,
        player_pos.z + 10,
    };
    ent.setOverride(fd.Position{
        .x = spawn_pos[0],
        .y = spawn_pos[1],
        .z = spawn_pos[2],
    });
    ent.set(fd.Health{ .value = 100 });

    ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("spider") });

    const body_interface = ctx.physics_world.getBodyInterfaceMut();

    const shape_settings = zphy.BoxShapeSettings.create(.{ 0.5, 0.5, 0.5 }) catch unreachable;
    defer shape_settings.release();

    const shape = shape_settings.createShape() catch unreachable;
    defer shape.release();

    const body_id = body_interface.createAndAddBody(.{
        .position = .{ spawn_pos[0], spawn_pos[1], spawn_pos[2], 0 },
        .rotation = .{ 0, 0, 0, 1 },
        .shape = shape,
        .motion_type = .kinematic,
        .object_layer = config.object_layers.moving,
        .motion_quality = .discrete,
        .user_data = ent.id,
    }, .activate) catch unreachable;

    //  Assign to flecs component
    ent.set(fd.PhysicsBody{ .body_id = body_id });
}

pub fn run() void {
    const tracy_zone = ztracy.ZoneNC(@src(), "Game Run", 0x00_ff_00_00);
    defer tracy_zone.End();

    zstbi.init(std.heap.page_allocator);
    defer zstbi.deinit();

    zaudio.init(std.heap.page_allocator);
    defer zaudio.deinit();
    const audio_engine = zaudio.Engine.create(null) catch unreachable;
    defer audio_engine.destroy();
    // const music = audio_engine.createSoundFromFile(
    //     "content/audio/music/Winter_Fire_Final.mp3",
    //     .{ .flags = .{ .stream = true } },
    // ) catch unreachable;
    // music.start() catch unreachable;
    // defer music.destroy();

    var flecs_world = flecs.World.init();
    defer flecs_world.deinit();
    _ = flecs.c.ecs_log_set_level(0);

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival") catch unreachable;
    main_window.setInputMode(.cursor, .disabled);

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state, std.heap.page_allocator);

    var prefab_manager = pm.PrefabManager.init(std.heap.page_allocator);
    defer prefab_manager.deinit();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    zmesh.init(arena);
    defer zmesh.deinit();

    // TODO(gmodarelli): Add a function to destroy the prefab's GPU resources
    spider_prefab = prefab_manager.loadPrefabFromGLTF("content/prefabs/creatures/spider/spider.gltf", &flecs_world, &gfx_state, std.heap.page_allocator) catch unreachable;
    bow_prefab = prefab_manager.loadPrefabFromGLTF("content/prefabs/props/bow_arrow/bow.gltf", &flecs_world, &gfx_state, std.heap.page_allocator) catch unreachable;
    arrow_prefab = prefab_manager.loadPrefabFromGLTF("content/prefabs/props/bow_arrow/arrow.gltf", &flecs_world, &gfx_state, std.heap.page_allocator) catch unreachable;

    var event_manager = EventManager.create(std.heap.page_allocator);
    defer event_manager.destroy();

    const input_target_defaults = blk: {
        var itm = input.TargetMap.init(std.heap.page_allocator);
        itm.ensureUnusedCapacity(18) catch unreachable;
        itm.putAssumeCapacity(config.input_move_left, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_right, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_forward, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_backward, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_up, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_down, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_slow, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_fast, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_interact, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_wielded_use_primary, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_wielded_use_secondary, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_cursor_pos, input.TargetValue{ .vector2 = .{ 0, 0 } });
        itm.putAssumeCapacity(config.input_cursor_movement, input.TargetValue{ .vector2 = .{ 0, 0 } });
        itm.putAssumeCapacity(config.input_cursor_movement_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_cursor_movement_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_gamepad_look_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_gamepad_look_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_gamepad_move_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_gamepad_move_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_look_yaw, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_look_pitch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_camera_switch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_camera_freeze_rendering, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_exit, input.TargetValue{ .number = 0 });
        break :blk itm;
    };

    const keymap = blk: {
        //
        // KEYBOARD
        //
        var keyboard_map = input.DeviceKeyMap{
            .device_type = .keyboard,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        keyboard_map.bindings.ensureTotalCapacity(18) catch unreachable;
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_left, .source = input.BindingSource{ .keyboard_key = .a } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_right, .source = input.BindingSource{ .keyboard_key = .d } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_forward, .source = input.BindingSource{ .keyboard_key = .w } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_backward, .source = input.BindingSource{ .keyboard_key = .s } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_up, .source = input.BindingSource{ .keyboard_key = .e } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_down, .source = input.BindingSource{ .keyboard_key = .q } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_slow, .source = input.BindingSource{ .keyboard_key = .left_control } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_fast, .source = input.BindingSource{ .keyboard_key = .left_shift } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_interact, .source = input.BindingSource{ .keyboard_key = .f } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_wielded_use_primary, .source = input.BindingSource{ .mouse_button = .left } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_wielded_use_secondary, .source = input.BindingSource{ .mouse_button = .right } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_camera_switch, .source = input.BindingSource{ .keyboard_key = .tab } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_camera_freeze_rendering, .source = input.BindingSource{ .keyboard_key = .r } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_exit, .source = input.BindingSource{ .keyboard_key = .escape } });

        //
        // MOUSE
        //
        var mouse_map = input.DeviceKeyMap{
            .device_type = .mouse,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        mouse_map.bindings.ensureTotalCapacity(8) catch unreachable;
        mouse_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_cursor_pos, .source = .mouse_cursor });
        mouse_map.processors.ensureTotalCapacity(8) catch unreachable;
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_cursor_movement,
            .class = input.ProcessorClass{ .vector2diff = input.ProcessorVector2Diff{ .source_target = config.input_cursor_pos } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_cursor_movement_x,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = config.input_cursor_movement,
                .conversion = .xy_to_x,
            } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_cursor_movement_y,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = config.input_cursor_movement,
                .conversion = .xy_to_y,
            } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_look_yaw,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = config.input_cursor_movement,
                .conversion = .xy_to_x,
            } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_look_pitch,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = config.input_cursor_movement,
                .conversion = .xy_to_y,
            } },
        });

        //
        // GAMEPAD
        //
        var gamepad_map = input.DeviceKeyMap{
            .device_type = .gamepad,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        gamepad_map.bindings.ensureTotalCapacity(8) catch unreachable;
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_gamepad_look_x, .source = input.BindingSource{ .gamepad_axis = .right_x } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_gamepad_look_y, .source = input.BindingSource{ .gamepad_axis = .right_y } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_gamepad_move_x, .source = input.BindingSource{ .gamepad_axis = .left_x } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_gamepad_move_y, .source = input.BindingSource{ .gamepad_axis = .left_y } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_slow, .source = input.BindingSource{ .gamepad_button = .left_bumper } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_fast, .source = input.BindingSource{ .gamepad_button = .right_bumper } });
        gamepad_map.processors.ensureTotalCapacity(16) catch unreachable;
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_gamepad_look_x,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = config.input_gamepad_look_x, .zone = 0.2 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_gamepad_look_y,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = config.input_gamepad_look_y, .zone = 0.2 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_gamepad_move_x,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = config.input_gamepad_move_x, .zone = 0.2 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_gamepad_move_y,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = config.input_gamepad_move_y, .zone = 0.2 } },
        });

        // Sensitivity
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_look_yaw,
            .class = input.ProcessorClass{ .scalar = input.ProcessorScalar{ .source_target = config.input_gamepad_look_x, .multiplier = 10 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_look_pitch,
            .class = input.ProcessorClass{ .scalar = input.ProcessorScalar{ .source_target = config.input_gamepad_look_y, .multiplier = 10 } },
        });

        // Movement axis to left/right forward/backward
        // TODO: better to store movement as vector
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_move_left,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = config.input_gamepad_move_x, .is_positive = false } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_move_right,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = config.input_gamepad_move_x, .is_positive = true } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_move_forward,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = config.input_gamepad_move_y, .is_positive = false } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = config.input_move_backward,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = config.input_gamepad_move_y, .is_positive = true } },
        });

        var layer_on_foot = input.KeyMapLayer{
            .id = IdLocal.init("on_foot"),
            .active = true,
            .device_maps = std.ArrayList(input.DeviceKeyMap).init(std.heap.page_allocator),
        };
        layer_on_foot.device_maps.append(keyboard_map) catch unreachable;
        layer_on_foot.device_maps.append(mouse_map) catch unreachable;
        layer_on_foot.device_maps.append(gamepad_map) catch unreachable;

        var map = input.KeyMap{
            .layer_stack = std.ArrayList(input.KeyMapLayer).init(std.heap.page_allocator),
        };
        map.layer_stack.append(layer_on_foot) catch unreachable;
        break :blk map;
    };

    var input_frame_data = input.FrameData.create(std.heap.page_allocator, keymap, input_target_defaults, main_window);
    var input_sys = try input_system.create(
        IdLocal.init("input_sys"),
        std.heap.page_allocator,
        &flecs_world,
        &input_frame_data,
    );
    defer input_system.destroy(input_sys);

    // const HeightmapPatchLoader = struct {
    //     pub fn load(patch: *world_patch_manager.Patch) void {
    //         _ = patch;
    //     }
    // };

    var asset_manager = AssetManager.create(std.heap.page_allocator);
    defer asset_manager.destroy();

    var world_patch_mgr = world_patch_manager.WorldPatchManager.create(std.heap.page_allocator, &asset_manager);
    world_patch_mgr.debug_server.run();
    defer world_patch_mgr.destroy();
    patch_types.registerPatchTypes(world_patch_mgr);

    var system_context = util.Context.init(std.heap.page_allocator);
    system_context.putConst(config.allocator, &std.heap.page_allocator);
    system_context.put(config.flecs_world, &flecs_world);
    system_context.put(config.event_manager, &event_manager);
    system_context.put(config.world_patch_mgr, world_patch_mgr);

    var physics_sys = try physics_system.create(
        IdLocal.init("physics_system"),
        system_context,
    );
    defer physics_system.destroy(physics_sys);

    var state_machine_sys = try state_machine_system.create(
        IdLocal.init("state_machine_sys"),
        std.heap.page_allocator,
        &flecs_world,
        &input_frame_data,
        physics_sys.physics_world,
        audio_engine,
    );
    defer state_machine_system.destroy(state_machine_sys);

    system_context.put(config.input_frame_data, &input_frame_data);
    system_context.putOpaque(config.physics_world, physics_sys.physics_world);

    const is_a = flecs.Entity.init(flecs_world.world, flecs.c.Constants.EcsIsA);
    var interact_sys = try interact_system.create(
        IdLocal.init("interact_sys"),
        system_context,
        // TODO(gmodarelli): These last 2 params are temporary
        arrow_prefab,
        is_a,
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
        &gfx_state,
        &flecs_world,
        physics_sys.physics_world,
        &asset_manager,
    );
    defer city_system.destroy(city_sys);

    var camera_sys = try camera_system.create(
        IdLocal.init("camera_system"),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
        &input_frame_data,
    );
    defer camera_system.destroy(camera_sys);

    var patch_prop_sys = try patch_prop_system.create(
        IdLocal.initFormat("patch_prop_system_{}", .{0}),
        std.heap.page_allocator,
        &flecs_world,
        world_patch_mgr,
    );
    defer patch_prop_system.destroy(patch_prop_sys);

    var procmesh_sys = try procmesh_system.create(
        IdLocal.initFormat("procmesh_system_{}", .{0}),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
        &input_frame_data,
    );
    defer procmesh_system.destroy(procmesh_sys);

    var static_mesh_renderer_sys = try static_mesh_renderer_system.create(
        IdLocal.initFormat("static_mesh_renderer_system_{}", .{0}),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
        &input_frame_data,
    );
    defer static_mesh_renderer_system.destroy(static_mesh_renderer_sys);

    var terrain_quad_tree_sys = try terrain_quad_tree_system.create(
        IdLocal.initFormat("terrain_quad_tree_system{}", .{0}),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
        world_patch_mgr,
    );
    defer terrain_quad_tree_system.destroy(terrain_quad_tree_sys);

    city_system.createEntities(city_sys);

    // Make sure systems are initialized and any initial system entities are created.
    update(&flecs_world, &gfx_state);

    // ████████╗██╗███╗   ███╗███████╗██╗     ██╗███╗   ██╗███████╗███████╗
    // ╚══██╔══╝██║████╗ ████║██╔════╝██║     ██║████╗  ██║██╔════╝██╔════╝
    //    ██║   ██║██╔████╔██║█████╗  ██║     ██║██╔██╗ ██║█████╗  ███████╗
    //    ██║   ██║██║╚██╔╝██║██╔══╝  ██║     ██║██║╚██╗██║██╔══╝  ╚════██║
    //    ██║   ██║██║ ╚═╝ ██║███████╗███████╗██║██║ ╚████║███████╗███████║
    //    ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝

    var tl_spider_spawn_ctx = SpawnContext{
        .flecs_world = &flecs_world,
        .physics_world = physics_sys.physics_world,
        // .player_ent =
    };

    const tl_spider_spawn = config.events.TimelineTemplateData{
        .id = IdLocal.init("spiderSpawn"),
        .events = &[_]timeline_system.TimelineEvent{
            .{
                .trigger_time = 5,
                .trigger_id = IdLocal.init("onSpawnAroundPlayer"),
                .func = spawnSpider,
                .data = &tl_spider_spawn_ctx,
            },
        },
        // .curves = &[_]timeline_system.TimelineCurve{
        //     .{
        //         .curve_type = .quality{
        //             .component_name = "Health",
        //         },
        //         .curve_type = .run_a_function{
        //             .func = null,
        //             .data = null,
        //         },
        //     },
        // },
        .loop_behavior = .loop_no_time_loss,
    };

    const tli_spider_spawn = config.events.TimelineInstanceData{
        .ent = 0,
        .timeline = IdLocal.init("spiderSpawn"),
    };

    event_manager.triggerEvent(config.events.onRegisterTimeline_id, &tl_spider_spawn);
    event_manager.triggerEvent(config.events.onAddTimelineInstance_id, &tli_spider_spawn);

    // ███████╗███╗   ██╗████████╗██╗████████╗██╗███████╗███████╗
    // ██╔════╝████╗  ██║╚══██╔══╝██║╚══██╔══╝██║██╔════╝██╔════╝
    // █████╗  ██╔██╗ ██║   ██║   ██║   ██║   ██║█████╗  ███████╗
    // ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║   ██║██╔══╝  ╚════██║
    // ███████╗██║ ╚████║   ██║   ██║   ██║   ██║███████╗███████║
    // ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   ╚═╝   ╚═╝╚══════╝╚══════╝

    const player_spawn = blk: {
        var builder = flecs.QueryBuilder.init(flecs_world);
        _ = builder
            .with(fd.SpawnPoint)
            .with(fd.Position);

        var filter = builder.buildFilter();
        defer filter.deinit();

        var entity_iter = filter.iterator(struct { spawn_point: *fd.SpawnPoint, pos: *fd.Position });
        while (entity_iter.next()) |comps| {
            const city_ent = flecs.c.ecs_get_target(
                flecs_world.world,
                entity_iter.entity().id,
                flecs_world.componentId(fr.Hometown),
                0,
            );
            const spawnpoint_ent = entity_iter.entity();
            flecs.c.ecs_iter_fini(entity_iter.iter);
            break :blk .{
                .pos = comps.pos.*,
                .spawnpoint_ent = spawnpoint_ent,
                .city_ent = city_ent,
            };
        }
        break :blk null;
    };

    // const entity3 = flecs_world.newEntity();
    // entity3.set(fd.Transform.initWithScale(0, 0, 0, 100));
    // entity3.set(fd.CIStaticMesh{
    //     .id = IdLocal.id64("sphere"),
    //     .basecolor_roughness = .{ .r = 1.0, .g = 0.0, .b = 0.0, .roughness = 0.8 },
    // });
    // entity3.set(fd.CIPhysicsBody{
    //     .shape_type = .sphere,
    //     .mass = 1,
    //     .sphere = .{ .radius = 10.5 },
    // });

    // const entity4 = flecs_world.newEntity();
    // entity4.set(fd.Transform.initWithScale(512, 0, 512, 100));
    // entity4.set(fd.CIStaticMesh{
    //     .id = IdLocal.id64("sphere"),
    //     .basecolor_roughness = .{ .r = 0.0, .g = 0.0, .b = 1.0, .roughness = 0.8 },
    // });

    const player_pos = if (player_spawn) |ps| ps.pos else fd.Position.init(100, 100, 100);
    const debug_camera_ent = flecs_world.newEntity();
    debug_camera_ent.set(fd.Position{ .x = player_pos.x + 100, .y = player_pos.y + 100, .z = player_pos.z + 100 });
    // debug_camera_ent.setPair(fd.Position, fd.LocalSpace, .{ .x = player_pos.x + 100, .y = player_pos.y + 100, .z = player_pos.z + 100 });
    debug_camera_ent.set(fd.EulerRotation{});
    debug_camera_ent.set(fd.Scale{});
    debug_camera_ent.set(fd.Transform{});
    debug_camera_ent.set(fd.Dynamic{});
    debug_camera_ent.set(fd.CICamera{
        .near = 0.1,
        .far = 10000,
        .window = main_window,
        .active = true,
        .class = 0,
    });
    debug_camera_ent.set(fd.WorldLoader{
        .range = 2,
        .props = true,
    });
    debug_camera_ent.set(fd.Input{ .active = true, .index = 1 });
    debug_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("debug_camera") });

    // ██████╗  ██████╗ ██╗    ██╗
    // ██╔══██╗██╔═══██╗██║    ██║
    // ██████╔╝██║   ██║██║ █╗ ██║
    // ██╔══██╗██║   ██║██║███╗██║
    // ██████╔╝╚██████╔╝╚███╔███╔╝
    // ╚═════╝  ╚═════╝  ╚══╝╚══╝

    const bow_ent = flecs_world.newEntity();
    bow_ent.addPair(is_a, bow_prefab);
    bow_ent.setName("bow");
    bow_ent.setOverride(fd.Position{ .x = 0.25, .y = 0, .z = 1 });
    // TODO(gmodarelli): Store components in GLFT 2 from Blender
    bow_ent.set(fd.ProjectileWeapon{});

    var proj_ent = flecs_world.newEntity();
    // proj_ent.setName("arrow2");
    // proj_ent.set(fd.Position{ .x = 0, .y = 0, .z = -0.5 });
    // proj_ent.set(fd.EulerRotation{});
    // proj_ent.set(fd.Scale.createScalar(1));
    // proj_ent.set(fd.Transform{});
    // proj_ent.set(fd.Forward{});
    // proj_ent.set(fd.Dynamic{});
    proj_ent.set(fd.Projectile{});
    // proj_ent.set(fd.CIStaticMesh{
    //     .id = IdLocal.id64("bow"),
    //     .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 1.0, .roughness = 1.0 },
    // });
    // proj_ent.childOf(bow_ent);
    // weapon_comp.chambered_projectile = proj_ent.id;

    // var spider_ent = flecs_world.newEntity();
    // // proj_ent.setName("arrow2");
    // spider_ent.set(fd.Position{ .x = player_pos.x + 10, .y = player_pos.y, .z = player_pos.z + 10 });
    // spider_ent.set(fd.EulerRotation{});
    // spider_ent.set(fd.Scale.createScalar(1));
    // spider_ent.set(fd.Transform{});
    // spider_ent.set(fd.Forward{});
    // spider_ent.set(fd.Dynamic{});
    // spider_ent.set(fd.CIStaticMesh{
    //     .id = IdLocal.id64("spider_body"),
    //     .material = fd.PBRMaterial.initNoTexture(.{ .r = 1.0, .g = 1.0, .b = 1.0 }, 0.8, 0.0),
    // });

    // ██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗
    // ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗
    // ██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝
    // ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗
    // ██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║
    // ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

    // _ = player_pos;
    // const player_height = config.noise_scale_y * (config.noise_offset_y + terrain_noise.noise2(20 * config.noise_scale_xz, 20 * config.noise_scale_xz));
    const player_ent = flecs_world.newEntity();
    player_ent.setName("player");
    player_ent.set(player_pos);
    // player_ent.set(fd.Position{ .x = 20, .y = player_height + 1, .z = 20 });
    player_ent.set(fd.EulerRotation{});
    player_ent.set(fd.Scale.createScalar(1));
    player_ent.set(fd.Transform.initFromPosition(player_pos));
    player_ent.set(fd.Forward{});
    player_ent.set(fd.Velocity{});
    player_ent.set(fd.Dynamic{});
    player_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("player_controller") });
    player_ent.set(fd.CIStaticMesh{
        .id = IdLocal.id64("cylinder"),
        .material = fd.PBRMaterial.initNoTexture(.{ .r = 1.0, .g = 1.0, .b = 1.0 }, 0.8, 0.0),
    });
    player_ent.set(fd.WorldLoader{
        .range = 2,
        .physics = true,
    });
    player_ent.set(fd.Input{ .active = false, .index = 0 });
    player_ent.set(fd.Health{ .value = 100 });
    if (player_spawn) |ps| {
        player_ent.addPair(fr.Hometown, ps.city_ent);
    }

    player_ent.set(fd.Interactor{ .active = true, .wielded_item_ent_id = bow_ent.id });

    const player_camera_ent = flecs_world.newEntity();
    player_camera_ent.childOf(player_ent);
    player_camera_ent.setName("playercamera");
    player_camera_ent.set(fd.Position{ .x = 0, .y = 1.8, .z = 0 });
    player_camera_ent.set(fd.EulerRotation{});
    player_camera_ent.set(fd.Scale.createScalar(1));
    player_camera_ent.set(fd.Transform{});
    player_camera_ent.set(fd.Dynamic{});
    player_camera_ent.set(fd.Forward{});
    player_camera_ent.set(fd.CICamera{
        .near = 0.1,
        .far = 10000,
        .window = main_window,
        .active = false,
        .class = 1,
    });
    player_camera_ent.set(fd.Input{ .active = false, .index = 0 });
    player_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("fps_camera") });
    player_camera_ent.set(fd.CIStaticMesh{
        .id = IdLocal.id64("sphere"),
        .material = fd.PBRMaterial.initNoTexture(.{ .r = 1.0, .g = 1.0, .b = 1.0 }, 0.8, 0.0),
    });
    player_camera_ent.set(fd.Light{ .radiance = .{ .r = 4, .g = 2, .b = 1 }, .range = 10 });
    bow_ent.childOf(player_camera_ent);

    // ███████╗██╗     ███████╗ ██████╗███████╗
    // ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
    // █████╗  ██║     █████╗  ██║     ███████╗
    // ██╔══╝  ██║     ██╔══╝  ██║     ╚════██║
    // ██║     ███████╗███████╗╚██████╗███████║
    // ╚═╝     ╚══════╝╚══════╝ ╚═════╝╚══════╝

    flecs_world.setSingleton(fd.EnvironmentInfo{
        .time_of_day_percent = 0,
        .sun_height = 0,
        .world_time = 0,
    });

    // Flecs config
    // Delete children when parent is destroyed
    _ = flecs_world.pair(flecs.c.Constants.EcsOnDeleteTarget, flecs.c.Constants.EcsOnDelete);

    // ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
    // ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
    // ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
    // ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
    // ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
    //  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

    while (true) {
        const window_status = window.update(&gfx_state) catch unreachable;
        if (window_status == .no_windows) {
            break;
        }
        if (input_frame_data.just_pressed(config.input_exit)) {
            break;
        }

        world_patch_mgr.tickOne();
        update(&flecs_world, &gfx_state);
    }
}

fn update(flecs_world: *flecs.World, gfx_state: *gfx.D3D12State) void {
    const stats = gfx_state.stats;
    const dt: f32 = @floatCast(stats.delta_time);

    const flecs_stats = flecs.c.ecs_get_world_info(flecs_world.world);
    {
        const time_multiplier = 24 * 4.0; // day takes quarter of an hour of realtime.. uuh this isn't a great method
        const world_time = flecs_stats.*.world_time_total;
        const environment_info = flecs_world.getSingletonMut(fd.EnvironmentInfo).?;
        const time_of_day_percent = std.math.modf(time_multiplier * world_time / (60 * 60 * 24));
        environment_info.time_of_day_percent = time_of_day_percent.fpart;
        environment_info.sun_height = @sin(0.5 * environment_info.time_of_day_percent * std.math.pi);
        environment_info.world_time = world_time;
    }

    gfx.beginFrame(gfx_state);

    flecs_world.progress(dt);

    const camera_comps = getActiveCamera(flecs_world);
    if (camera_comps) |comps| {
        gfx.endFrame(gfx_state, comps.camera, comps.transform.getPos00());
    } else {
        const camera = fd.Camera{
            .near = 0.01,
            .far = 100.0,
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

fn getActiveCamera(flecs_world: *flecs.World) ?struct { camera: *const fd.Camera, transform: *const fd.Transform } {
    var builder = flecs.QueryBuilder.init(flecs_world.*);
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
            return .{ .camera = comps.cam, .transform = comps.transform };
        }
    }

    return null;
}
