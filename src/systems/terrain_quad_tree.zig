const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");

const config = @import("../config/config.zig");
const renderer = @import("../renderer/tides_renderer.zig");
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");

const lod_load_range = 300;

const TerrainLayer = struct {
    diffuse: renderer.TextureHandle,
    normal: renderer.TextureHandle,
    arm: renderer.TextureHandle,
};

const TerrainLayerTextureIndices = extern struct {
    diffuse_index: u32,
    normal_index: u32,
    arm_index: u32,
    padding: u32,
};

// const DrawUniforms = struct {
//     start_instance_location: u32,
//     vertex_offset: i32,
//     vertex_buffer_index: u32,
//     instance_data_buffer_index: u32,
//     terrain_layers_buffer_index: u32,
//     terrain_height: f32,
//     heightmap_texel_size: f32,
// };

const InstanceData = struct {
    object_to_world: zm.Mat,
    heightmap_index: u32,
    splatmap_index: u32,
    lod: u32,
    padding1: u32,
};

const max_instances = 1000;
const max_instances_per_draw_call = 20;

const invalid_index = std.math.maxInt(u32);
const QuadTreeNode = struct {
    center: [2]f32,
    size: [2]f32,
    child_indices: [4]u32,
    mesh_lod: u32,
    patch_index: [2]u32,
    // TODO(gmodarelli): Do not store these here when we implement streaming
    heightmap_handle: ?renderer.TextureHandle,
    splatmap_handle: ?renderer.TextureHandle,

    pub inline fn containsPoint(self: *QuadTreeNode, point: [2]f32) bool {
        return (point[0] > (self.center[0] - self.size[0]) and
            point[0] < (self.center[0] + self.size[0]) and
            point[1] > (self.center[1] - self.size[1]) and
            point[1] < (self.center[1] + self.size[1]));
    }

    pub inline fn nearPoint(self: *QuadTreeNode, point: [2]f32, range: f32) bool {
        const half_size = self.size[0] / 2;
        const circle_distance_x = @abs(point[0] - self.center[0]);
        const circle_distance_y = @abs(point[1] - self.center[1]);

        if (circle_distance_x > (half_size + range)) {
            return false;
        }
        if (circle_distance_y > (half_size + range)) {
            return false;
        }

        if (circle_distance_x <= (half_size)) {
            return true;
        }
        if (circle_distance_y <= (half_size)) {
            return true;
        }

        const corner_distance_sq = (circle_distance_x - half_size) * (circle_distance_x - half_size) +
            (circle_distance_y - half_size) * (circle_distance_y - half_size);

        return (corner_distance_sq <= (range * range));
    }

    pub inline fn isLoaded(self: *QuadTreeNode) bool {
        return self.heightmap_handle != null and self.splatmap_handle != null;
    }

    pub fn containedInsideChildren(self: *QuadTreeNode, point: [2]f32, range: f32, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.nearPoint(point, range)) {
            return false;
        }

        for (self.child_indices) |child_index| {
            if (child_index == std.math.maxInt(u32)) {
                return false;
            }

            var node = nodes.items[child_index];
            if (node.nearPoint(point, range)) {
                return true;
            }
        }

        return false;
    }

    pub fn areChildrenLoaded(self: *QuadTreeNode, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.isLoaded()) {
            return false;
        }

        for (self.child_indices) |child_index| {
            if (child_index == std.math.maxInt(u32)) {
                return false;
            }

            var node = nodes.items[child_index];
            if (!node.isLoaded()) {
                return false;
            }
        }

        return true;
    }
};

const DrawCall = struct {
    index_count: u32,
    instance_count: u32,
    index_offset: u32,
    vertex_offset: i32,
    start_instance_location: u32,
};

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    sys: ecs.entity_t,

    // gfx: *gfx.D3D12State,

    // vertex_buffer: gfx.BufferHandle,
    // index_buffer: gfx.BufferHandle,
    terrain_layers_buffer: renderer.BufferHandle,
    instance_data_buffers: [renderer.buffered_frames_count]renderer.BufferHandle,
    instance_data: std.ArrayList(InstanceData),
    draw_calls: std.ArrayList(DrawCall),

    terrain_quad_tree_nodes: std.ArrayList(QuadTreeNode),
    terrain_lod_meshes: std.ArrayList(renderer.MeshHandle),
    quads_to_render: std.ArrayList(u32),
    quads_to_load: std.ArrayList(u32),

    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,

    cam_pos_old: [3]f32 = .{ -100000, 0, -100000 }, // NOTE(Anders): Assumes only one camera
};

