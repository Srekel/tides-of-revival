const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const zm = @import("zmath");
const zbt = @import("zbullet");

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const config = @import("../config.zig");

const patch_side_vertex_count = config.patch_resolution;
const vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;
const indices_per_patch: u32 = (config.patch_resolution - 1) * (config.patch_resolution - 1) * 6;

const WorldLoaderData = struct {
    ent: flecs.EntityId = 0,
    pos_old: [3]f32 = .{ -100000, 0, -100000 },
};

const Patch = struct {
    body_opt: ?zbt.Body = null,
    physics_shape_opt: ?zbt.Shape = null,
    lookup: world_patch_manager.PatchLookup,
};

const IndexType = u32;

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    sys: flecs.EntityId,

    comp_query_body: flecs.Query,
    comp_query_loader: flecs.Query,
    loaders: [1]WorldLoaderData = .{.{}},
    requester_id: world_patch_manager.RequesterId,
    patches: std.ArrayList(Patch),
    indices: [indices_per_patch]IndexType,
};

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
) !*SystemState {
    var query_builder_body = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_body.with(fd.PhysicsBody)
        .with(fd.Transform);
    const comp_query_body = query_builder_body.buildQuery();

    var query_builder_loader = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_loader.with(fd.WorldLoader)
        .with(fd.Transform);
    const comp_query_loader = query_builder_loader.buildQuery();

    zbt.init(allocator);
    const physics_world = zbt.initWorld();
    physics_world.setGravity(&.{ 0.0, -10.0, 0.0 });

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .world_patch_mgr = world_patch_mgr,
        .sys = sys,
        .comp_query_body = comp_query_body,
        .comp_query_loader = comp_query_loader,
        .requester_id = world_patch_mgr.registerRequester(IdLocal.init("physics")),
        .patches = std.ArrayList(Patch).initCapacity(allocator, 8 * 8) catch unreachable,
        .indices = undefined,
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
    state.comp_query_loader.deinit();
    state.physics_world.deinit();
    zbt.deinit();
    state.patches.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state.physics_world.stepSimulation(iter.iter.delta_time, .{});
    updateBodies(state);
    updateLoaders(state);
    updatePatches(state);
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

fn updateLoaders(state: *SystemState) void {
    var entity_iter = state.comp_query_loader.iterator(struct {
        WorldLoader: *fd.WorldLoader,
        transform: *fd.Transform,
    });

    var arena_state = std.heap.ArenaAllocator.init(state.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    while (entity_iter.next()) |comps| {
        var loader_comp = comps.WorldLoader;
        if (!loader_comp.physics) {
            continue;
        }

        var loader = blk: {
            for (&state.loaders) |*loader| {
                if (loader.ent == entity_iter.entity().id) {
                    break :blk loader;
                }
            }

            // HACK
            state.loaders[0].ent = entity_iter.entity().id;
            break :blk &state.loaders[0];

            // unreachable;
        };

        const pos_new = comps.transform.getPos00();
        if (tides_math.dist3_xz(pos_new, loader.pos_old) < 32) {
            continue;
        }

        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;

        const area_old = world_patch_manager.RequestRectangle{
            .x = loader.pos_old[0] - 64,
            .z = loader.pos_old[2] - 64,
            .width = 128,
            .height = 128,
        };

        const area_new = world_patch_manager.RequestRectangle{
            .x = pos_new[0] - 64,
            .z = pos_new[2] - 64,
            .width = 128,
            .height = 128,
        };

        const patch_type_id = state.world_patch_mgr.getPatchTypeId(IdLocal.init("heightmap"));
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_old, 0, &lookups_old);
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_new, 0, &lookups_new);

        var i_old: u32 = 0;
        blk: while (i_old < lookups_old.items.len) {
            var i_new: u32 = 0;
            while (i_new < lookups_new.items.len) {
                if (lookups_old.items[i_old].eql(lookups_new.items[i_new])) {
                    _ = lookups_old.swapRemove(i_old);
                    _ = lookups_new.swapRemove(i_new);
                    continue :blk;
                }
                i_new += 1;
            }
            i_old += 1;
        }

        // HACK
        if (loader.pos_old[0] != -100000) {
            state.world_patch_mgr.removeLoadRequestFromLookups(state.requester_id, lookups_old.items);
        }

        state.world_patch_mgr.addLoadRequestFromLookups(state.requester_id, lookups_new.items, .high);

        for (lookups_new.items) |lookup| {
            state.patches.appendAssumeCapacity(.{
                .lookup = lookup,
            });
        }

        loader.pos_old = pos_new;
    }
}

