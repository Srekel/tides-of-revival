const std = @import("std");
const zglfw = @import("zglfw");
const IdLocal = @import("core/core.zig").IdLocal;

pub const TargetMap = std.AutoHashMap(IdLocal, TargetValue);

pub const FrameData = struct {
    index_curr: u32 = 0,
    target_defaults: TargetMap,
    targets_double_buffer: [2]TargetMap,
    targets: *TargetMap = undefined,
    map: KeyMap,
    window: *zglfw.Window,

    pub fn create(allocator: std.mem.Allocator, keymap: KeyMap, target_defaults: TargetMap, window: *zglfw.Window) FrameData {
        var res: FrameData = .{
            .target_defaults = target_defaults,
            .targets_double_buffer = .{ TargetMap.init(allocator), TargetMap.init(allocator) },
            .map = keymap,
            .window = window,
        };
        res.targets = &res.targets_double_buffer[0];

        res.targets_double_buffer[0].ensureUnusedCapacity(target_defaults.count()) catch unreachable;
        res.targets_double_buffer[1].ensureUnusedCapacity(target_defaults.count()) catch unreachable;
        var it = res.target_defaults.iterator();
        while (it.next()) |kv| {
            res.targets_double_buffer[0].putAssumeCapacity(kv.key_ptr.*, kv.value_ptr.*);
            res.targets_double_buffer[1].putAssumeCapacity(kv.key_ptr.*, kv.value_ptr.*);
        }
        return res;
    }

    pub fn get(self: FrameData, target_id: IdLocal) TargetValue {
        const value = self.targets.get(target_id);
        return value.?;
    }

    pub fn held(self: FrameData, target_id: IdLocal) bool {
        const value = self.targets.get(target_id);
        return value.?.isActive();
    }

    pub fn just_pressed(self: FrameData, target_id: IdLocal) bool {
        const index_curr = self.index_curr;
        const index_prev = 1 - index_curr;
        const value_curr = self.targets_double_buffer[index_curr].get(target_id).?;
        const value_prev = self.targets_double_buffer[index_prev].get(target_id).?;
        return !value_prev.isActive() and value_curr.isActive();
    }

    pub fn just_released(self: FrameData, target_id: IdLocal) bool {
        const index_curr = self.index_curr;
        const index_prev = 1 - index_curr;
        const value_curr = self.targets_double_buffer[index_curr].get(target_id).?;
        const value_prev = self.targets_double_buffer[index_prev].get(target_id).?;
        return value_prev.isActive() and !value_curr.isActive();
    }
};

pub const InputType = enum {
    number,
    vector2,
};

pub const TargetValue = union(InputType) {
    number: f32,
    vector2: [2]f32,
    fn isActive(self: TargetValue) bool {
        return switch (self) {
            .number => |value| value != 0,
            .vector2 => |value| value[0] != 0 or value[1] != 0, // TODO
        };
    }
    fn supersedes(self: TargetValue, other: TargetValue) bool {
        return switch (self) {
            .number => |value| @abs(value) > @abs(other.number),
            .vector2 => |value| @abs(value[0]) > @abs(other.vector2[0]) or @abs(value[1]) > @abs(other.vector2[1]), // TODO
        };
    }
};

pub const BindingSource = union(enum) {
    keyboard_key: zglfw.Key,
    mouse_button: zglfw.MouseButton,
    mouse_cursor: void,
    gamepad_button: zglfw.Gamepad.Button,
    gamepad_axis: zglfw.Gamepad.Axis,
    processor: void,
};

pub const Binding = struct {
    target_id: IdLocal,
    source: BindingSource,
};

pub const DeviceType = enum {
    keyboard,
    mouse,
    gamepad,
};

// fn remap4ToAxis2D(targets: TargetMap, source_targets: std.ArrayList(IdLocal)) TargetValue {
//     const value_left = targets[source_targets.items[0]] catch unreachable;
//     const value_right = targets[source_targets.items[1]] catch unreachable;
//     const value_up = targets[source_targets.items[2]] catch unreachable;
//     const value_down = targets[source_targets.items[3]] catch unreachable;
//     const value = [2]f32{
//         blk: {
//             if (value_left.number != 0) {
//                 break :blk -value_left.number;
//             }
//             if (value_right.number != 0) {
//                 break :blk value_right.number;
//             }
//             break :blk 0;
//         },
//         blk: {
//             if (value_down.number != 0) {
//                 break :blk -value_down.number;
//             }
//             if (value_up.number != 0) {
//                 break :blk value_up.number;
//             }
//             break :blk 0;
//         },
//     };
//     return .{ .vector2 = value };
// }

