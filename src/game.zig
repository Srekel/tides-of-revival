const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");
const RndGen = std.rand.DefaultPrng;

const window = @import("window.zig");
const gfx = @import("gfx_d3d12.zig");
const camera_system = @import("systems/camera_system.zig");
const city_system = @import("systems/procgen/city_system.zig");
// const gui_system = @import("systems/gui_system.zig");
const input_system = @import("systems/input_system.zig");
const input = @import("input.zig");
const physics_system = @import("systems/physics_system.zig");
const terrain_quad_tree_system = @import("systems/terrain_quad_tree.zig");
const procmesh_system = @import("systems/procedural_mesh_system.zig");
const state_machine_system = @import("systems/state_machine_system.zig");
const terrain_system = @import("systems/terrain_system.zig");
const fd = @import("flecs_data.zig");
const fr = @import("flecs_relation.zig");
const config = @import("config.zig");
// const quality = @import("data/quality.zig");
const IdLocal = @import("variant.zig").IdLocal;
const zaudio = @import("zaudio");
const znoise = @import("znoise");
const ztracy = @import("ztracy");

const fsm = @import("fsm/fsm.zig");

pub fn run() void {
    const tracy_zone = ztracy.ZoneNC(@src(), "Game Run", 0x00_ff_00_00);
    defer tracy_zone.End();

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
    const main_window = window.createWindow("The Elvengroin Legacy") catch unreachable;
    main_window.setInputMode(.cursor, .disabled);

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state, std.heap.page_allocator);

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
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_camera_switch, .source = input.BindingSource{ .keyboard_key = .tab } });
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
        std.heap.c_allocator,
        &flecs_world,
        &input_frame_data,
    );
    defer input_system.destroy(input_sys);

    var physics_sys = try physics_system.create(
        IdLocal.init("physics_system_{}"),
        std.heap.page_allocator,
        &flecs_world,
    );
    defer physics_system.destroy(physics_sys);

    var state_machine_sys = try state_machine_system.create(
        IdLocal.init("state_machine_sys"),
        std.heap.c_allocator,
        &flecs_world,
        &input_frame_data,
        physics_sys.physics_world,
        audio_engine,
    );
    defer state_machine_system.destroy(state_machine_sys);

    const terrain_noise: znoise.FnlGenerator = .{
        .seed = @intCast(i32, 1234),
        .fractal_type = .fbm,
        .frequency = 0.0001,
        .octaves = 7,
    };

    var city_sys = try city_system.create(
        IdLocal.init("city_system"),
        std.heap.c_allocator,
        &gfx_state,
        &flecs_world,
        physics_sys.physics_world,
        terrain_noise,
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

    var procmesh_sys = try procmesh_system.create(
        IdLocal.initFormat("procmesh_system_{}", .{0}),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
    );
    defer procmesh_system.destroy(procmesh_sys);

    var terrain_sys = try terrain_system.create(
        IdLocal.init("terrain_system"),
        std.heap.c_allocator,
        &gfx_state,
        &flecs_world,
        physics_sys.physics_world,
        terrain_noise,
    );
    defer terrain_system.destroy(terrain_sys);

    // var gui_sys = try gui_system.create(
    //     std.heap.page_allocator,
    //     &gfx_state,
    //     main_window,
    // );
    // defer gui_system.destroy(&gui_sys);

    city_system.createEntities(city_sys);

    // Make sure systems are initialized and any initial system entities are created.
    update(&flecs_world, &gfx_state);

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
    // entity3.set(fd.Transform.init(150, 500, 0.6));
    // entity3.set(fd.Scale.createScalar(10.5));
    // // entity3.set(fd.Velocity{ .x = -10, .y = 0, .z = 0 });
    // entity3.set(fd.CIShapeMeshInstance{
    //     .id = IdLocal.id64("sphere"),
    //     .basecolor_roughness = .{ .r = 0.7, .g = 0.0, .b = 1.0, .roughness = 0.8 },
    // });
    // entity3.set(fd.CIPhysicsBody{
    //     .shape_type = .sphere,
    //     .mass = 1,
    //     .sphere = .{ .radius = 10.5 },
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
    });
    debug_camera_ent.set(fd.Input{ .active = true, .index = 1 });
    debug_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("debug_camera") });

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
    player_ent.set(fd.CIShapeMeshInstance{
        .id = IdLocal.id64("cylinder"),
        .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 1.0, .roughness = 0.8 },
    });
    player_ent.set(fd.WorldLoader{
        .range = 2,
    });
    player_ent.set(fd.Input{ .active = false, .index = 0 });
    player_ent.set(fd.Health{ .value = 100 });
    if (player_spawn) |ps| {
        player_ent.addPair(fr.Hometown, ps.city_ent);
    }

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
    player_camera_ent.set(fd.CIShapeMeshInstance{
        .id = IdLocal.id64("sphere"),
        .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 1.0, .roughness = 0.8 },
    });
    player_camera_ent.set(fd.Light{ .radiance = .{ .r = 4, .g = 2, .b = 1 }, .range = 10 });

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
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            break;
        }
        if (input_frame_data.just_pressed(config.input_exit)) {
            break;
        }

        update(&flecs_world, &gfx_state);
    }
}

fn update(flecs_world: *flecs.World, gfx_state: *gfx.D3D12State) void {
    // const stats = gfx_state.gctx.stats;
    const stats = gfx_state.stats;
    const dt = @floatCast(f32, stats.delta_time);

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

    gfx.update(gfx_state);
    // gui_system.preUpdate(&gui_sys);

    flecs_world.progress(dt);
    // gui_system.update(&gui_sys);
    gfx.draw(gfx_state);
}
