const std = @import("std");
const zglfw = @import("zglfw");
const IdLocal = @import("variant.zig").IdLocal;

const TargetMap = std.AutoHashMap(IdLocal, TargetValue);

pub const FrameData = struct {
    targets: TargetMap,
    map: KeyMap,
    window: zglfw.Window,

    pub fn create(allocator: std.mem.Allocator, keymap: KeyMap, window: zglfw.Window) FrameData {
        return .{
            .targets = TargetMap.init(allocator),
            .map = keymap,
            .window = window,
        };
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
            .vector2 => |value| value[0] != 0, // TODO
        };
    }
    fn supersedes(self: TargetValue, other: TargetValue) bool {
        return switch (self) {
            .number => |value| value > other.number,
            .vector2 => |value| value[0] != 0, // TODO
        };
    }
};

// pub const TargetValue = struct {
//     value: TargetValue,
//     fn isActive(self: TargetValue) bool {
//         switch (self.value) {
//             .number => |value| value != 0,
//             .vector2 => |value| value[0] != 0, // TODO
//         }
//     }
// };

pub const KeyBindingSource = union(enum) {
    keyboard: zglfw.Key,
    mouse_button: zglfw.MouseButton,
};

pub const KeyBinding = struct {
    target_id: IdLocal,
    source: KeyBindingSource,
};

pub const DeviceType = enum {
    keyboard,
    mouse,
    gamepad,
};

fn remap4ToAxis2D(targets: TargetMap, source_targets: std.ArrayList(IdLocal)) TargetValue {
    const value_left = targets[source_targets.items[0]] catch unreachable;
    const value_right = targets[source_targets.items[1]] catch unreachable;
    const value_up = targets[source_targets.items[2]] catch unreachable;
    const value_down = targets[source_targets.items[3]] catch unreachable;
    const value = [2]f32{
        blk: {
            if (value_left.number != 0) {
                break :blk -value_left.number;
            }
            if (value_right.number != 0) {
                break :blk value_right.number;
            }
            break :blk 0;
        },
        blk: {
            if (value_down.number != 0) {
                break :blk -value_down.number;
            }
            if (value_up.number != 0) {
                break :blk value_up.number;
            }
            break :blk 0;
        },
    };
    return .{ .vector2 = value };
}

// const ProcessorFunc = struct {
//     remap_func: *const fn (targets: TargetMap, source_targets: std.ArrayList(IdLocal)) TargetValue,

//     // union(enum) {
//     //     axis2d: remap4ToAxis2D,
//     // },
// };

// const Processor = struct {
//     target_id: IdLocal,
//     in_values: std.ArrayList(IdLocal),
//     process_func:

//     union(enum) {
//         axis2d:  remap4ToAxis2D,
//     },
//     *const fn (targets: TargetMap, source_targets: std.ArrayList(IdLocal)) TargetValue,
// };

pub const DeviceKeyMap = struct {
    // active_device_index: ?u32 = null,
    device_type: DeviceType,
    bindings: std.ArrayList(KeyBinding),
    // processors: std.ArrayList(Remapping),
};

pub const KeyMapLayer = struct {
    id: IdLocal,
    active: bool,
    device_maps: std.ArrayList(DeviceKeyMap),
};

pub const KeyMap = struct {
    stack: std.ArrayList(KeyMapLayer),
};

pub fn doTheThing(allocator: std.mem.Allocator, frame_data: *FrameData) void {
    var used_inputs = std.AutoHashMap(KeyBindingSource, bool).init(allocator);
    var targets = TargetMap.init(allocator);
    var map = frame_data.map;
    var window = frame_data.window;
    for (map.stack.items) |layer| {
        if (!layer.active) {
            continue;
        }
        for (layer.device_maps.items) |device_map| {
            for (device_map.bindings.items) |binding| {
                if (used_inputs.contains(binding.source)) {
                    continue;
                }

                std.debug.print("prevalue {}\n", .{binding.source});
                const value =
                    switch (binding.source) {
                    .keyboard => |key| blk: {
                        if (window.getKey(key) == .press) {
                            std.debug.print("press {}\n", .{key});
                            break :blk TargetValue{ .number = 1 };
                        }

                        std.debug.print("break {}\n", .{key});
                        break; // footgun
                    },
                    .mouse_button => TargetValue{ .number = 1 },
                };

                std.debug.print("value {}\n", .{value});
                // break :blk TargetValue{ .number = 0 };

                if (!value.isActive()) {
                    continue;
                }

                used_inputs.put(binding.source, true) catch unreachable;

                const prev_value = targets.get(binding.target_id);
                if (prev_value) |pv| {
                    if (value.supersedes(pv)) {
                        targets.put(binding.target_id, value) catch unreachable;
                    }
                } else {
                    targets.put(binding.target_id, value) catch unreachable;
                }
            }

            // for (device_map.remappings) |remapping| {
            //     const value = remapping.remap_func(targets, remapping.input_targets);
            //     const prev_value = targets.get(remapping.target_id);
            //     if (prev_value) |pv| {
            //         if (value.supersedes(pv)) {
            //             targets.put(remapping.target_id, value) catch unreachable;
            //         }
            //     } else {
            //         targets.put(remapping.target_id, value) catch unreachable;
            //     }
            // }
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

// const input_map = [@typeInfo(Inputs).Enum.fields.len]zglfw.Key{
//     .{.id = IdLocal{"move"}, output=vector2, },
//     .left_shift,
//     .left_shift,
//     .left_shift,
// };

test "test" {
    const allocator = std.testing.allocator;
    var keyboard_map = DeviceKeyMap{
        .device_type = .keyboard,
        .bindings = std.ArrayList(KeyBinding).init(allocator),
    };
    keyboard_map.bindings.append(.{
        .target_id = IdLocal.init("move_left"),
        .source = KeyBindingSource{ .keyboard = .left },
    });
    keyboard_map.bindings.append(.{
        .target_id = IdLocal.init("move_right"),
        .source = KeyBindingSource{ .keyboard = .right },
    });

    var layer_on_foot = KeyMapLayer{
        .id = IdLocal.init("on_foot"),
        .active = true,
        .device_maps = std.ArrayList(DeviceKeyMap).init(allocator),
    };
    layer_on_foot.device_maps.append(keyboard_map);

    var map = KeyMap{
        .stack = std.ArrayList(KeyMapLayer).init(allocator),
    };
    map.stack.append(layer_on_foot);

    return map;
}
