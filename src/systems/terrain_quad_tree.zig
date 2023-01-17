const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const glfw = @import("glfw");
const zm = @import("zmath");
const zmu = @import("zmathutil");
const flecs = @import("flecs");

const gfx = @import("../gfx_d3d12.zig");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const IndexType = u32;

const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
    time: f32,
    padding1: u32,
    padding2: u32,
    padding3: u32,
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
    uv: [2]f32,
};

const InstanceTransform = struct {
    object_to_world: zm.Mat,
};

const InstanceMaterial = struct {
    basecolor_roughness: [4]f32,
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

    meshes: std.ArrayList(Mesh),
    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

fn initScene(
    _: std.mem.Allocator,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) !void {
    // Load the LOD5 obj
    var file = std.fs.cwd().openFile("content/meshes/LOD5.obj", .{}) catch |err| {
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

    var buf: [1024]u8 = undefined;
    var vertex_offset = meshes_vertices.items.len;

    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = std.mem.split(u8, line, " ");

        var first = it.first();
        if (std.mem.eql(u8, first, "v")) {
            var vertex: Vertex = undefined;
            vertex.position[0] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            vertex.position[1] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            vertex.position[2] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            meshes_vertices.append(vertex) catch unreachable;
        } else if (std.mem.eql(u8, first, "vt")) { // NOTE: This only works with this mesh. We need to fix this
            var vertex = &meshes_vertices.items[vertex_offset];
            vertex.uv[0] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            vertex.uv[1] = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
            vertex_offset += 1;
        } else if (std.mem.eql(u8, first, "f")) {
            var triangle_index: u32 = 0;
            while (triangle_index < 3) : (triangle_index += 1) {
                var triangles_iterator = std.mem.split(u8, it.next().?, "/");

                // NOTE: we're assuming position and uvs are aligned
                var index = std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10) catch unreachable;
                index -= 1;
                meshes_indices.append(index) catch unreachable;
            }
        }
    }

    assert(vertex_offset == meshes_vertices.items.len);
    mesh.num_indices = @intCast(u32, meshes_indices.items.len);
    mesh.num_vertices = @intCast(u32, meshes_vertices.items.len);
    meshes.append(mesh) catch unreachable;
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, flecs_world: *flecs.World) !*SystemState {
    // Queries
    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Transform);
    var query_camera = query_builder_camera.buildQuery();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_vertices = std.ArrayList(Vertex).init(arena);
    initScene(allocator, &meshes, &meshes_indices, &meshes_vertices) catch unreachable;

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
        .meshes = meshes,
        .query_camera = query_camera,
    };

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.meshes.deinit();
    state.instance_transforms.deinit();
    state.instance_materials.deinit();
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
    state.instance_transforms.clearRetainingCapacity();
    state.instance_materials.clearRetainingCapacity();
    state.draw_calls.clearRetainingCapacity();

    // Test single instance
    {
        const mesh = state.meshes.items[0];
        state.draw_calls.append(.{
            .mesh_index = 0,
            .index_count = mesh.num_indices,
            .instance_count = 1,
            .index_offset = mesh.index_offset,
            .vertex_offset = mesh.vertex_offset,
            .start_instance_location = 0,
        }) catch unreachable;

        const object_to_world = zm.translation(0.0, 50.0, 0.0);
        state.instance_transforms.append(.{ .object_to_world = zm.transpose(object_to_world) }) catch unreachable;
        state.instance_materials.append(.{ .basecolor_roughness = [4]f32{ 0.2, 0.8, 0.4, 0.5, } }) catch unreachable;
    }

    const frame_index = state.gfx.gctx.frame_index;
    state.gfx.uploadDataToBuffer(InstanceTransform, state.instance_transform_buffers[frame_index], 0, state.instance_transforms.items);
    state.gfx.uploadDataToBuffer(InstanceMaterial, state.instance_material_buffers[frame_index], 0, state.instance_materials.items);

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