pub const ProcessorScalar = struct {
    source_target: IdLocal,
    multiplier: f32,

    pub fn process(self: ProcessorScalar, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        _ = targets_prev;
        var res = targets_curr.get(self.source_target).?;
        res.number *= self.multiplier;
        return res;
    }
};

pub const ProcessorDeadzone = struct {
    source_target: IdLocal,
    zone: f32,

    pub fn process(self: ProcessorDeadzone, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        _ = targets_prev;
        var res = targets_curr.get(self.source_target).?;
        if (@abs(res.number) < self.zone) {
            res.number = 0;
        } else {
            // Remap [zone..1] to [0..1]
            res.number = (res.number - self.zone) / (1.0 - self.zone);
        }
        return res;
    }
};

pub const ProcessorVector2Diff = struct {
    source_target: IdLocal,

    pub fn process(self: ProcessorVector2Diff, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        const prev = targets_prev.get(self.source_target).?;
        const curr = targets_curr.get(self.source_target).?;
        const movement: [2]f32 = .{ curr.vector2[0] - prev.vector2[0], curr.vector2[1] - prev.vector2[1] };
        return TargetValue{ .vector2 = .{ movement[0], movement[1] } };
    }
};

pub const ProcessorAxisConversion = struct {
    source_target: IdLocal,
    conversion: enum {
        xy_to_x,
        xy_to_y,
    },

    pub fn process(self: ProcessorAxisConversion, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        _ = targets_prev;
        const axis_value = targets_curr.get(self.source_target).?;
        const res = switch (self.conversion) {
            .xy_to_x => TargetValue{ .number = axis_value.vector2[0] },
            .xy_to_y => TargetValue{ .number = axis_value.vector2[1] },
        };
        return res;
    }
};

pub const ProcessorAxisSplit = struct {
    source_target: IdLocal,
    is_positive: bool,

    pub fn process(self: ProcessorAxisSplit, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        _ = targets_prev;
        var res = targets_curr.get(self.source_target).?;
        if (self.is_positive) {
            if (res.number < 0) {
                res.number = 0;
            }
        } else {
            if (res.number > 0) {
                res.number = 0;
            } else {
                res.number = -res.number;
            }
        }
        return res;
    }
};

pub const ProcessorAxisToBool = struct {
    source_target: IdLocal,

    pub fn process(self: ProcessorAxisToBool, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        _ = targets_prev;
        const res = targets_curr.get(self.source_target).?;
        if (res.number > 0.1) {
            return TargetValue{ .number = 1 };
        }
        return TargetValue{ .number = 0 };
    }
};

pub const ProcessorClass = union(enum) {
    // axis2d:  remap4ToAxis2D,
    scalar: ProcessorScalar,
    deadzone: ProcessorDeadzone,
    vector2diff: ProcessorVector2Diff,
    axis_conversion: ProcessorAxisConversion,
    axis_split: ProcessorAxisSplit,
    axis_to_bool: ProcessorAxisToBool,
};

pub const Processor = struct {
    target_id: IdLocal,
    class: ProcessorClass,
    always_use_result: bool = false,
    fn process(self: Processor, targets_curr: TargetMap, targets_prev: TargetMap) TargetValue {
        switch (self.class) {
            inline else => |case| return case.process(targets_curr, targets_prev),
        }
    }
};

pub const DeviceKeyMap = struct {
    // active_device_index: ?u32 = null,
    device_type: DeviceType,
    bindings: std.ArrayList(Binding),
    processors: std.ArrayList(Processor),
};

pub const KeyMapLayer = struct {
    id: IdLocal,
    active: bool,
    device_maps: std.ArrayList(DeviceKeyMap),
};

pub const KeyMap = struct {
    layer_stack: std.ArrayList(KeyMapLayer),
};