fn loadMesh(path: [:0]const u8, meshes: *std.ArrayList(renderer.MeshHandle)) !void {
    const mesh_handle = renderer.loadMesh(path);
    meshes.append(mesh_handle) catch unreachable;
}

fn loadTerrainLayer(name: []const u8) !TerrainLayer {
    const diffuse = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "{s}_diff_2k.dds",
            .{name},
        ) catch unreachable;

        break :blk renderer.loadTexture(path);
    };

    const normal = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "{s}_nor_dx_2k.dds",
            .{name},
        ) catch unreachable;

        break :blk renderer.loadTexture(path);
    };

    const arm = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "{s}_arm_2k.dds",
            .{name},
        ) catch unreachable;

        break :blk renderer.loadTexture(path);
    };

    return .{
        .diffuse = diffuse,
        .normal = normal,
        .arm = arm,
    };
}

fn loadNodeHeightmap(
    node: *QuadTreeNode,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    assert(node.heightmap_handle == null);

    const lookup = world_patch_manager.PatchLookup{
        .patch_x = @as(u16, @intCast(node.patch_index[0])),
        .patch_z = @as(u16, @intCast(node.patch_index[1])),
        .lod = @as(u4, @intCast(node.mesh_lod)),
        .patch_type_id = heightmap_patch_type_id,
    };

    const patch_info = world_patch_mgr.tryGetPatch(lookup, u8);
    if (patch_info.data_opt) |data| {
        var data_slice = renderer.Slice{
            .data = @as(*anyopaque, @ptrCast(data)),
            .size = data.len,
        };

        var namebuf: [256]u8 = undefined;
        const debug_name = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "lod{d}/heightmap_x{d}_y{d}",
            .{ node.mesh_lod, node.patch_index[0], node.patch_index[1] },
        ) catch unreachable;

        node.heightmap_handle = renderer.loadTextureFromMemory(65, 65, .R32_SFLOAT, data_slice, debug_name);
    }
}

fn loadNodeSplatmap(
    node: *QuadTreeNode,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    assert(node.splatmap_handle == null);

    const lookup = world_patch_manager.PatchLookup{
        .patch_x = @as(u16, @intCast(node.patch_index[0])),
        .patch_z = @as(u16, @intCast(node.patch_index[1])),
        .lod = @as(u4, @intCast(node.mesh_lod)),
        .patch_type_id = splatmap_patch_type_id,
    };

    const patch_info = world_patch_mgr.tryGetPatch(lookup, u8);
    if (patch_info.data_opt) |data| {
        var data_slice = renderer.Slice{
            .data = @as(*anyopaque, @ptrCast(data)),
            .size = data.len,
        };

        var namebuf: [256]u8 = undefined;
        const debug_name = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "lod{d}/splatmap_x{d}_y{d}",
            .{ node.mesh_lod, node.patch_index[0], node.patch_index[1] },
        ) catch unreachable;

        node.splatmap_handle = renderer.loadTextureFromMemory(65, 65, .R8_UNORM, data_slice, debug_name);
    }
}

fn loadHeightAndSplatMaps(
    node: *QuadTreeNode,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    if (node.heightmap_handle == null) {
        loadNodeHeightmap(node, world_patch_mgr, heightmap_patch_type_id) catch unreachable;
    }

    // NOTE(gmodarelli): avoid loading the splatmap if we haven't loaded the heightmap
    // This improves up startup times
    if (node.heightmap_handle == null) {
        return;
    }

    if (node.splatmap_handle == null) {
        loadNodeSplatmap(node, world_patch_mgr, splatmap_patch_type_id) catch unreachable;
    }
}

