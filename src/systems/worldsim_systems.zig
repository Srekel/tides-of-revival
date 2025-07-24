const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
// const zgpu = @import("zgpu");
// const zglfw = @import("zglfw");
// const zm = @import("zmath");
// const zgui = @import("zgui");
// const ztracy = @import("ztracy");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
// const IdLocal = @import("../core/core.zig").IdLocal;
// const ID = @import("../core/core.zig").ID;
const input = @import("../input.zig");
// const config = @import("../config/config.zig");
// const renderer = @import("../renderer/renderer.zig");
const context = @import("../core/context.zig");

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    state: struct {
        //     switch_pressed: bool = false,
        //     active_index: u32 = 1,
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{};

    _ = ecsu.registerSystem(create_ctx.ecsu_world.world, "settlementGrowth", settlementGrowth, update_ctx, &[_]ecs.term_t{
        .{ .id = ecs.id(fd.Script), .inout = .InOut },
        .{ .id = ecs.id(fd.Settlement), .inout = .In },
        .{ .id = ecs.id(fd.Position), .inout = .In },
    });
}

fn settlementGrowth(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const scripts = ecs.field(it, fd.Script, 0).?;
    const settlements = ecs.field(it, fd.Settlement, 1).?;
    const positions = ecs.field(it, fd.Position, 2).?;

    for (scripts, settlements, positions) |script, *settlement, position| {
        _ = position; //
        settlement.safety += 1;
        if (settlement.safety > 500) {
            settlement.level += 1;
            settlement.safety = 0;

            const vars = ecs.script_vars_init(ctx.ecsu_world.world);
            defer ecs.script_vars_fini(vars);
            const var_settlement_level = ecs.script_vars_define_id(vars, "settlement_level", ecs.FLECS_IDecs_i32_tID_).?;
            @as(*i32, @alignCast(@ptrCast(var_settlement_level.value.ptr.?))).* = settlement.level;
            const desc: ecs.script_eval_desc_t = .{ .vars = vars };

            const res = ecs.script_eval(script.script, &desc);
            std.debug.assert(res == 0);
        }
    }
}
