const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const zm = @import("zmath");
const zbt = @import("zbullet");

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    sys: flecs.EntityId,

    comp_query_body: flecs.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, flecs_world: *flecs.World) !*SystemState {
    var query_builder_body = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_body.with(fd.PhysicsBody)
        .with(fd.Transform);
    const comp_query_body = query_builder_body.buildQuery();

    zbt.init(allocator);
    const physics_world = zbt.initWorld();
    physics_world.setGravity(&.{ 0.0, -10.0, 0.0 });

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .sys = sys,
        .comp_query_body = comp_query_body,
    };

    flecs_world.observer(ObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    {
        // HACK
        var i = state.physics_world.getNumBodies() - 1;
        while (i >= 0) : (i -= 1) {
            const body = state.physics_world.getBody(i);
            state.physics_world.removeBody(body);
            body.deinit();
        }
    }

    state.comp_query_body.deinit();
    state.physics_world.deinit();
    zbt.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state.physics_world.stepSimulation(iter.iter.delta_time, .{});
    updateBodies(state);
}

fn updateBodies(state: *SystemState) void {
    var entity_iter = state.comp_query_body.iterator(struct {
        PhysicsBody: *fd.PhysicsBody,
        transform: *fd.Transform,
    });

    while (entity_iter.next()) |comps| {
        var body_comp = comps.PhysicsBody;
        var body = body_comp.body;
        body.getGraphicsWorldTransform(&comps.transform.matrix);
    }
}

const ObserverCallback = struct {
    body: *const fd.CIPhysicsBody,

    pub const name = "CIPhysicsBody";
    pub const run = onSetCIPhysicsBody;
};

fn onSetCIPhysicsBody(it: *flecs.Iterator(ObserverCallback)) void {
    var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));
    while (it.next()) |_| {
        const ci_ptr = flecs.c.ecs_field_w_size(it.iter, @sizeOf(fd.CIPhysicsBody), @intCast(i32, it.index)).?;
        var ci = @ptrCast(*fd.CIPhysicsBody, @alignCast(@alignOf(fd.CIPhysicsBody), ci_ptr));

        var transform = it.entity().getMut(fd.Transform).?;
        const shape = switch (ci.shape_type) {
            .box => zbt.initBoxShape(&.{ ci.box.size, ci.box.size, ci.box.size }).asShape(),
            .sphere => zbt.initSphereShape(ci.sphere.radius).asShape(),
        };
        const body = zbt.initBody(
            ci.mass,
            &transform.matrix,
            shape,
        );

        body.setDamping(0.1, 0.1);
        body.setRestitution(0.5);
        body.setFriction(0.2);

        state.physics_world.addBody(body);

        const ent = it.entity();
        ent.remove(fd.CIPhysicsBody);
        ent.set(fd.PhysicsBody{
            .body = body,
        });
    }
}
