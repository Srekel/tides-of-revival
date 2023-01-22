const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const glfw = @import("glfw");
const zm = @import("zmath");
const zmu = @import("zmathutil");
const flecs = @import("flecs");

const gfx = @import("../gfx_d3d12.zig");
const zd3d12 = @import("zd3d12");
const zwin32 = @import("zwin32");
const hrPanic = zwin32.hrPanic;
const d3d12 = zwin32.d3d12;

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const IndexType = u32;

const zmesh = @import("zmesh");

const Texture = struct {
    resource: zd3d12.ResourceHandle,
    persistent_descriptor: zd3d12.PersistentDescriptor,
};

const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
    time: f32,
};

const DrawUniforms = struct {
    start_instance_location: u32,
    vertex_offset: i32,
    vertex_buffer_index: u32,
    instance_transform_buffer_index: u32,
    instance_material_buffer_index: u32,
};

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
};

const InstanceTransform = struct {
    object_to_world: zm.Mat,
};

const InstanceMaterial = struct {
    heightmap_index: u32,
};

const max_instances = 100;
const max_instances_per_draw_call = 20;

const DrawCall = struct {
    mesh_index: u32,
    index_count: u32,
    instance_count: u32,
    index_offset: u32,
    vertex_offset: i32,
    start_instance_location: u32,
};

const Mesh = struct {
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

const QuadTreeNode = struct {
    center: [2]f32,
    size: [2]f32,
    child_indices: [4]u32,
    mesh_lod: u32,
    patch_index: [2]u32,
    // TODO: Do not store this here when we implement streaming
    heightmap_handle: gfx.TextureHandle,

    pub inline fn containsPoint(self: *QuadTreeNode, point: [2]f32) bool {
        return !(point[0] < (self.center[0] - self.size[0]) or
            point[0] > (self.center[0] + self.size[0]) or
            point[1] < (self.center[1] - self.size[1]) or
            point[1] > (self.center[1] + self.size[1]));
    }

    pub fn containedInsideChildren(self: *QuadTreeNode, point: [2]f32, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.containsPoint(point)) {
            return false;
        }

        for (self.child_indices) |child_index| {
            var node = nodes.items[child_index];
            if (node.containsPoint(point)) {
                return true;
            }
        }

        return false;
    }
};

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    sys: flecs.EntityId,

    gfx: *gfx.D3D12State,

    query_camera: flecs.Query,

    vertex_buffer: gfx.BufferHandle,
    index_buffer: gfx.BufferHandle,
    instance_transform_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_material_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_transforms: std.ArrayList(InstanceTransform),
    instance_materials: std.ArrayList(InstanceMaterial),
    draw_calls: std.ArrayList(DrawCall),
    gpu_frame_profiler_index: u64 = undefined,

    terrain_quad_tree_nodes: std.ArrayList(QuadTreeNode),
    terrain_lod_meshes: std.ArrayList(Mesh),
    quads_to_render: std.ArrayList(u32),

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

