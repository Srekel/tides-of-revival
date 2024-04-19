const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const config = @import("../config/config.zig");
const util = @import("../util.zig");
const EventManager = @import("../core/event_manager.zig").EventManager;
const context = @import("../core/context.zig");

const zignav = @import("zignav");
const Recast = zignav.Recast;
const DetourNavMesh = zignav.DetourNavMesh;
const DetourNavMeshBuilder = zignav.DetourNavMeshBuilder;
const DetourNavMeshQuery = zignav.DetourNavMeshQuery;
const DetourStatus = zignav.DetourStatus;

const IndexType = u32;
const patch_side_vertex_count = config.patch_resolution;
const vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;
const indices_per_patch: u32 = (config.patch_resolution - 1) * (config.patch_resolution - 1) * 6;

const WorldLoaderData = struct {
    ent: ecs.entity_t = 0,
    pos_old: [3]f32 = .{ -100000, 0, -100000 },
};

const Patch = struct {
    lookup: world_patch_manager.PatchLookup,
    poly_mesh_opt: ?*Recast.rcPolyMesh,
    poly_mesh_detail_opt: ?*Recast.rcPolyMeshDetail,
};

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    sys: ecs.entity_t,
    comp_query_loader: ecsu.Query,
    loaders: [1]WorldLoaderData = .{.{}},
    requester_id: world_patch_manager.RequesterId,
    patches: std.ArrayList(Patch),
    indices: [indices_per_patch]IndexType,
    nav_ctx: Recast.rcContext = undefined,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    event_mgr: *EventManager,
    physics_world: *zphy.PhysicsSystem,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    const allocator = ctx.allocator;
    const ecsu_world = ctx.ecsu_world;

    var query_builder_loader = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_loader.with(fd.WorldLoader)
        .with(fd.Transform);
    const comp_query_loader = query_builder_loader.buildQuery();

    // Recast
    var nav_ctx: zignav.Recast.rcContext = undefined;
    nav_ctx.init(false);

    var system = allocator.create(SystemState) catch unreachable;
    const sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .world_patch_mgr = ctx.world_patch_mgr,
        .sys = sys,
        .comp_query_loader = comp_query_loader,
        .requester_id = ctx.world_patch_mgr.registerRequester(IdLocal.init("navmesh")),
        .patches = std.ArrayList(Patch).initCapacity(allocator, 16 * 16) catch unreachable,
        .indices = undefined,
        .nav_ctx = nav_ctx,
    };

    system.nav_ctx.init(false);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_loader.deinit();
    system.patches.deinit();
    system.nav_ctx.deinit();
    system.allocator.destroy(system.contact_listener);
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    updateLoaders(system);
    updatePatches(system);
}

fn updateLoaders(system: *SystemState) void {
    var entity_iter = system.comp_query_loader.iterator(struct {
        WorldLoader: *fd.WorldLoader,
        transform: *fd.Transform,
    });

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    while (entity_iter.next()) |comps| {
        const loader_comp = comps.WorldLoader;
        if (!loader_comp.navmesh) {
            continue;
        }

        var loader = blk: {
            for (&system.loaders) |*loader| {
                if (loader.ent == entity_iter.entity()) {
                    break :blk loader;
                }
            }

            // HACK
            system.loaders[0].ent = entity_iter.entity();
            break :blk &system.loaders[0];
        };

        const pos_new = comps.transform.getPos00();
        if (tides_math.dist3_xz(pos_new, loader.pos_old) < 32) {
            continue;
        }

        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;

        const area_old = world_patch_manager.RequestRectangle{
            .x = loader.pos_old[0] - 256,
            .z = loader.pos_old[2] - 256,
            .width = 512,
            .height = 512,
        };

        const area_new = world_patch_manager.RequestRectangle{
            .x = pos_new[0] - 256,
            .z = pos_new[2] - 256,
            .width = 512,
            .height = 512,
        };

        const patch_type_id = system.world_patch_mgr.getPatchTypeId(IdLocal.init("heightmap"));
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
            system.world_patch_mgr.removeLoadRequestFromLookups(system.requester_id, lookups_old.items);

            for (lookups_old.items) |lookup| {
                for (system.patches.items, 0..) |*patch, i| {
                    if (patch.lookup.eql(lookup)) {
                        // TOOD: cleanup

                        _ = system.patches.swapRemove(i);
                        break;
                    }
                }
            }
        }

        system.world_patch_mgr.addLoadRequestFromLookups(system.requester_id, lookups_new.items, .medium);

        for (lookups_new.items) |lookup| {
            system.patches.appendAssumeCapacity(.{
                .lookup = lookup,
                .poly_mesh_opt = null,
                .poly_mesh_detail_opt = null,
            });
        }

        loader.pos_old = pos_new;
    }
}

