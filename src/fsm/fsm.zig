const std = @import("std");
const flecs = @import("flecs");
const IdLocal = @import("../variant.zig").IdLocal;
const BlobArray = @import("../blob_array.zig").BlobArray;
const zm = @import("zmath");
const input = @import("../input.zig");

pub const TriggerEvent = struct {
    id: IdLocal,
    value: f32,
};

pub const Trigger = struct {
    event: TriggerEvent,
    comparison: enum { less_than, equal_exact, greater_than },

    pub fn pass(self: Trigger, value: f32) bool {
        return switch (self.comparison) {
            .less_than => value < self.event.value,
            .equal_exact => value == self.event.value,
            .greater_than => value > self.event.value,
        };
    }
};

pub const Transition = struct {
    triggers: std.ArrayList(Trigger),
    enabled: bool,
    next_state: *State,

    pub fn isValid(self: Transition, trigger_value: f32) bool {
        if (self.enabled) {
            return false;
        }

        for (self.triggers) |*trigger| {
            if (trigger.pass(trigger_value)) {
                return true;
            }
        }

        return false;
    }
};

pub const State = struct {
    const Self = @This();
    // ptr: *anyopaque,
    name: IdLocal,
    size: u64,
    self: []u8,
    transitions: std.ArrayList(Transition),
    enter: *const StateFunc,
    exit: *const StateFunc,
    update: *const StateFunc,

    // pub fn initImpl(implPtr: anytype) Self {
    //     const ImplPtrType = @TypeOf(implPtr);
    //     const ptr_info = @typeInfo(ImplPtrType);
    //     const alignment = ptr_info.Pointer.alignment;
    //     const gen = struct {
    //         pub fn enterImpl(pointer: *anyopaque) ?u32 {
    //             const self = @ptrCast(ImplPtrType, @alignCast(alignment, pointer));
    //             return @call(.{ .modifier = .always_inline }, ptr_info.Pointer.child.next, .{self});
    //         }
    //         pub fn exitImpl(pointer: *anyopaque) ?u32 {
    //             const self = @ptrCast(ImplPtrType, @alignCast(alignment, pointer));
    //             return @call(.{ .modifier = .always_inline }, ptr_info.Pointer.child.next, .{self});
    //         }
    //         pub fn updateImpl(pointer: *anyopaque) ?u32 {
    //             const self = @ptrCast(ImplPtrType, @alignCast(alignment, pointer));
    //             return @call(.{ .modifier = .always_inline }, ptr_info.Pointer.child.next, .{self});
    //         }
    //     };

    //     return .{
    //         .ptr = State.ptr,
    //         .enterFn = gen.enterImpl,
    //         .exitFn = gen.exitImpl,
    //         .updateFn = gen.updateImpl,
    //     };
    // }
};

pub const StateCreateContext = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
};

pub const StateFuncContext = struct {
    state: *const State,
    transition_events: std.BoundedArray(Trigger, 32),
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    blob_array: BlobArray(16),
    frame_data: *const input.FrameData,
    dt: zm.F32x4,
};

pub const StateFunc = fn (ctx: StateFuncContext) void;

pub const StateMachine = struct {
    name: IdLocal,
    initial_state: *State,
    states: std.ArrayList(State),
    max_state_size: u64,

    pub fn create(name: []const u8, states: std.ArrayList(State), initial_state_name: []const u8) StateMachine {
        return .{
            .name = IdLocal.init(name),
            .states = states,
            .initial_state = blk: {
                for (states.items) |*state| {
                    if (state.name.eqlStr(initial_state_name)) {
                        break :blk state;
                    }
                }
                unreachable;
            },
            .max_state_size = blk: {
                var max_size: u64 = 16;
                for (states.items) |*state| {
                    if (state.size > max_size) {
                        max_size = state.size;
                    }
                }
                break :blk max_size;
            },
        };
    }

    // pub fn update(self: *StateMachine, entity: flecs.Entity, flecs_world: flecs.World) void {
    //     var ctx: StateFuncContext = .{
    //         .entity = entity,
    //         .transition_events = .{},
    //         .flecs_world = flecs_world,
    //     };
    //     self.current_state.update(ctx);

    //     if (ctx.transition_events.len == 0) {
    //         return;
    //     }

    //     for (self.current_state.transitions) |transition| {
    //         if (transition.isValid(ctx.transition_events)) {
    //             self.current_state.exit(ctx, transition.next_state);
    //             self.current_state = transition.next_state;
    //             self.current_state.enter(ctx, transition.next_state);
    //         }
    //     }
    // }
};