fn loadMesh(
    allocator: std.mem.Allocator,
    path: []const u8,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.warn("Unable to open file: {s}", .{@errorName(err)});
        return err;
    };
    defer file.close();

    var buffer_reader = std.io.bufferedReader(file.reader());
    var in_stream = buffer_reader.reader();

    var mesh = Mesh{
        .index_offset = @intCast(u32, meshes_indices.items.len),
        .vertex_offset = @intCast(i32, meshes_vertices.items.len),
        .num_indices = 0,
        .num_vertices = 0,
    };

    // var unique_indices_map = std.StringHashMap(u32).init(allocator);
    var unique_indices_map = std.HashMap([]const u8, u32, std.hash_map.StringContext, 80).init(allocator);
    try unique_indices_map.ensureTotalCapacity(10 * 1024);
    defer unique_indices_map.deinit();

    var indices = std.ArrayList(IndexType).init(arena);
    var vertices = std.ArrayList(Vertex).init(arena);

    var positions = std.ArrayList([3]f32).init(arena);
    var normals = std.ArrayList([3]f32).init(arena);
    var uvs = std.ArrayList([2]f32).init(arena);

    var buf: [1024]u8 = undefined;

    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = std.mem.split(u8, line, " ");

        var first = it.first();
        if (std.mem.eql(u8, first, "v")) {
            var position: [3]f32 = undefined;
            position[0] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            position[1] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            position[2] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            positions.append(position) catch unreachable;
        } else if (std.mem.eql(u8, first, "vn")) {
            var normal: [3]f32 = undefined;
            normal[0] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            normal[1] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            normal[2] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            normals.append(normal) catch unreachable;
        } else if (std.mem.eql(u8, first, "vt")) {
            var uv: [2]f32 = undefined;
            uv[0] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            uv[1] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            uvs.append(uv) catch unreachable;
        } else if (std.mem.eql(u8, first, "f")) {
            var triangle_index: u32 = 0;
            while (triangle_index < 3) : (triangle_index += 1) {
                var vertex_components = it.next().?;
                var triangles_iterator = std.mem.split(u8, vertex_components, "/");

                // NOTE(gmodarelli): We're assuming Positions, UV's and Normals are exported with the OBJ file.
                // TODO(gmodarelli): Parse the OBJ in 2 passes. First collect all attributes and then generate
                // vertices and indices. Positions and UV's must be present, Normals can be calculated.
                var position_index = std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10) catch unreachable;
                position_index -= 1;
                var uv_index = std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10) catch unreachable;
                uv_index -= 1;
                var normal_index = std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10) catch unreachable;
                normal_index -= 1;

                const unique_vertex_index = @intCast(u32, vertices.items.len);
                indices.append(unique_vertex_index) catch unreachable;
                vertices.append(.{
                    .position = positions.items[position_index],
                    .normal = normals.items[normal_index],
                    .uv = uvs.items[uv_index],
                }) catch unreachable;
            }
        }
    }

    var remapped_indices = std.ArrayList(u32).init(arena);
    remapped_indices.resize(indices.items.len) catch unreachable;

    const num_unique_vertices = zmesh.opt.generateVertexRemap(
        remapped_indices.items,
        indices.items,
        Vertex,
        vertices.items,
    );

    var optimized_vertices = std.ArrayList(Vertex).init(arena);
    optimized_vertices.resize(num_unique_vertices) catch unreachable;

    zmesh.opt.remapVertexBuffer(
        Vertex,
        optimized_vertices.items,
        vertices.items,
        remapped_indices.items,
    );

    mesh.num_indices = @intCast(u32, remapped_indices.items.len);
    mesh.num_vertices = @intCast(u32, optimized_vertices.items.len);

    meshes.append(mesh) catch unreachable;
    meshes_indices.appendSlice(remapped_indices.items) catch unreachable;
    meshes_vertices.appendSlice(optimized_vertices.items) catch unreachable;
}

