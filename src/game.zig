const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");
const RndGen = std.rand.DefaultPrng;

const window = @import("window.zig");
const gfx = @import("gfx_wgpu.zig");
const camera_system = @import("systems/camera_system.zig");
const city_system = @import("systems/procgen/city_system.zig");
// const gui_system = @import("systems/gui_system.zig");
const input_system = @import("systems/input_system.zig");
const input = @import("input.zig");
const physics_system = @import("systems/physics_system.zig");
const procmesh_system = @import("systems/procedural_mesh_system.zig");
const state_machine_system = @import("systems/state_machine_system.zig");
const terrain_system = @import("systems/terrain_system.zig");
const triangle_system = @import("systems/triangle_system.zig");
const fd = @import("flecs_data.zig");
const config = @import("config.zig");
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
    const music = audio_engine.createSoundFromFile(
        "content/audio/music/Winter_Fire_Final.mp3",
        .{ .flags = .{ .stream = true } },
    ) catch unreachable;
    music.start() catch unreachable;

    var flecs_world = flecs.World.init();
    defer flecs_world.deinit();

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("The Elvengroin Legacy") catch unreachable;
    main_window.setInputMode(.cursor, .disabled);

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state);

    const input_target_defaults = blk: {
        var itm = input.TargetMap.init(std.heap.page_allocator);
        itm.ensureUnusedCapacity(16) catch unreachable;
        itm.putAssumeCapacity(config.input_move_left, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_right, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_forward, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_backward, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_slow, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_move_fast, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_cursor_pos, input.TargetValue{ .vector2 = .{ 0, 0 } });
        itm.putAssumeCapacity(config.input_cursor_movement, input.TargetValue{ .vector2 = .{ 0, 0 } });
        itm.putAssumeCapacity(config.input_cursor_movement_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_cursor_movement_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_look_yaw, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_look_pitch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_camera_switch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(config.input_exit, input.TargetValue{ .number = 0 });
        break :blk itm;
    };

    const keymap = blk: {
        var keyboard_map = input.DeviceKeyMap{
            .device_type = .keyboard,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        keyboard_map.bindings.ensureTotalCapacity(16) catch unreachable;
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_left, .source = input.BindingSource{ .keyboard_key = .a } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_right, .source = input.BindingSource{ .keyboard_key = .d } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_forward, .source = input.BindingSource{ .keyboard_key = .w } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_backward, .source = input.BindingSource{ .keyboard_key = .s } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_slow, .source = input.BindingSource{ .keyboard_key = .left_control } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_move_fast, .source = input.BindingSource{ .keyboard_key = .left_shift } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_camera_switch, .source = input.BindingSource{ .keyboard_key = .tab } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = config.input_exit, .source = input.BindingSource{ .keyboard_key = .escape } });

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

        var layer_on_foot = input.KeyMapLayer{
            .id = IdLocal.init("on_foot"),
            .active = true,
            .device_maps = std.ArrayList(input.DeviceKeyMap).init(std.heap.page_allocator),
        };
        layer_on_foot.device_maps.append(keyboard_map) catch unreachable;
        layer_on_foot.device_maps.append(mouse_map) catch unreachable;

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
        .octaves = 10,
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

    const debug_camera_ent = flecs_world.newEntity();
    debug_camera_ent.set(fd.Position{ .x = 200, .y = 200, .z = 50 });
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

    const player_pos = blk: {
        var builder = flecs.QueryBuilder.init(flecs_world);
        _ = builder
            .with(fd.SpawnPoint)
            .with(fd.Position);

        var filter = builder.buildFilter();
        defer filter.deinit();

        var entity_iter = filter.iterator(struct { spawn_point: *fd.SpawnPoint, pos: *fd.Position });
        while (entity_iter.next()) |comps| {
            break :blk comps.pos.*;
        }
        unreachable;
    };

    // _ = player_pos;
    // const player_height = config.noise_scale_y * (config.noise_offset_y + terrain_noise.noise2(20 * config.noise_scale_xz, 20 * config.noise_scale_xz));
    const player_ent = flecs_world.newEntity();
    player_ent.set(player_pos);
    // player_ent.set(fd.Position{ .x = 20, .y = player_height + 1, .z = 20 });
    player_ent.set(fd.EulerRotation{});
    player_ent.set(fd.Scale.createScalar(1.7));
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
    player_ent.setName("player");
    player_ent.set(fd.Input{ .active = false, .index = 0 });
    player_ent.set(fd.Light{ .radiance = .{ .r = 4, .g = 2, .b = 1 }, .range = 10 });

    const player_camera_ent = flecs_world.newEntity();
    player_camera_ent.set(fd.Position{ .x = 0, .y = 1, .z = 0 });
    player_camera_ent.set(fd.EulerRotation{});
    player_camera_ent.set(fd.Scale.createScalar(0.5));
    player_camera_ent.set(fd.Transform{});
    player_camera_ent.set(fd.Dynamic{});
    player_camera_ent.set(fd.CICamera{
        .near = 0.1,
        .far = 10000,
        .window = main_window,
        .active = false,
        .class = 1,
    });
    player_camera_ent.set(fd.Input{ .active = false, .index = 0 });
    player_camera_ent.set(fd.CIFSM{ .state_machine_hash = IdLocal.id64("fps_camera") });
    player_camera_ent.childOf(player_ent);
    player_camera_ent.setName("playercamera");
    player_camera_ent.set(fd.CIShapeMeshInstance{
        .id = IdLocal.id64("sphere"),
        .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 1.0, .roughness = 0.8 },
    });

    _ = flecs_world.pair(flecs.c.EcsOnDeleteObject, flecs.c.EcsOnDelete);

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

fn update(flecs_world: *flecs.World, gfx_state: *gfx.GfxState) void {
    const stats = gfx_state.gctx.stats;
    // const dt = @floatCast(f32, stats.delta_time) * 0.2;
    const dt = @floatCast(f32, stats.delta_time);
    gfx.update(gfx_state);
    // gui_system.preUpdate(&gui_sys);

    flecs_world.progress(dt);
    // gui_system.update(&gui_sys);
    gfx.draw(gfx_state);
}
