const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");
const im3d = @import("im3d");

const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const world_patch_manager = @import("../../worldpatch/world_patch_manager.zig");
const tides_math = @import("../../core/math.zig");
const config = @import("../../config/config.zig");
const util = @import("../../util.zig");
const EventManager = @import("../../core/event_manager.zig").EventManager;
const context = @import("../../core/context.zig");

const zignav = @import("zignav");
const Recast = zignav.Recast;
const DetourNavMesh = zignav.DetourNavMesh;
const DetourNavMeshBuilder = zignav.DetourNavMeshBuilder;
const DetourNavMeshQuery = zignav.DetourNavMeshQuery;
const DetourStatus = zignav.DetourStatus;
const nav_util = @import("navmesh_system_util.zig");

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
    lookup_neighbors: [8]world_patch_manager.PatchLookup,
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
    nav_mesh: [*c]DetourNavMesh.dtNavMesh = undefined,
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

    const nav_mesh = DetourNavMesh.dtAllocNavMesh();

    const navmesh_params = DetourNavMesh.dtNavMeshParams{
        .orig = .{ 0, 0, 0 },
        .tileWidth = @floatFromInt(config.patch_size),
        .tileHeight = @floatFromInt(config.patch_size),
        .maxTiles = 1024 * 1024 / (config.patch_size * config.patch_size),
        .maxPolys = 128 * 128,
    };
    const status_nm = nav_mesh.*.init__Overload2(&navmesh_params);
    assert(DetourStatus.dtStatusSucceed(status_nm));

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
        .nav_mesh = nav_mesh,
    };

    system.nav_ctx.init(false);
    return system;
}

pub fn destroy(system: *SystemState) void {
    DetourNavMesh.dtFreeNavMesh(system.nav_mesh);
    system.comp_query_loader.deinit();
    system.patches.deinit();
    system.nav_ctx.deinit();
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
            var neighbors = .{lookup} ** 8;
            neighbors[0].patch_x -= 1; // row below
            neighbors[0].patch_z -= 1;
            neighbors[1].patch_x += 0;
            neighbors[1].patch_z -= 1;
            neighbors[2].patch_x += 1;
            neighbors[2].patch_z -= 1;
            neighbors[3].patch_x -= 1; // same row, skip same patch
            neighbors[3].patch_z += 0;
            neighbors[4].patch_x += 1;
            neighbors[4].patch_z += 0;
            neighbors[5].patch_x -= 1; // row above
            neighbors[5].patch_z += 1;
            neighbors[6].patch_x += 0;
            neighbors[6].patch_z += 1;
            neighbors[7].patch_x += 1;
            neighbors[7].patch_z += 1;
            system.patches.appendAssumeCapacity(.{
                .lookup = lookup,
                .lookup_neighbors = neighbors,
                .poly_mesh_opt = null,
                .poly_mesh_detail_opt = null,
            });
        }

        loader.pos_old = pos_new;
    }
}

const Vertex = struct { x: f32, y: f32, z: f32 };

const vertex_margin = 3;
const vertices_side = config.patch_resolution + vertex_margin;
const square_side_count = (vertices_side - 1);
const square_count = square_side_count * square_side_count;
const triangle_count = square_count * 2;
var s_vertices: [vertices_side * vertices_side]Vertex = undefined;
const s_triangles = tri_blk: {
    @setEvalBranchQuota(square_side_count * square_side_count * 2);
    var tris: [triangle_count * 3]i32 = undefined;
    var triangle_index = 0;
    for (0..square_side_count) |sqx| {
        for (0..square_side_count) |sqz| {
            const bl = sqx + sqz * (square_side_count + 1); // bot left
            const br = sqx + sqz * (square_side_count + 1) + 1;
            const tl = sqx + (sqz + 1) * (square_side_count + 1);
            const tr = sqx + (sqz + 1) * (square_side_count + 1) + 1;
            tris[triangle_index + 0] = bl;
            tris[triangle_index + 1] = tr;
            tris[triangle_index + 2] = br;
            triangle_index += 3;
            tris[triangle_index + 0] = bl;
            tris[triangle_index + 1] = tl;
            tris[triangle_index + 2] = tr;
            triangle_index += 3;
        }
    }
    break :tri_blk tris;
};