fn loadResources(
    allocator: std.mem.Allocator,
    quad_tree_nodes: *std.ArrayList(QuadTreeNode),
    terrain_layers: *std.ArrayList(TerrainLayer),
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Load terrain layers textures
    {
        const dry_ground = loadTerrainLayer("dry_ground_rocks") catch unreachable;
        const forest_ground = loadTerrainLayer("forest_ground_01") catch unreachable;
        const rock_ground = loadTerrainLayer("rock_ground") catch unreachable;
        const snow = loadTerrainLayer("snow_02") catch unreachable;

        // NOTE: There's an implicit dependency on the order of the Splatmap here
        // - 0 dirt
        // - 1 grass
        // - 2 rock
        // - 3 snow
        terrain_layers.append(dry_ground) catch unreachable;
        terrain_layers.append(forest_ground) catch unreachable;
        terrain_layers.append(rock_ground) catch unreachable;
        terrain_layers.append(snow) catch unreachable;
    }

    // Ask the World Patch Manager to load all LOD3 for the current world extents
    const rid = world_patch_mgr.registerRequester(IdLocal.init("terrain_quad_tree"));
    const area = world_patch_manager.RequestRectangle{ .x = 0, .z = 0, .width = 4096, .height = 4096 };
    var lookups = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
    world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 3, &lookups);
    world_patch_manager.WorldPatchManager.getLookupsFromRectangle(splatmap_patch_type_id, area, 3, &lookups);
    world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .high);
    // Make sure all LOD3 are resident
    world_patch_mgr.tickAll();

    // Request loading all the other LODs
    lookups.clearRetainingCapacity();
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 2, &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(splatmap_patch_type_id, area, 2, &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 1 &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(splatmap_patch_type_id, area, 1, &lookups);
    // world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .medium);

    // Load all LOD's heightmaps
    {
        var i: u32 = 0;
        while (i < quad_tree_nodes.items.len) : (i += 1) {
            var node = &quad_tree_nodes.items[i];
            loadHeightAndSplatMaps(
                node,
                world_patch_mgr,
                heightmap_patch_type_id,
                splatmap_patch_type_id,
            ) catch unreachable;
        }
    }
}