fn loadResources(
    allocator: std.mem.Allocator,
    quad_tree_nodes: *std.ArrayList(QuadTreeNode),
    gfxstate: *gfx.D3D12State,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) !void {
    loadMesh(allocator, "content/meshes/LOD0.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    loadMesh(allocator, "content/meshes/LOD1.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    loadMesh(allocator, "content/meshes/LOD2.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    loadMesh(allocator, "content/meshes/LOD3.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;

    // Load the LOD3 and LOD2 heightmaps
    {
        var namebuf: [256]u8 = undefined;

        var i: u32 = 0;
        while (i < quad_tree_nodes.items.len) : (i += 1) {
            var node = &quad_tree_nodes.items[i];

            const namebufslice = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "content/patch/lod{}/heightmap_x{}_y{}.png",
                .{
                    node.mesh_lod,
                    node.patch_index[0],
                    node.patch_index[1],
                },
            ) catch unreachable;

            std.debug.print("Loading patch: {s}\n", .{ namebufslice });

            node.heightmap_handle = gfxstate.scheduleLoadTexture(namebufslice, .{
                .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                .name = L("FIXME"),
            }) catch unreachable;
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

    const invalid_index = std.math.maxInt(u32);
    var child_index: u32 = 0;
    while (child_index < 4) : (child_index += 1) {
        var center_x = if (child_index % 2 == 0) node.center[0] - node.size[0] * 0.5 else node.center[0] + node.size[0] * 0.5;
        var center_y = if (child_index < 2) node.center[1] - node.size[1] * 0.5 else node.center[1] + node.size[1] * 0.5;
        var patch_index_x: u32 = if (child_index % 2 == 0) 0 else 1;
        // var patch_index_y: u32 = if (child_index < 2) 0 else 1;
        var patch_index_y: u32 = if (child_index < 2) 1 else 0;

        var child_node = QuadTreeNode{
            .center = [2]f32{ center_x, center_y },
            .size = [2]f32{ node.size[0] * 0.5, node.size[1] * 0.5 },
            .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
            .mesh_lod = node.mesh_lod - 1,
            .patch_index = [2]u32{ node.patch_index[0] + patch_index_x, node.patch_index[1] + patch_index_y },
            .heightmap_handle = undefined,
        };

        node.child_indices[child_index] = @intCast(u32, nodes.items.len);
        nodes.appendAssumeCapacity(child_node);

        assert(node.child_indices[child_index] < nodes.items.len);
        divideQuadTreeNode(nodes, &nodes.items[node.child_indices[child_index]]);
    }
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, flecs_world: *flecs.World) !*SystemState {
    // Queries
    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Transform);
    var query_camera = query_builder_camera.buildQuery();

    const invalid_index = std.math.maxInt(u32);
    // TODO(gmodarelli): This is just enough for a single sector, but it's good for testing
    const max_quad_tree_nodes: usize = 85;
    var terrain_quad_tree_nodes = std.ArrayList(QuadTreeNode).initCapacity(allocator, max_quad_tree_nodes) catch unreachable;
    // Root node
    terrain_quad_tree_nodes.appendAssumeCapacity(.{
        .center = [2]f32{ 0.0, 0.0 },
        .size = [2]f32{ 256.0, 256.0 },
        .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
        .mesh_lod = 3,
        .patch_index = [2]u32{ 0, 0 },
        .heightmap_handle = undefined,
    });

    var root_node = &terrain_quad_tree_nodes.items[0];
    divideQuadTreeNode(&terrain_quad_tree_nodes, root_node);
    var quads_to_render = std.ArrayList(u32).init(allocator);

    for (root_node.child_indices) |child_index| {
        var node = &terrain_quad_tree_nodes.items[child_index];
        std.log.debug("Patch index: {}, {}", .{node.patch_index[0], node.patch_index[1]});
        std.log.debug("Center: {}, {}\n", .{node.center[0], node.center[1]});
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_vertices = std.ArrayList(Vertex).init(arena);
    loadResources(allocator, &terrain_quad_tree_nodes, gfxstate, &meshes, &meshes_indices, &meshes_vertices) catch unreachable;

    const total_num_vertices = @intCast(u32, meshes_vertices.items.len);
    const total_num_indices = @intCast(u32, meshes_indices.items.len);

    // Create a vertex buffer.
    var vertex_buffer = gfxstate.createBuffer(.{
        .size = total_num_vertices * @sizeOf(Vertex),
        .state = d3d12.RESOURCE_STATES.GENERIC_READ,
        .name = L("Terrain Quad Tree Vertex Buffer"),
        .persistent = true,
        .has_cbv = false,
        .has_srv = true,
        .has_uav = false,
    }) catch unreachable;

    // Create an index buffer.
    var index_buffer = gfxstate.createBuffer(.{
        .size = total_num_indices * @sizeOf(IndexType),
        .state = .{ .INDEX_BUFFER = true },
        .name = L("Terrain Quad Tree Index Buffer"),
        .persistent = false,
        .has_cbv = false,
        .has_srv = false,
        .has_uav = false,
    }) catch unreachable;

    // Create instance buffers.
    const instance_transform_buffers = blk: {
        var buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle = undefined;
        for (buffers) |_, buffer_index| {
            const bufferDesc = gfx.BufferDesc{
                .size = max_instances * @sizeOf(InstanceTransform),
                .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                .name = L("Terrain Quad Tree Instance Transform Buffer"),
                .persistent = true,
                .has_cbv = false,
                .has_srv = true,
                .has_uav = false,
            };

            buffers[buffer_index] = gfxstate.createBuffer(bufferDesc) catch unreachable;
        }

        break :blk buffers;
    };

    const instance_material_buffers = blk: {
        var buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle = undefined;
        for (buffers) |_, buffer_index| {
            const bufferDesc = gfx.BufferDesc{
                .size = max_instances * @sizeOf(InstanceMaterial),
                .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                .name = L("Terrain Quad Tree Instance Material Buffer"),
                .persistent = true,
                .has_cbv = false,
                .has_srv = true,
                .has_uav = false,
            };

            buffers[buffer_index] = gfxstate.createBuffer(bufferDesc) catch unreachable;
        }

        break :blk buffers;
    };

    var draw_calls = std.ArrayList(DrawCall).init(allocator);
    var instance_transforms = std.ArrayList(InstanceTransform).init(allocator);
    var instance_materials = std.ArrayList(InstanceMaterial).init(allocator);

    gfxstate.scheduleUploadDataToBuffer(Vertex, vertex_buffer, 0, meshes_vertices.items);
    gfxstate.scheduleUploadDataToBuffer(IndexType, index_buffer, 0, meshes_indices.items);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });

    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .sys = sys,
        .gfx = gfxstate,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .instance_transform_buffers = instance_transform_buffers,
        .instance_material_buffers = instance_material_buffers,
        .draw_calls = draw_calls,
        .instance_transforms = instance_transforms,
        .instance_materials = instance_materials,
        .terrain_lod_meshes = meshes,
        .terrain_quad_tree_nodes = terrain_quad_tree_nodes,
        .quads_to_render = quads_to_render,
        .query_camera = query_camera,
    };

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.terrain_lod_meshes.deinit();
    state.instance_transforms.deinit();
    state.instance_materials.deinit();
    state.terrain_quad_tree_nodes.deinit();
    state.quads_to_render.deinit();
    state.draw_calls.deinit();
    state.allocator.destroy(state);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));

    const CameraQueryComps = struct {
        cam: *const fd.Camera,
        transform: *const fd.Transform,
    };
    var camera_comps: ?CameraQueryComps = blk: {
        var entity_iter_camera = state.query_camera.iterator(CameraQueryComps);
        while (entity_iter_camera.next()) |comps| {
            if (comps.cam.active) {
                break :blk comps;
            }
        }

        break :blk null;
    };

    if (camera_comps == null) {
        return;
    }

    const cam = camera_comps.?.cam;
    const cam_world_to_clip = zm.loadMat(cam.world_to_clip[0..]);
    state.gpu_frame_profiler_index = state.gfx.gpu_profiler.startProfile(state.gfx.gctx.cmdlist, "Terrain Quad Tree");

    const pipeline_info = state.gfx.getPipeline(IdLocal.init("terrain_quad_tree"));
    state.gfx.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

    state.gfx.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
    const index_buffer = state.gfx.lookupBuffer(state.index_buffer);
    const index_buffer_resource = state.gfx.gctx.lookupResource(index_buffer.?.resource);
    state.gfx.gctx.cmdlist.IASetIndexBuffer(&.{
        .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
        .SizeInBytes = @intCast(c_uint, index_buffer_resource.?.GetDesc().Width),
        .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
    });

    // Upload per-frame constant data.
    const camera_position = camera_comps.?.transform.getPos00();
    {
        const environment_info = state.flecs_world.getSingletonMut(fd.EnvironmentInfo).?;
        const world_time = environment_info.world_time;
        const mem = state.gfx.gctx.allocateUploadMemory(FrameUniforms, 1);
        mem.cpu_slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
        mem.cpu_slice[0].camera_position = camera_position;
        mem.cpu_slice[0].time = world_time;

        state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
    }

    // Reset transforms, materials and draw calls array list
    state.quads_to_render.clearRetainingCapacity();
    state.instance_transforms.clearRetainingCapacity();
    state.instance_materials.clearRetainingCapacity();
    state.draw_calls.clearRetainingCapacity();

    // Algorithm that walks the quad tree and generates a list quad tree nodes to render
    {
        const lod3_node = &state.terrain_quad_tree_nodes.items[0];
        const camera_point = [2]f32{ camera_position[0], camera_position[2] };

        if (lod3_node.containedInsideChildren(camera_point, &state.terrain_quad_tree_nodes)) {
            var lod2_node_index: u32 = std.math.maxInt(u32);
            for (lod3_node.child_indices) |lod3_child_index| {
                var lod3_child_node = &state.terrain_quad_tree_nodes.items[lod3_child_index];
                if (lod3_child_node.containsPoint(camera_point)) {
                    lod2_node_index = lod3_child_index;
                } else {
                    state.quads_to_render.append(lod3_child_index) catch unreachable;
                }
            }

            if (lod2_node_index != std.math.maxInt(u32)) {
                var lod1_node_index: u32 = std.math.maxInt(u32);
                const lod2_node = &state.terrain_quad_tree_nodes.items[lod2_node_index];
                for (lod2_node.child_indices) |lod2_child_index| {
                    var lod2_child_node = &state.terrain_quad_tree_nodes.items[lod2_child_index];
                    if (lod2_child_node.containsPoint(camera_point)) {
                        lod1_node_index = lod2_child_index;
                    } else {
                        state.quads_to_render.append(lod2_child_index) catch unreachable;
                    }
                }

                if (lod1_node_index != std.math.maxInt(u32)) {
                    // var lod0_node_index: u32 = std.math.maxInt(u32);
                    const lod1_node = &state.terrain_quad_tree_nodes.items[lod1_node_index];
                    for (lod1_node.child_indices) |lod1_child_index| {
                        var lod1_child_node = &state.terrain_quad_tree_nodes.items[lod1_child_index];
                        if (lod1_child_node.containsPoint(camera_point)) {
                            // lod0_node_index = lod1_child_index;
                            state.quads_to_render.appendSlice(lod1_node.child_indices[0..4]) catch unreachable;
                        } else {
                            state.quads_to_render.append(lod1_child_index) catch unreachable;
                        }
                    }
                }
            }
        } else {
            state.quads_to_render.append(0) catch unreachable;
        }
    }

    {
        // TODO: Batch quads together by mesh lod
        var start_instance_location: u32 = 0;
        for (state.quads_to_render.items) |quad_index| {
            const quad = &state.terrain_quad_tree_nodes.items[quad_index];

            const object_to_world = zm.translation(quad.center[0], 0.0, quad.center[1]);
            state.instance_transforms.append(.{ .object_to_world = zm.transpose(object_to_world) }) catch unreachable;
            // TODO: Generate from quad.patch_index
            const texture = state.gfx.lookupTexture(quad.heightmap_handle);
            state.instance_materials.append(.{ .heightmap_index = texture.?.persistent_descriptor.index }) catch unreachable;

            const mesh = state.terrain_lod_meshes.items[quad.mesh_lod];

            state.draw_calls.append(.{
                .mesh_index = 0,
                .index_count = mesh.num_indices,
                .instance_count = 1,
                .index_offset = mesh.index_offset,
                .vertex_offset = mesh.vertex_offset,
                .start_instance_location = start_instance_location,
            }) catch unreachable;

            start_instance_location += 1;
        }
    }

    const frame_index = state.gfx.gctx.frame_index;
    if (state.instance_transforms.items.len > 0) {
        assert(state.instance_transforms.items.len == state.instance_materials.items.len);
        state.gfx.uploadDataToBuffer(InstanceTransform, state.instance_transform_buffers[frame_index], 0, state.instance_transforms.items);
        state.gfx.uploadDataToBuffer(InstanceMaterial, state.instance_material_buffers[frame_index], 0, state.instance_materials.items);
    }

    const vertex_buffer = state.gfx.lookupBuffer(state.vertex_buffer);
    const instance_transform_buffer = state.gfx.lookupBuffer(state.instance_transform_buffers[frame_index]);
    const instance_material_buffer = state.gfx.lookupBuffer(state.instance_material_buffers[frame_index]);

    for (state.draw_calls.items) |draw_call| {
        const mem = state.gfx.gctx.allocateUploadMemory(DrawUniforms, 1);
        mem.cpu_slice[0].start_instance_location = draw_call.start_instance_location;
        mem.cpu_slice[0].vertex_offset = draw_call.vertex_offset;
        mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
        mem.cpu_slice[0].instance_transform_buffer_index = instance_transform_buffer.?.persistent_descriptor.index;
        mem.cpu_slice[0].instance_material_buffer_index = instance_material_buffer.?.persistent_descriptor.index;
        state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

        state.gfx.gctx.cmdlist.DrawIndexedInstanced(
            draw_call.index_count,
            draw_call.instance_count,
            draw_call.index_offset,
            draw_call.vertex_offset,
            draw_call.start_instance_location,
        );
    }

    state.gfx.gpu_profiler.endProfile(state.gfx.gctx.cmdlist, state.gpu_frame_profiler_index, state.gfx.gctx.frame_index);
}
