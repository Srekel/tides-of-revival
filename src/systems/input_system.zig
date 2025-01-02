const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const input = @import("../input.zig");
const ztracy = @import("ztracy");

const Context = struct {
    allocator: std.mem.Allocator,
    input_frame_data: *input.FrameData,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, ecsu_world: ecsu.World, input_frame_data: *input.FrameData) ecs.entity_t {
    const ctx = allocator.create(Context) catch unreachable;
    ctx.* = .{
        .allocator = allocator,
        .input_frame_data = input_frame_data,
    };

    var system_desc = ecs.system_desc_t{};
    system_desc.callback = inputSystem;
    system_desc.ctx = ctx;
    return ecs.SYSTEM(ecsu_world.world, name.toCString(), ecs.OnUpdate, &system_desc);
}

fn inputSystem(it: *ecs.iter_t) callconv(.C) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Input System: Update", 0x00_ff_00_ff);
    defer trazy_zone.End();
    // defer ecs.iter_fini(it); // needed?

    const ctx: *Context = @alignCast(@ptrCast(it.ctx.?));
    input.doTheThing(ctx.allocator, ctx.input_frame_data);
}
