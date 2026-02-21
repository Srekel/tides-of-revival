const std = @import("std");
const input = @import("../input.zig");
const ID = @import("../core/core.zig").ID;

// Debug Layer
pub const toggle_imgui = ID("toggle_imgui");
pub const toggle_player_control = ID("toggle_player_control");

pub const move_left = ID("move_left");
pub const move_right = ID("move_right");
pub const move_forward = ID("move_forward");
pub const move_backward = ID("move_backward");
pub const move_up = ID("move_up");
pub const move_down = ID("move_down");
pub const move_slow = ID("move_slow");
pub const move_fast = ID("move_fast");

pub const interact = ID("interact");
pub const wielded_use_primary = ID("wielded_use_primary");
pub const wielded_use_secondary = ID("wielded_use_secondary");
pub const help = ID("help");
pub const credits = ID("credits");

pub const cursor_pos = ID("cursor_pos");
pub const cursor_movement = ID("cursor_movement");
pub const cursor_movement_x = ID("cursor_movement_x");
pub const cursor_movement_y = ID("cursor_movement_y");

pub const gamepad_look_x = ID("gamepad_look_x");
pub const gamepad_look_y = ID("gamepad_look_y");
pub const gamepad_move_x = ID("gamepad_move_x");
pub const gamepad_move_y = ID("gamepad_move_y");

pub const look_yaw = ID("look_yaw");
pub const look_pitch = ID("look_pitch");

pub const journey = ID("journey");
pub const rest = ID("rest");

pub const camera_switch = ID("camera_switch");
pub const exit = ID("exit");

pub const reload_shaders = ID("reload_shaders");
pub const toggle_vsync = ID("toggle_vsync");
pub const toggle_terrain_shadows = ID("toggle_terrain_shadows");
pub const toggle_stats = ID("toggle_stats");

pub const time_speed_up = ID("time_speed_up");
pub const time_speed_down = ID("time_speed_down");
pub const time_speed_normal = ID("time_speed_normal");

