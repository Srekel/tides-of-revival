const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const zm = @import("zmath");
const fd = @import("../flecs_data.zig");
const fr = @import("../flecs_relation.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");
const config = @import("../config.zig");
const input = @import("../input.zig");

const SystemState = struct {
    flecs_sys: flecs.EntityId,
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    frame_data: *input.FrameData,

    comp_query_interactor: flecs.Query,
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const flecs_world = ctx.get(config.flecs_world.hash, flecs.World);
    const frame_data = ctx.get(config.input_frame_data.hash, input.FrameData);

    var query_builder_interactor = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_interactor.with(fd.Interactor)
        .with(fd.Transform);
    const comp_query_interactor = query_builder_interactor.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .flecs_world = flecs_world,
        .frame_data = frame_data,
        .comp_query_interactor = comp_query_interactor,
    };

    // flecs_world.observer(ObserverCallback, .on_set, system);

    // initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_interactor.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var system = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    updateInteractors(system);
    // updatePatches(system);
}

fn updateInteractors(system: *SystemState) void {
    var entity_iter = system.comp_query_interactor.iterator(struct {
        Interactor: *fd.Interactor,
        transform: *fd.Transform,
    });

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    _ = arena;

    const wielded_use_primary_held = system.frame_data.held(config.input_wielded_use_primary);
    while (entity_iter.next()) |comps| {
        var interactor_comp = comps.Interactor;

        const item_ent = flecs.Entity.init(system.flecs_world.world, interactor_comp.wielded_item_ent_id);
        var item_rotation = item_ent.getMut(fd.EulerRotation).?;
        const target_roll: f32 = if (wielded_use_primary_held) 1 else 0;
        item_rotation.pitch = zm.lerpV(item_rotation.roll, target_roll, 0.1);
        if (wielded_use_primary_held) {}
    }
}