pub fn doTheThing(allocator: std.mem.Allocator, input_frame_data: *FrameData) void {
    var used_inputs = std.AutoHashMap(BindingSource, bool).init(allocator);
    defer used_inputs.clearAndFree();

    const targets_prev = &input_frame_data.targets_double_buffer[input_frame_data.index_curr];
    input_frame_data.index_curr = 1 - input_frame_data.index_curr;
    var targets = &input_frame_data.targets_double_buffer[input_frame_data.index_curr];

    var it = input_frame_data.target_defaults.iterator();
    while (it.next()) |kv| {
        targets.putAssumeCapacity(kv.key_ptr.*, kv.value_ptr.*);
    }

    input_frame_data.targets = targets;
    const map = input_frame_data.map;
    var window = input_frame_data.window;
    for (map.layer_stack.items) |layer| {
        if (!layer.active) {
            continue;
        }
        for (layer.device_maps.items) |device_map| {
            for (device_map.bindings.items) |binding| {
                if (used_inputs.contains(binding.source)) {
                    continue;
                }

                // std.debug.print("prevalue {}\n", .{binding.source});
                const value =
                    switch (binding.source) {
                    .keyboard_key => |key| blk: {
                        if (window.getKey(key) == .press) {
                            // std.debug.print("press {}\n", .{key});
                            break :blk TargetValue{ .number = 1 };
                        }

                        // std.debug.print("break {}\n", .{key});
                        // break; // footgun
                        break :blk TargetValue{ .number = 0 };
                    },
                    .mouse_button => |button| blk: {
                        const button_action = window.getMouseButton(button);
                        break :blk TargetValue{ .number = if (button_action == .press) 1 else 0 };
                    },
                    .mouse_cursor => blk: {
                        const cursor_pos = window.getCursorPos();
                        const cursor_value = TargetValue{ .vector2 = .{
                            @as(f32, @floatCast(cursor_pos[0])),
                            @as(f32, @floatCast(cursor_pos[1])),
                        } };
                        break :blk cursor_value;
                    },
                    .gamepad_axis => |axis| blk: {
                        var joystick_id: u32 = 0;
                        while (joystick_id < zglfw.Joystick.maximum_supported) : (joystick_id += 1) {
                            if (zglfw.Joystick.get(@as(zglfw.Joystick.Id, @intCast(joystick_id)))) |joystick| {
                                if (joystick.asGamepad()) |gamepad| {
                                    const gamepad_state = gamepad.getState();
                                    const value = gamepad_state.axes[@intFromEnum(axis)];
                                    break :blk TargetValue{ .number = value };
                                }
                            }
                        }

                        break :blk TargetValue{ .number = 0 };
                    },
                    .gamepad_button => |button| blk: {
                        var joystick_id: u32 = 0;
                        while (joystick_id < zglfw.Joystick.maximum_supported) : (joystick_id += 1) {
                            if (zglfw.Joystick.get(@as(zglfw.Joystick.Id, @intCast(joystick_id)))) |joystick| {
                                if (joystick.asGamepad()) |gamepad| {
                                    const gamepad_state = gamepad.getState();
                                    const action = gamepad_state.buttons[@intFromEnum(button)];
                                    const value: f32 = if (action == .release) 0 else 1;
                                    break :blk TargetValue{ .number = value };
                                }
                            }
                        }

                        break :blk TargetValue{ .number = 0 };
                    },
                    .processor => TargetValue{ .number = 0 },
                };

                if (!value.isActive()) {
                    continue;
                }

                // std.debug.print("target1: {s} value {}\n", .{ binding.target_id.toString(), value });
                used_inputs.put(binding.source, true) catch unreachable;

                const prev_value = targets.get(binding.target_id);
                if (prev_value) |pv| {
                    if (value.supersedes(pv)) {
                        targets.put(binding.target_id, value) catch unreachable;
                    }
                } else {
                    // std.debug.print("target2: {s} value {}\n", .{ binding.target_id.toString(), value });
                    targets.put(binding.target_id, value) catch unreachable;
                }
            }

            for (device_map.processors.items) |processor| {
                const value = processor.process(targets.*, targets_prev.*);
                const prev_value = targets.get(processor.target_id);
                if (prev_value) |pv| {
                    if (processor.always_use_result or value.supersedes(pv)) {
                        targets.put(processor.target_id, value) catch unreachable;
                    }
                } else {
                    targets.put(processor.target_id, value) catch unreachable;
                }
            }
        }
    }
}

// const inputs = [_]InputResult{
//     .{
//         .id = IdLocal.init("move"),
//         .output_type = .vector2,
//     },
//     // move_right,
//     // move_forward,
//     // move_backward,
// };

// const input_map = [@typeInfo(Inputs).@"enum".fields.len]zglfw.Key{
//     .{.id = IdLocal{"move"}, output=vector2, },
//     .left_shift,
//     .left_shift,
//     .left_shift,
// };

test "test" {
    const allocator = std.testing.allocator;
    var keyboard_map = DeviceKeyMap{
        .device_type = .keyboard,
        .bindings = std.ArrayList(Binding).init(allocator),
    };
    keyboard_map.bindings.append(.{
        .target_id = IdLocal.init("move_left"),
        .source = BindingSource{ .keyboard_key = .left },
    });
    keyboard_map.bindings.append(.{
        .target_id = IdLocal.init("move_right"),
        .source = BindingSource{ .keyboard_key = .right },
    });

    var layer_on_foot = KeyMapLayer{
        .id = IdLocal.init("on_foot"),
        .active = true,
        .device_maps = std.ArrayList(DeviceKeyMap).init(allocator),
    };
    layer_on_foot.device_maps.append(keyboard_map);

    var map = KeyMap{
        .layer_stack = std.ArrayList(KeyMapLayer).init(allocator),
    };
    map.layer_stack.append(layer_on_foot);

    return map;
}