fn updatePatches(system: *SystemState) void {
    for (system.patches.items) |*patch| {
        if (patch.poly_mesh_opt) |_| {
            continue;
        }

        const patch_info = system.world_patch_mgr.tryGetPatch(patch.lookup, f32);
        if (patch_info.data_opt) |data| {
            // _ = data;

            const world_pos = patch.lookup.getWorldPos();
            _ = world_pos; // autofix
            // var vertices: [config.patch_resolution * config.patch_resolution][3]f32 = undefined;
            // var z: u32 = 0;
            // while (z < config.patch_resolution) : (z += 1) {
            //     var x: u32 = 0;
            //     while (x < config.patch_resolution) : (x += 1) {
            //         const index = @intCast(u32, x + z * config.patch_resolution);
            //         const height = data[index];

            //         vertices[index][0] = @floatFromInt(f32, x);
            //         vertices[index][1] = height;
            //         vertices[index][2] = @floatFromInt(f32, z);
            //     }
            // }

            // var indices = &system.indices;
            // // var indices: [indices_per_patch]IndexType = undefined;

            // // TODO: Optimize, don't do it for every frame!
            // var i: u32 = 0;
            // z = 0;
            // const width = @intCast(u32, config.patch_resolution);
            // const height = @intCast(u32, config.patch_resolution);
            // while (z < height - 1) : (z += 1) {
            //     var x: u32 = 0;
            //     while (x < width - 1) : (x += 1) {
            //         const indices_quad = [_]u32{
            //             x + z * width, //           0
            //             x + (z + 1) * width, //     4
            //             x + 1 + z * width, //       1
            //             x + 1 + (z + 1) * width, // 5
            //         };

            //         indices[i + 0] = indices_quad[0]; // 0
            //         indices[i + 1] = indices_quad[1]; // 4
            //         indices[i + 2] = indices_quad[2]; // 1

            //         indices[i + 3] = indices_quad[2]; // 1
            //         indices[i + 4] = indices_quad[1]; // 4
            //         indices[i + 5] = indices_quad[3]; // 5

            //         // std.debug.print("quad: {any}\n", .{indices_quad});
            //         // std.debug.print("indices: {any}\n", .{patch_indices[i .. i + 6]});
            //         // std.debug.print("tri: {any} {any} {any}\n", .{
            //         //     patch_vertex_positions[patch_indices[i + 0]],
            //         //     patch_vertex_positions[patch_indices[i + 1]],
            //         //     patch_vertex_positions[patch_indices[i + 2]],
            //         // });
            //         // std.debug.print("tri: {any} {any} {any}\n", .{
            //         //     patch_vertex_positions[patch_indices[i + 3]],
            //         //     patch_vertex_positions[patch_indices[i + 4]],
            //         //     patch_vertex_positions[patch_indices[i + 5]],
            //         // });
            //         i += 6;
            //     }
            // }
            // std.debug.assert(i == indices_per_patch);
            // std.debug.assert(i == indices_per_patch);
            // std.debug.assert(i == indices_per_patch);
            // std.debug.assert(i == indices_per_patch);

            // std.debug.assert(patch_indices.len == indices_per_patch);

            //  TODO: Use mesh
            const height_field_size = config.patch_size;
            var samples: [height_field_size * height_field_size]f32 = undefined;

            const width = @as(u32, @intCast(config.patch_size));
            for (0..width) |z| {
                for (0..width) |x| {
                    const index = @as(u32, @intCast(x + z * config.patch_resolution));
                    const height = data[index];
                    const sample = &samples[x + z * width];
                    sample.* = height;
                }
            }

            // patch.shape_opt = shape;
        }
    }
}
