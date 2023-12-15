const std = @import("std");
const ecs = @import("zflecs");
const zm = @import("zmath");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const context = @import("../core/context.zig");
const renderer = @import("../renderer/tides_renderer.zig");

pub const SystemState = struct {
    flecs_sys: ecs.entity_t,
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    comp_query_interactor: ecsu.Query,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    const allocator = ctx.allocator;

    var query_builder_interactor = ecsu.QueryBuilder.init(ctx.ecsu_world);
    _ = query_builder_interactor
        .with(renderer.Renderable)
        .with(fd.Dynamic)
        .with(fd.Transform);
    const comp_query_interactor = query_builder_interactor.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = ctx.ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PostUpdate, fd.NOCOMP, postUpdate, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .ecsu_world = ctx.ecsu_world,
        .comp_query_interactor = comp_query_interactor,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_interactor.deinit();
    system.allocator.destroy(system);
}

fn postUpdate(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    var entity_iter = system.comp_query_interactor.iterator(struct {
        renderable: *renderer.Renderable,
        dynamic: *fd.Dynamic,
        transform: *fd.Transform,
    });

    while (entity_iter.next()) |comps| {
        _ = comps.transform;
        var renderable_comp = comps.renderable;

        // @memcpy(&renderable_comp.transform, transform_comp.matrix[0..]);
        renderer.updateRenderable(renderable_comp.*);
    }
}
