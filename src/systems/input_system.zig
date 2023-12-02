const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const input = @import("../input.zig");

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    flecs_sys: ecs.entity_t,
    query: ecsu.Query,
    input_frame_data: *input.FrameData,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, ecsu_world: ecsu.World, input_frame_data: *input.FrameData) !*SystemState {
    var query_builder = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder
        .with(fd.Input);
    var query = query_builder.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .flecs_sys = flecs_sys,
        .query = query,
        .input_frame_data = input_frame_data,
    };

    // ecsu_world.observer(ObserverCallback, ecs.OnSet, system);

    // initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.query.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    // const dt4 = zm.f32x4s(iter.iter.delta_time);
    // _ = system;
    input.doTheThing(system.allocator, system.input_frame_data);

    // var entity_iter = system.query.iterator(struct {
    //     fsm: *fd.FSM,
    // });

    // while (entity_iter.next()) |comps| {
    //     _ = comps;
    // }

    // const NextState = struct {
    //     entity: flecs.Entity,
    //     next_state: *fsm.State,
    // };

    // for (system.instances.items) |*instance| {
    //     for (instance.curr_states.items) |fsm_state| {
    //         const ctx = fsm.StateFuncContext{
    //             .state = fsm_state,
    //             .blob_array = instance.blob_array,
    //             .allocator = system.allocator,
    //             // .entity = instance.entities.items[i],
    //             // .data = instance.blob_array.getBlob(i),
    //             .transition_events = .{},
    //             .ecsu_world = system.ecsu_world,
    //             .dt = dt4,
    //         };
    //         fsm_state.update(ctx);
    //     }
    // }
}
