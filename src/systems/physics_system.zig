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

    // bodies: std.ArrayList(zbt.Body),
    comp_query: flecs.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, flecs_world: *flecs.World) !*SystemState {
    var query_builder = flecs.QueryBuilder.init(flecs_world.*)
        .with(fd.PhysicsBody)
        .with(fd.Transform);
    var comp_query = query_builder.buildQuery();

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
        // .bodies = std.ArrayList(zbt.Body).init(),
        .comp_query = comp_query,
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

    state.comp_query.deinit();
    state.physics_world.deinit();
    zbt.deinit();
    state.allocator.destroy(state);
}

var lol: i32 = 0;
fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state.physics_world.stepSimulation(iter.iter.delta_time, .{});
    // _ = state.physics_world.stepSimulation(0.0166, .{});

    var entity_iter = state.comp_query.iterator(struct {
        PhysicsBody: *fd.PhysicsBody,
        transform: *fd.Transform,
    });

    lol += 1;
    while (entity_iter.next()) |comps| {
        var body_comp = comps.PhysicsBody;
        var body = body_comp.body;
        _ = body;
        // body = body;
        // var transform: [12]f32 = undefined;
        body.getGraphicsWorldTransform(&comps.transform.matrix);
        // std.debug.print("{}\t{d}\n", .{ lol, comps.transform.matrix[10] });

        // var impulse = [3]f32{ 0, 0, 1 };
        // body.applyCentralImpulse(&impulse);
        // var ztransform = zm.loadMat43(transform[0..]);
        // comps.pos.x = transform[9];
        // comps.pos.y = transform[10];
        // comps.pos.z = transform[11];
        // var transform: [12]f32 = undefined;
        // break :blk zm.loadMat43(transform[0..]);
        // };
    }
}

const ObserverCallback = struct {
    // pos: *const fd.Position,
    body: *const fd.CIPhysicsBody,

    pub const name = "CIPhysicsBody";
    pub const run = onSetCIPhysicsBody;
};

fn onSetCIPhysicsBody(it: *flecs.Iterator(ObserverCallback)) void {
    var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));
    while (it.next()) |_| {
        const ci_ptr = flecs.c.ecs_term_w_size(it.iter, @sizeOf(fd.CIPhysicsBody), @intCast(i32, it.index)).?;
        var ci = @ptrCast(*fd.CIPhysicsBody, @alignCast(@alignOf(fd.CIPhysicsBody), ci_ptr));

        var transform = it.entity().getMut(fd.Transform).?;
        // const transform = [_]f32{
        //     1.0, 0.0, 0.0, // orientation
        //     0.0, 1.0, 0.0,
        //     0.0, 0.0, 1.0,
        //     pos.x, pos.y, pos.z, // translation
        // };

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
