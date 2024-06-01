const std = @import("std");
const input = @import("../input.zig");
const ID = @import("../core/core.zig").ID;

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

pub const draw_bounding_spheres = ID("draw_bounding_spheres");
pub const camera_switch = ID("camera_switch");
pub const camera_freeze_rendering = ID("camera_freeze_rendering");
pub const exit = ID("exit");

pub const view_mode_lit = ID("view_mode_lit");
pub const view_mode_albedo = ID("view_mode_albedo");
pub const view_mode_world_normal = ID("view_mode_world_normal");
pub const view_mode_metallic = ID("view_mode_metallic");
pub const view_mode_roughness = ID("view_mode_roughness");
pub const view_mode_ao = ID("view_mode_ao");
pub const view_mode_depth = ID("view_mode_depth");

pub const reload_shaders = ID("reload_shaders");
pub const toggle_vsync = ID("toggle_vsync");

pub fn createDefaultTargetDefaults(allocator: std.mem.Allocator) input.TargetMap {
    const input_target_defaults = blk: {
        var itm = input.TargetMap.init(allocator);
        itm.ensureUnusedCapacity(64) catch unreachable;
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
        itm.putAssumeCapacity(draw_bounding_spheres, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(camera_switch, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(camera_freeze_rendering, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(exit, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_lit, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_albedo, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_world_normal, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_metallic, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_roughness, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_ao, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(view_mode_depth, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(reload_shaders, input.TargetValue{ .number = 0 });
        itm.putAssumeCapacity(toggle_vsync, input.TargetValue{ .number = 0 });
        break :blk itm;
    };

    return input_target_defaults;
}

pub fn createKeyMap(allocator: std.mem.Allocator) input.KeyMap {
    _ = allocator;
    const keymap = blk: {
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
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_primary, .source = input.BindingSource{ .keyboard_key = .g } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_secondary, .source = input.BindingSource{ .keyboard_key = .h } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = draw_bounding_spheres, .source = input.BindingSource{ .keyboard_key = .b } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = camera_switch, .source = input.BindingSource{ .keyboard_key = .tab } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = camera_freeze_rendering, .source = input.BindingSource{ .keyboard_key = .x } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = exit, .source = input.BindingSource{ .keyboard_key = .escape } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_lit, .source = input.BindingSource{ .keyboard_key = .zero } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_albedo, .source = input.BindingSource{ .keyboard_key = .one } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_world_normal, .source = input.BindingSource{ .keyboard_key = .two } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_metallic, .source = input.BindingSource{ .keyboard_key = .three } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_roughness, .source = input.BindingSource{ .keyboard_key = .four } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_ao, .source = input.BindingSource{ .keyboard_key = .five } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = view_mode_depth, .source = input.BindingSource{ .keyboard_key = .six } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = reload_shaders, .source = input.BindingSource{ .keyboard_key = .r } });
        keyboard_map.bindings.appendAssumeCapacity(.{ .target_id = toggle_vsync, .source = input.BindingSource{ .keyboard_key = .v } });

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
        gamepad_map.bindings.ensureTotalCapacity(8) catch unreachable;
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_look_x, .source = input.BindingSource{ .gamepad_axis = .right_x } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_look_y, .source = input.BindingSource{ .gamepad_axis = .right_y } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_move_x, .source = input.BindingSource{ .gamepad_axis = .left_x } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = gamepad_move_y, .source = input.BindingSource{ .gamepad_axis = .left_y } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = wielded_use_primary, .source = input.BindingSource{ .gamepad_button = .right_bumper } });
        // gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = move_slow, .source = input.BindingSource{ .gamepad_button = .left_bumper } });
        gamepad_map.bindings.appendAssumeCapacity(.{ .target_id = move_fast, .source = input.BindingSource{ .gamepad_button = .left_bumper } });
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
        map.layer_stack.append(layer_on_foot) catch unreachable;
        break :blk map;
    };

    return keymap;
}