fn readVertices(
    source: []const f32,
    source_pos: []const f32,
    source_offset_x: u32,
    source_offset_z: u32,
    dest: []Vertex,
    dest_offset_x: u32,
    dest_offset_z: u32,
) void {
    const count_x = @min(config.patch_resolution - source_offset_x - 1, vertices_side - dest_offset_x);
    const count_z = @min(config.patch_resolution - source_offset_z - 1, vertices_side - dest_offset_z);

    // util.log("");
    // util.log3("sourcelen", source.len, "destlen", dest.len, "vertices_side", vertices_side);

    for (0..count_z) |z| {
        for (0..count_x) |x| {
            const source_index = (x + source_offset_x) + (z + source_offset_z) * config.patch_resolution;
            const dest_index = (x + dest_offset_x) + (z + dest_offset_z) * vertices_side;
            // util.log2("source_index", source_index, "dest_index", dest_index);
            const val = source[source_index];
            dest[dest_index].x = source_pos[0] + @as(f32, @floatFromInt(x));
            dest[dest_index].y = source_pos[1] + val;
            dest[dest_index].z = source_pos[2] + @as(f32, @floatFromInt(z));
        }
    }
}

fn updatePatches(system: *SystemState) void {
    var patch_data: [9][]f32 = undefined;

    patch_loop: for (system.patches.items) |*patch| {
        if (patch.poly_mesh_opt) |_| {
            continue;
        }

        const patch_info = system.world_patch_mgr.tryGetPatch(patch.lookup, f32);
        if (patch_info.data_opt == null) {
            continue;
        }
        patch_data[5] = patch_info.data_opt.?;

        for (patch.lookup_neighbors, 0..8) |neighbor, neighbor_index| {
            const patch_info_neighbor = system.world_patch_mgr.tryGetPatch(neighbor, f32);
            if (patch_info_neighbor.data_opt == null) {
                continue :patch_loop;
            }
            patch_data[if (neighbor_index < 5) neighbor_index else neighbor_index + 1] = patch_info_neighbor.data_opt.?;
        }
        util.log2("x", patch.lookup.patch_x, "z", patch.lookup.patch_z);

        const world_pos = patch.lookup.getWorldPos();
        const world_pos_f = .{ @as(f32, @floatFromInt(world_pos.world_x)), 0, @as(f32, @floatFromInt(world_pos.world_z)) };

        const mrgn = vertex_margin;
        const psize = config.patch_size;
        const verts = &s_vertices;
        // zig fmt: off
        readVertices(patch_data[0], &world_pos_f, psize - mrgn, psize - mrgn, verts, 0,                        0);                        // bot left
        readVertices(patch_data[1], &world_pos_f, 0,            psize - mrgn, verts, mrgn,                     0);                        // bot mid
        readVertices(patch_data[2], &world_pos_f, 0,            psize - mrgn, verts, vertices_side - mrgn * 2, 0);                        // bot right
        readVertices(patch_data[3], &world_pos_f, psize - mrgn, 0,            verts, 0,                        mrgn);                     // mid left
        readVertices(patch_data[4], &world_pos_f, 0,            0,            verts, mrgn,                     mrgn);                     // mid mid
        readVertices(patch_data[5], &world_pos_f, 0,            0,            verts, vertices_side - mrgn * 2, mrgn);                     // mid right
        readVertices(patch_data[6], &world_pos_f, psize - mrgn, 0,            verts, 0,                        vertices_side - mrgn * 2); // top left
        readVertices(patch_data[7], &world_pos_f, 0,            0,            verts, mrgn,                     vertices_side - mrgn * 2); // top mid
        readVertices(patch_data[8], &world_pos_f, 0,            0,            verts, vertices_side - mrgn * 2, vertices_side - mrgn * 2); // top right
        // // zig fmt: on


        // im3d.Im3d.BeginTriangles();
        // im3d.Im3d.Vertex(world_pos.world_x, s_vertices[s_triangles[0]]);
        // im3d.Im3d.Vertex(s_vertices[s_triangles[1]]);
        // im3d.Im3d.Vertex(s_vertices[s_triangles[2]]);
        // im3d.Im3d.EndTriangles();



        const game_config: nav_util.GameConfig = .{
            .indoors = true,
            .tile_size = config.patch_size,
            .offset = .{ @floatFromInt(world_pos.world_x), 0, @floatFromInt(world_pos.world_z) },
        };
        _ = game_config; // autofix

        const tile_mesh = buildTileMesh(&system.nav_ctx, .{@floatFromInt(world_pos.world_x), 0, @floatFromInt(world_pos.world_z)  },) catch unreachable;
        patch.poly_mesh_opt = tile_mesh.poly_mesh;
        patch.poly_mesh_detail_opt = tile_mesh.poly_mesh_detail;

        const tile = nav_util.createTileFromPolyMesh(
            tile_mesh.poly_mesh,
            tile_mesh.poly_mesh_detail,
            tile_mesh.config,
            @intCast( @divFloor(world_pos.world_x, config.patch_size)),
            @intCast(  @divFloor(world_pos.world_z, config.patch_size)),
        ) catch unreachable;

        var tile_ref: DetourNavMesh.dtPolyRef = 0;
        const status_tile = system.nav_mesh.*.addTile(
            tile.data,
            tile.data_size,
            0, // DetourNavMesh.dtTileFlags.DT_TILE_FREE_DATA.bits,
            0,
            &tile_ref,
        );
        assert(DetourStatus.dtStatusSucceed(status_tile));
    }
}