pub fn createDefaultTargetDefaults(allocator: std.mem.Allocator) input.TargetMap {
    const input_target_defaults = blk: {
        var itm = input.TargetMap.init(allocator);
        itm.ensureUnusedCapacity(64) catch unreachable;
        itm.putAssumeCapacity(toggle_player_control, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(toggle_imgui, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_left, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_right, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_forward, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_backward, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_up, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_down, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_slow, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(move_fast, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(interact, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(wielded_use_primary, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(wielded_use_secondary, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(help, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(credits, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(cursor_pos, input.TargetValue{ .vector2 = .{ 0, 0 } });
        itm.putAssumeCapacity(cursor_movement, input.TargetValue{ .vector2 = .{ 0, 0 } });
        itm.putAssumeCapacity(cursor_movement_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(cursor_movement_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(gamepad_look_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(gamepad_look_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(gamepad_move_x, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(gamepad_move_y, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(look_yaw, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(look_pitch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(camera_switch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(exit, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(reload_shaders, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(toggle_vsync, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(toggle_terrain_shadows, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(toggle_stats, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(time_speed_up, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(time_speed_down, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(time_speed_normal, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(journey, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(rest, input.TargetValue{ .number = 0 });
        break :blk itm;
    };

    return input_target_defaults;
}

pub fn createKeyMap(allocator: std.mem.Allocator) input.KeyMap {
    _ = allocator;
    const keymap = blk: {
        //
        // DEBUG
        //
        var debug_keyboard_map = input.DeviceKeyMap{
            .device_type = .keyboard,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        debug_keyboard_map.bindings.ensureTotalCapacity(8) catch unreachable;
        debug_keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = toggle_imgui, .source = input.BindingSource{ .keyboard_key = .F2 } });
        debug_keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = toggle_player_control, .source = input.BindingSource{ .keyboard_key = .F8 } });

        //
        // KEYBOARD
        //
        var keyboard_map = input.DeviceKeyMap{
            .device_type = .keyboard,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        keyboard_map.bindings.ensureTotalCapacity(32) catch unreachable;
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_left, .source = input.BindingSource{ .keyboard_key = .a } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_right, .source = input.BindingSource{ .keyboard_key = .d } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_forward, .source = input.BindingSource{ .keyboard_key = .w } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_backward, .source = input.BindingSource{ .keyboard_key = .s } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_up, .source = input.BindingSource{ .keyboard_key = .e } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_down, .source = input.BindingSource{ .keyboard_key = .q } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_slow, .source = input.BindingSource{ .keyboard_key = .left_control } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = move_fast, .source = input.BindingSource{ .keyboard_key = .left_shift } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = interact, .source = input.BindingSource{ .keyboard_key = .f } });
        // keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_primary, .source = input.BindingSource{ .keyboard_key = .g } });
        // keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_secondary, .source = input.BindingSource{ .keyboard_key = .h } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = help, .source = input.BindingSource{ .keyboard_key = .h } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = credits, .source = input.BindingSource{ .keyboard_key = .c } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = journey, .source = input.BindingSource{ .keyboard_key = .space } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = rest, .source = input.BindingSource{ .keyboard_key = .r } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = camera_switch, .source = input.BindingSource{ .keyboard_key = .tab } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = exit, .source = input.BindingSource{ .keyboard_key = .escape } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = reload_shaders, .source = input.BindingSource{ .keyboard_key = .F9 } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = toggle_vsync, .source = input.BindingSource{ .keyboard_key = .v } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = toggle_terrain_shadows, .source = input.BindingSource{ .keyboard_key = .t } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = toggle_stats, .source = input.BindingSource{ .keyboard_key = .F1 } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = time_speed_up, .source = input.BindingSource{ .keyboard_key = .page_up } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = time_speed_down, .source = input.BindingSource{ .keyboard_key = .page_down } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = time_speed_normal, .source = input.BindingSource{ .keyboard_key = .home } });

        //
        // MOUSE
        //
        var mouse_map = input.DeviceKeyMap{
            .device_type = .mouse,
            .bindings = std.ArrayList(input.Binding).init(std.heap.page_allocator),
            .processors = std.ArrayList(input.Processor).init(std.heap.page_allocator),
        };
        mouse_map.bindings.ensureTotalCapacity(8) catch unreachable;
        mouse_map.bindings.appendAssumeCapacity(.{ .target_id = cursor_pos, .source = .mouse_cursor });
        mouse_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_primary, .source = input.BindingSource{ .mouse_button = .left } });
        mouse_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_secondary, .source = input.BindingSource{ .mouse_button = .right } });
        mouse_map.processors.ensureTotalCapacity(8) catch unreachable;
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = cursor_movement,
            .class = input.ProcessorClass{ .vector2diff = input.ProcessorVector2Diff{ .source_target = cursor_pos } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = cursor_movement_x,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = cursor_movement,
                .conversion = .xy_to_x,
            } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = cursor_movement_y,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = cursor_movement,
                .conversion = .xy_to_y,
            } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = look_yaw,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = cursor_movement,
                .conversion = .xy_to_x,
            } },
        });
        mouse_map.processors.appendAssumeCapacity(.{
            .target_id = look_pitch,
            .class = input.ProcessorClass{ .axis_conversion = input.ProcessorAxisConversion{
                .source_target = cursor_movement,
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
        gamepad_map.bindings.ensureTotalCapacity(16) catch unreachable;
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_look_x, .source = input.BindingSource{ .gamepad_axis = .right_x } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_look_y, .source = input.BindingSource{ .gamepad_axis = .right_y } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_move_x, .source = input.BindingSource{ .gamepad_axis = .left_x } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_move_y, .source = input.BindingSource{ .gamepad_axis = .left_y } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_primary, .source = input.BindingSource{ .gamepad_button = .right_bumper } });
        // gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = move_slow, .source = input.BindingSource{ .gamepad_button = .left_bumper } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = move_fast, .source = input.BindingSource{ .gamepad_button = .left_bumper } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = journey, .source = input.BindingSource{ .gamepad_button = .a } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = rest, .source = input.BindingSource{ .gamepad_button = .y } });
        gamepad_map.processors.ensureTotalCapacity(16) catch unreachable;
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = gamepad_look_x,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = gamepad_look_x, .zone = 0.2 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = gamepad_look_y,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = gamepad_look_y, .zone = 0.2 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = gamepad_move_x,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = gamepad_move_x, .zone = 0.2 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = gamepad_move_y,
            .always_use_result = true,
            .class = input.ProcessorClass{ .deadzone = input.ProcessorDeadzone{ .source_target = gamepad_move_y, .zone = 0.2 } },
        });

        // Sensitivity
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = look_yaw,
            .class = input.ProcessorClass{ .scalar = input.ProcessorScalar{ .source_target = gamepad_look_x, .multiplier = 10 } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = look_pitch,
            .class = input.ProcessorClass{ .scalar = input.ProcessorScalar{ .source_target = gamepad_look_y, .multiplier = 10 } },
        });

        // Movement axis to left/right forward/backward
        // TODO: better to store movement as vector
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = move_left,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = gamepad_move_x, .is_positive = false } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = move_right,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = gamepad_move_x, .is_positive = true } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = move_forward,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = gamepad_move_y, .is_positive = false } },
        });
        gamepad_map.processors.appendAssumeCapacity(.{
            .target_id = move_backward,
            .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisSplit{ .source_target = gamepad_move_y, .is_positive = true } },
        });

        // Trigger axis
        // gamepad_map.processors.appendAssumeCapacity(.{
        //     .target_id = wielded_use_primary,
        //     .class = input.ProcessorClass{ .axis_split = input.ProcessorAxisToBool{ .source_target = wielded_use_primary } },
        // });

        var layer_debug = input.KeyMapLayer{
            .id = ID("debug"),
            .active = true,
            .device_maps = std.ArrayList(input.DeviceKeyMap).init(std.heap.page_allocator),
        };
        layer_debug.device_maps.append(debug_keyboard_map) catch unreachable;

        var layer_on_foot = input.KeyMapLayer{
            .id = ID("on_foot"),
            .active = true,
            .device_maps = std.ArrayList(input.DeviceKeyMap).init(std.heap.page_allocator),
        };
        layer_on_foot.device_maps.append(keyboard_map) catch unreachable;
        layer_on_foot.device_maps.append(mouse_map) catch unreachable;
        layer_on_foot.device_maps.append(gamepad_map) catch unreachable;

        var map = input.KeyMap{
            .layer_stack = std.ArrayList(input.KeyMapLayer).init(std.heap.page_allocator),
        };
        map.layer_stack.append(layer_debug) catch unreachable;
        map.layer_stack.append(layer_on_foot) catch unreachable;
        break :blk map;
    };

    return keymap;
}