fn updatePatches(state: *SystemState) void {
    for (state.patches.items) |*patch| {
        if (patch.body_opt) |body| {
            _ = body;
            continue;
        }

        const patch_info = state.world_patch_mgr.tryGetPatch(patch.lookup, f32);
        if (patch_info.data_opt) |data| {
            // _ = data;

            const world_pos = patch.lookup.getWorldPos();
            var vertices: [config.patch_resolution * config.patch_resolution][3]f32 = undefined;
            var z: u32 = 0;
            while (z < config.patch_resolution) : (z += 1) {
                var x: u32 = 0;
                while (x < config.patch_resolution) : (x += 1) {
                    const index = @intCast(u32, x + z * config.patch_resolution);
                    const height = data[index];

                    vertices[index][0] = @intToFloat(f32, x);
                    vertices[index][1] = height;
                    vertices[index][2] = @intToFloat(f32, z);
                }
            }

            var indices = &state.indices;
            // var indices: [indices_per_patch]IndexType = undefined;

            // TODO: Optimize, don't do it for every frame!
            var i: u32 = 0;
            z = 0;
            const width = @intCast(u32, config.patch_resolution);
            const height = @intCast(u32, config.patch_resolution);
            while (z < height - 1) : (z += 1) {
                var x: u32 = 0;
                while (x < width - 1) : (x += 1) {
                    const indices_quad = [_]u32{
                        x + z * width, //           0
                        x + (z + 1) * width, //     4
                        x + 1 + z * width, //       1
                        x + 1 + (z + 1) * width, // 5
                    };

                    indices[i + 0] = indices_quad[0]; // 0
                    indices[i + 1] = indices_quad[1]; // 4
                    indices[i + 2] = indices_quad[2]; // 1

                    indices[i + 3] = indices_quad[2]; // 1
                    indices[i + 4] = indices_quad[1]; // 4
                    indices[i + 5] = indices_quad[3]; // 5

                    // std.debug.print("quad: {any}\n", .{indices_quad});
                    // std.debug.print("indices: {any}\n", .{patch_indices[i .. i + 6]});
                    // std.debug.print("tri: {any} {any} {any}\n", .{
                    //     patch_vertex_positions[patch_indices[i + 0]],
                    //     patch_vertex_positions[patch_indices[i + 1]],
                    //     patch_vertex_positions[patch_indices[i + 2]],
                    // });
                    // std.debug.print("tri: {any} {any} {any}\n", .{
                    //     patch_vertex_positions[patch_indices[i + 3]],
                    //     patch_vertex_positions[patch_indices[i + 4]],
                    //     patch_vertex_positions[patch_indices[i + 5]],
                    // });
                    i += 6;
                }
            }
            std.debug.assert(i == indices_per_patch);
            std.debug.assert(i == indices_per_patch);
            std.debug.assert(i == indices_per_patch);
            std.debug.assert(i == indices_per_patch);

            // std.debug.assert(patch_indices.len == indices_per_patch);

            const trimesh = zbt.initTriangleMeshShape();
            trimesh.addIndexVertexArray(
                @intCast(u32, indices_per_patch / 3),
                &state.indices,
                @sizeOf([3]u32),
                @intCast(u32, vertices[0..].len),
                &vertices[0],
                @sizeOf([3]f32),
            );
            trimesh.finish();

            const shape = trimesh.asShape();
            patch.physics_shape_opt = shape;

            const transform = [_]f32{
                1.0,                                 0.0, 0.0,
                0.0,                                 1.0, 0.0,
                0.0,                                 0.0, 1.0,
                @intToFloat(f32, world_pos.world_x), 0,   @intToFloat(f32, world_pos.world_z),
            };

            const body = zbt.initBody(
                0,
                &transform,
                patch.physics_shape_opt.?,
            );

            body.setDamping(0.1, 0.1);
            body.setRestitution(0.5);
            body.setFriction(0.2);
            patch.body_opt = body;
            state.physics_world.addBody(body);
        }
    }
}

//  ██████╗ █████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗███████╗
// ██╔════╝██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
// ██║     ███████║██║     ██║     ██████╔╝███████║██║     █████╔╝ ███████╗
// ██║     ██╔══██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ╚════██║
// ╚██████╗██║  ██║███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗███████║
//  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

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