fn divideQuadTreeNode(
    nodes: *std.ArrayList(QuadTreeNode),
    node: *QuadTreeNode,
) void {
    if (node.mesh_lod == 0) {
        return;
    }

    var child_index: u32 = 0;
    while (child_index < 4) : (child_index += 1) {
        var center_x = if (child_index % 2 == 0) node.center[0] - node.size[0] * 0.5 else node.center[0] + node.size[0] * 0.5;
        var center_y = if (child_index < 2) node.center[1] + node.size[1] * 0.5 else node.center[1] - node.size[1] * 0.5;
        var patch_index_x: u32 = if (child_index % 2 == 0) 0 else 1;
        var patch_index_y: u32 = if (child_index < 2) 1 else 0;

        var child_node = QuadTreeNode{
            .center = [2]f32{ center_x, center_y },
            .size = [2]f32{ node.size[0] * 0.5, node.size[1] * 0.5 },
            .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
            .mesh_lod = node.mesh_lod - 1,
            .patch_index = [2]u32{ node.patch_index[0] * 2 + patch_index_x, node.patch_index[1] * 2 + patch_index_y },
            .heightmap_handle = null,
            .splatmap_handle = null,
        };

        node.child_indices[child_index] = @as(u32, @intCast(nodes.items.len));
        nodes.appendAssumeCapacity(child_node);

        assert(node.child_indices[child_index] < nodes.items.len);
        divideQuadTreeNode(nodes, &nodes.items[node.child_indices[child_index]]);
    }
}

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
) !*SystemState {
    // TODO(gmodarelli): This is just enough for a single sector, but it's good for testing
    const max_quad_tree_nodes: usize = 85 * 64;
    var terrain_quad_tree_nodes = std.ArrayList(QuadTreeNode).initCapacity(allocator, max_quad_tree_nodes) catch unreachable;
    var quads_to_render = std.ArrayList(u32).init(allocator);
    var quads_to_load = std.ArrayList(u32).init(allocator);

    // Create initial sectors
    {
        var patch_half_size = @as(f32, @floatFromInt(config.largest_patch_width)) / 2.0;
        var patch_y: u32 = 0;
        while (patch_y < 8) : (patch_y += 1) {
            var patch_x: u32 = 0;
            while (patch_x < 8) : (patch_x += 1) {
                terrain_quad_tree_nodes.appendAssumeCapacity(.{
                    .center = [2]f32{
                        @as(f32, @floatFromInt(patch_x * config.largest_patch_width)) + patch_half_size,
                        @as(f32, @floatFromInt(patch_y * config.largest_patch_width)) + patch_half_size,
                    },
                    .size = [2]f32{ patch_half_size, patch_half_size },
                    .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
                    .mesh_lod = 3,
                    .patch_index = [2]u32{ patch_x, patch_y },
                    .heightmap_handle = null,
                    .splatmap_handle = null,
                });
            }
        }

        assert(terrain_quad_tree_nodes.items.len == 64);

        var sector_index: u32 = 0;
        while (sector_index < 64) : (sector_index += 1) {
            var node = &terrain_quad_tree_nodes.items[sector_index];
            divideQuadTreeNode(&terrain_quad_tree_nodes, node);
        }
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var meshes = std.ArrayList(renderer.MeshHandle).init(allocator);

    loadMesh("prefabs/environment/terrain/theforge/terrain_patch_0.bin", &meshes) catch unreachable;
    loadMesh("prefabs/environment/terrain/theforge/terrain_patch_1.bin", &meshes) catch unreachable;
    loadMesh("prefabs/environment/terrain/theforge/terrain_patch_2.bin", &meshes) catch unreachable;
    loadMesh("prefabs/environment/terrain/theforge/terrain_patch_3.bin", &meshes) catch unreachable;

    const heightmap_patch_type_id = world_patch_mgr.getPatchTypeId(IdLocal.init("heightmap"));
    const splatmap_patch_type_id = world_patch_mgr.getPatchTypeId(IdLocal.init("splatmap"));

    var terrain_layers = std.ArrayList(TerrainLayer).init(arena);
    loadResources(
        allocator,
        &terrain_quad_tree_nodes,
        &terrain_layers,
        world_patch_mgr,
        heightmap_patch_type_id,
        splatmap_patch_type_id,
    ) catch unreachable;

    var terrain_layer_texture_indices = std.ArrayList(TerrainLayerTextureIndices).initCapacity(arena, terrain_layers.items.len) catch unreachable;
    var terrain_layer_index: u32 = 0;
    while (terrain_layer_index < terrain_layers.items.len) : (terrain_layer_index += 1) {
        const terrain_layer = &terrain_layers.items[terrain_layer_index];
        terrain_layer_texture_indices.appendAssumeCapacity(.{
            .diffuse_index = renderer.textureBindlessIndex(terrain_layer.diffuse),
            .normal_index = renderer.textureBindlessIndex(terrain_layer.normal),
            .arm_index = renderer.textureBindlessIndex(terrain_layer.arm),
            .padding = 42,
        });
    }

    const transform_layer_data = renderer.Slice{
        .data = @ptrCast(terrain_layer_texture_indices.items),
        .size = terrain_layer_texture_indices.items.len * @sizeOf(TerrainLayerTextureIndices),
    };
    const terrain_layers_buffer = renderer.createBuffer(transform_layer_data, @sizeOf(TerrainLayerTextureIndices), "Terrain Layers Buffer");

    // Create instance buffers.
    const instance_data_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = max_instances * @sizeOf(InstanceData),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(InstanceData), "Terrain Quad Tree Instance Data Buffer");
        }

        break :blk buffers;
    };

    var draw_calls = std.ArrayList(DrawCall).init(allocator);
    var instance_data = std.ArrayList(InstanceData).init(allocator);

    var system = allocator.create(SystemState) catch unreachable;
    var sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });

    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .world_patch_mgr = world_patch_mgr,
        .sys = sys,
        .instance_data_buffers = instance_data_buffers,
        .draw_calls = draw_calls,
        .instance_data = instance_data,
        .terrain_layers_buffer = terrain_layers_buffer,
        .terrain_lod_meshes = meshes,
        .terrain_quad_tree_nodes = terrain_quad_tree_nodes,
        .quads_to_render = quads_to_render,
        .quads_to_load = quads_to_load,
        .heightmap_patch_type_id = heightmap_patch_type_id,
        .splatmap_patch_type_id = splatmap_patch_type_id,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    // TODO(gmodarelli): Destroy renderer resources?

    system.terrain_lod_meshes.deinit();
    system.instance_data.deinit();
    system.terrain_quad_tree_nodes.deinit();
    system.quads_to_render.deinit();
    system.quads_to_load.deinit();
    system.draw_calls.deinit();
    system.allocator.destroy(system);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var cam_ent = util.getActiveCameraEnt(system.ecsu_world);
    const cam_comps = cam_ent.getComps(struct {
        cam: *const fd.Camera,
        transform: *const fd.Transform,
    });

    // const cam = cam_comps.cam;
    const camera_position = cam_comps.transform.getPos00();

    // Reset transforms, materials and draw calls array list
    system.quads_to_render.clearRetainingCapacity();
    system.quads_to_load.clearRetainingCapacity();
    system.instance_data.clearRetainingCapacity();
    system.draw_calls.clearRetainingCapacity();

    {
        var sector_index: u32 = 0;
        while (sector_index < 64) : (sector_index += 1) {
            const lod3_node = &system.terrain_quad_tree_nodes.items[sector_index];
            const camera_point = [2]f32{ camera_position[0], camera_position[2] };

            collectQuadsToRenderForSector(
                system,
                camera_point,
                lod_load_range,
                lod3_node,
                sector_index,
                arena,
            ) catch unreachable;
        }
    }

    // {
    //     // TODO: Batch quads together by mesh lod
    //     var start_instance_location: u32 = 0;
    //     for (system.quads_to_render.items) |quad_index| {
    //         const quad = &system.terrain_quad_tree_nodes.items[quad_index];

    //         const object_to_world = zm.translation(quad.center[0], 0.0, quad.center[1]);
    //         // TODO: Generate from quad.patch_index
    //         const heightmap = system.gfx.lookupTexture(quad.heightmap_handle.?);
    //         const splatmap = system.gfx.lookupTexture(quad.splatmap_handle.?);
    //         system.instance_data.append(.{
    //             .object_to_world = zm.transpose(object_to_world),
    //             .heightmap_index = heightmap.?.persistent_descriptor.index,
    //             .splatmap_index = splatmap.?.persistent_descriptor.index,
    //             .lod = quad.mesh_lod,
    //             .padding1 = 42,
    //         }) catch unreachable;

    //         const mesh = system.terrain_lod_meshes.items[quad.mesh_lod];

    //         system.draw_calls.append(.{
    //             .index_count = mesh.sub_meshes[0].lods[0].index_count,
    //             .instance_count = 1,
    //             .index_offset = mesh.sub_meshes[0].lods[0].index_offset,
    //             .vertex_offset = @as(i32, @intCast(mesh.sub_meshes[0].lods[0].vertex_offset)),
    //             .start_instance_location = start_instance_location,
    //         }) catch unreachable;

    //         start_instance_location += 1;
    //     }
    // }

    // const frame_index = system.gfx.gctx.frame_index;
    // if (system.instance_data.items.len > 0) {
    //     assert(system.instance_data.items.len < max_instances);
    //     _ = system.gfx.uploadDataToBuffer(InstanceData, system.instance_data_buffers[frame_index], 0, system.instance_data.items);
    // }

    // const vertex_buffer = system.gfx.lookupBuffer(system.vertex_buffer);
    // const instance_data_buffer = system.gfx.lookupBuffer(system.instance_data_buffers[frame_index]);
    // const terrain_layers_buffer = system.gfx.lookupBuffer(system.terrain_layers_buffer);

    // for (system.draw_calls.items) |draw_call| {
    //     const mem = system.gfx.gctx.allocateUploadMemory(DrawUniforms, 1);
    //     mem.cpu_slice[0].start_instance_location = draw_call.start_instance_location;
    //     mem.cpu_slice[0].vertex_offset = draw_call.vertex_offset;
    //     mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
    //     mem.cpu_slice[0].instance_data_buffer_index = instance_data_buffer.?.persistent_descriptor.index;
    //     mem.cpu_slice[0].terrain_layers_buffer_index = terrain_layers_buffer.?.persistent_descriptor.index;
    //     mem.cpu_slice[0].terrain_height = config.terrain_span;
    //     mem.cpu_slice[0].heightmap_texel_size = 1.0 / @as(f32, @floatFromInt(config.patch_resolution));
    //     system.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

    //     system.gfx.gctx.cmdlist.DrawIndexedInstanced(
    //         draw_call.index_count,
    //         draw_call.instance_count,
    //         draw_call.index_offset,
    //         draw_call.vertex_offset,
    //         draw_call.start_instance_location,
    //     );
    // }

    // system.gfx.gpu_profiler.endProfile(system.gfx.gctx.cmdlist, system.gpu_frame_profiler_index, system.gfx.gctx.frame_index);

    for (system.quads_to_load.items) |quad_index| {
        var node = &system.terrain_quad_tree_nodes.items[quad_index];
        loadHeightAndSplatMaps(
            node,
            system.world_patch_mgr,
            system.heightmap_patch_type_id,
            system.splatmap_patch_type_id,
        ) catch unreachable;
    }

    // Load high-lod patches near camera
    if (tides_math.dist3_xz(system.cam_pos_old, camera_position) > 32) {
        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        for (0..3) |lod| {
            lookups_old.clearRetainingCapacity();
            lookups_new.clearRetainingCapacity();

            const area_width = 4 * config.patch_size * @as(f32, @floatFromInt(std.math.pow(usize, 2, lod)));

            const area_old = world_patch_manager.RequestRectangle{
                .x = system.cam_pos_old[0] - area_width,
                .z = system.cam_pos_old[2] - area_width,
                .width = area_width * 2,
                .height = area_width * 2,
            };

            const area_new = world_patch_manager.RequestRectangle{
                .x = camera_position[0] - area_width,
                .z = camera_position[2] - area_width,
                .width = area_width * 2,
                .height = area_width * 2,
            };

            const lod_u4 = @as(u4, @intCast(lod));
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(system.heightmap_patch_type_id, area_old, lod_u4, &lookups_old);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(system.splatmap_patch_type_id, area_old, lod_u4, &lookups_old);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(system.heightmap_patch_type_id, area_new, lod_u4, &lookups_new);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(system.splatmap_patch_type_id, area_new, lod_u4, &lookups_new);

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

            const rid = system.world_patch_mgr.getRequester(IdLocal.init("terrain_quad_tree")); // HACK(Anders)
            // NOTE(Anders): HACK
            if (system.cam_pos_old[0] != -100000) {
                system.world_patch_mgr.removeLoadRequestFromLookups(rid, lookups_old.items);
            }

            system.world_patch_mgr.addLoadRequestFromLookups(rid, lookups_new.items, .medium);
        }

        system.cam_pos_old = camera_position;
    }
}

