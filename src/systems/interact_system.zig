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

const SystemState = struct {
    flecs_sys: flecs.EntityId,
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,

    comp_query_loader: flecs.Query,
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const flecs_world = ctx.get(config.flecs_world.hash, flecs.World);
    var query_builder_loader = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_loader.with(fd.Interactor)
        .with(fd.Transform);
    const comp_query_loader = query_builder_loader.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .flecs_world = flecs_world,
        .comp_query_loader = comp_query_loader,
    };

    // flecs_world.observer(ObserverCallback, .on_set, system);

    // initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_loader.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var system = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    updateInteractors(system);
    // updatePatches(system);
}

fn updateInteractors(system: *SystemState) void {
    var entity_iter = system.comp_query_loader.iterator(struct {
        Interactor: *fd.Interactor,
        transform: *fd.Transform,
    });
    _ = entity_iter;

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    _ = arena;

    // while (entity_iter.next()) |comps| {
    //     var loader_comp = comps.Interactor;
    //     if (!loader_comp.props) {
    //         continue;
    //     }
    // }
}