pub fn buildTileMesh(
    nav_ctx: *Recast.rcContext,
    offset: [3]f32,
) !struct {
    config: Recast.rcConfig,
    poly_mesh: *Recast.rcPolyMesh,
    poly_mesh_detail: *Recast.rcPolyMeshDetail,
} {
    const recast_config = nav_util.generateConfig(nav_util.GameConfig{
        .indoors = true,
        .tile_size = config.patch_size,
        .offset = offset,
    });

    const heightfield = Recast.rcAllocHeightfield();
    const compact_heightfield = Recast.rcAllocCompactHeightfield();
    const contour_set = Recast.rcAllocContourSet();
    const poly_mesh = Recast.rcAllocPolyMesh();
    const poly_mesh_detail = Recast.rcAllocPolyMeshDetail();
    if (heightfield == null or
        compact_heightfield == null or
        contour_set == null or
        poly_mesh == null or
        poly_mesh_detail == null)
    {
        return error.OutOfMemory;
    }

    defer Recast.rcFreeHeightField(heightfield);
    defer Recast.rcFreeCompactHeightfield(compact_heightfield);
    defer Recast.rcFreeContourSet(contour_set);

    try nav_util.buildFullNavMesh(
        recast_config,
        nav_ctx,
      util.castSliceToSlice(f32, &s_vertices),
        &s_triangles,
        heightfield,
        compact_heightfield,
        contour_set,
        poly_mesh,
        poly_mesh_detail,
    );

    const FLAG_AREA_GROUND = 0;
    const FLAG_POLY_WALK = 1;

    for (0..@intCast(poly_mesh.*.npolys)) |pi| {
        if (poly_mesh.*.areas[pi] == Recast.WALKABLE_AREA) {
            poly_mesh.*.areas[pi] = FLAG_AREA_GROUND;
            poly_mesh.*.flags[pi] = FLAG_POLY_WALK;
        }
    }

    return .{
        .config = recast_config,
        .poly_mesh = poly_mesh,
        .poly_mesh_detail = poly_mesh_detail,
    };
}
