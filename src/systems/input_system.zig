const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const input = @import("../input.zig");
const ztracy = @import("ztracy");
const context = @import("../core/context.zig");

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    arena_frame: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    heap_allocator: std.mem.Allocator,
    arena_frame: std.mem.Allocator,
    input_frame_data: *input.FrameData,
};

pub fn create(name: IdLocal, create_ctx: SystemCreateCtx) ecs.entity_t {
    const ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    ctx.* = SystemUpdateContext.view(create_ctx);

    var system_desc = ecs.system_desc_t{};
    system_desc.callback = inputSystem;
    system_desc.ctx = ctx;
    return ecs.SYSTEM(
        create_ctx.ecsu_world.world,
        name.toCString(),
        ecs.OnUpdate,
        &system_desc,
    );
}

fn inputSystem(it: *ecs.iter_t) callconv(.C) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Input System: Update", 0x00_ff_00_ff);
    defer trazy_zone.End();

    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    input.doTheThing(ctx.arena_frame, ctx.input_frame_data);
}