// Algorithm that walks a quad tree and generates a list of quad tree nodes to render
fn collectQuadsToRenderForSector(system: *SystemState, position: [2]f32, range: f32, node: *QuadTreeNode, node_index: u32, allocator: std.mem.Allocator) !void {
    assert(node_index != invalid_index);

    if (node.mesh_lod == 0) {
        return;
    }

    if (node.containedInsideChildren(position, range, &system.terrain_quad_tree_nodes) and node.areChildrenLoaded(&system.terrain_quad_tree_nodes)) {
        var higher_lod_node_indices: [4]u32 = .{ invalid_index, invalid_index, invalid_index, invalid_index };
        for (node.child_indices, 0..) |node_child_index, i| {
            var child_node = &system.terrain_quad_tree_nodes.items[node_child_index];
            if (child_node.nearPoint(position, range)) {
                if (child_node.mesh_lod == 1 and child_node.areChildrenLoaded(&system.terrain_quad_tree_nodes)) {
                    system.quads_to_render.appendSlice(child_node.child_indices[0..4]) catch unreachable;
                } else if (child_node.mesh_lod == 1 and !child_node.areChildrenLoaded(&system.terrain_quad_tree_nodes)) {
                    system.quads_to_render.append(node_child_index) catch unreachable;
                    system.quads_to_load.appendSlice(child_node.child_indices[0..4]) catch unreachable;
                } else if (child_node.mesh_lod > 1) {
                    higher_lod_node_indices[i] = node_child_index;
                }
            } else {
                system.quads_to_render.append(node_child_index) catch unreachable;
            }
        }

        for (higher_lod_node_indices) |higher_lod_node_index| {
            if (higher_lod_node_index != invalid_index) {
                var child_node = &system.terrain_quad_tree_nodes.items[higher_lod_node_index];
                collectQuadsToRenderForSector(system, position, range, child_node, higher_lod_node_index, allocator) catch unreachable;
            } else {
                // system.quads_to_render.append(node.child_indices[i]) catch unreachable;
            }
        }
    } else if (node.containedInsideChildren(position, range, &system.terrain_quad_tree_nodes) and !node.areChildrenLoaded(&system.terrain_quad_tree_nodes)) {
        system.quads_to_render.append(node_index) catch unreachable;
        system.quads_to_load.appendSlice(node.child_indices[0..4]) catch unreachable;
    } else {
        if (node.isLoaded()) {
            system.quads_to_render.append(node_index) catch unreachable;
        } else {
            system.quads_to_load.append(node_index) catch unreachable;
        }
    }
}
