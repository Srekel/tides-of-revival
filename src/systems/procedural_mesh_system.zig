const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const glfw = @import("glfw");
const zm = @import("zmath");
const zmu = @import("zmathutil");
const zmesh = @import("zmesh");
const flecs = @import("flecs");

const gfx = @import("../gfx_d3d12.zig");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;

const Vertex = @import("../renderer/renderer_types.zig").Vertex;
const IndexType = @import("../renderer/renderer_types.zig").IndexType;
const Mesh = @import("../renderer/renderer_types.zig").Mesh;
const mesh_loader = @import("../renderer/mesh_loader.zig");

const DrawUniforms = struct {
    start_instance_location: u32,
    vertex_offset: i32,
    vertex_buffer_index: u32,
    instance_transform_buffer_index: u32,
    instance_material_buffer_index: u32,
};

const InstanceTransform = struct {
    object_to_world: zm.Mat,
};

const InstanceMaterial = struct {
    albedo_color: [4]f32,
    roughness: f32,
    metallic: f32,
    normal_intensity: f32,
    albedo_texture_index: u32,
    emissive_texture_index: u32,
    normal_texture_index: u32,
    arm_texture_index: u32,
    padding: u32,
};

const max_instances = 1000000;
const max_instances_per_draw_call = 4096;
const max_draw_distance: f32 = 500.0;

const DrawCall = struct {
    mesh_index: u32,
    index_count: u32,
    instance_count: u32,
    index_offset: u32,
    vertex_offset: i32,
    start_instance_location: u32,
};

const ProcMesh = struct {
    // entity: flecs.EntityId,
    id: IdLocal,
    mesh: Mesh,
};

// const SystemInit = struct {
//     arena_state: std.heap.ArenaAllocator,
//     arena_allocator: std.mem.Allocator,

//     meshes: std.ArrayList(Mesh),
//     meshes_indices: std.ArrayList(IndexType),
//     meshes_positions: std.ArrayList([3]f32),
//     meshes_normals: std.ArrayList([3]f32),

//     pub fn init(self: *SystemInit, system_allocator: std.mem.Allocator) void {
//         self.arena_state = std.heap.ArenaAllocator.init(system_allocator);
//         const arena = arena_state.allocator();

//         self.meshes = std.ArrayList(Mesh).init(system_allocator);
//         self.meshes_indices = std.ArrayList(IndexType).init(arena);
//         self.meshes_positions = std.ArrayList([3]f32).init(arena);
//         self.meshes_normals = std.ArrayList([3]f32).init(arena);
//     }

//     pub fn deinit(self: *SystemInit) void {
//         self.arena_state.deinit();
//     }

//     pub fn setupSystem(state: *SystemState) void {}
// };

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    sys: flecs.EntityId,
    // init: SystemInit,

    gfx: *gfx.D3D12State,

    vertex_buffer: gfx.BufferHandle,
    index_buffer: gfx.BufferHandle,
    instance_transform_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_material_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_transforms: std.ArrayList(InstanceTransform),
    instance_materials: std.ArrayList(InstanceMaterial),
    draw_calls: std.ArrayList(DrawCall),
    gpu_frame_profiler_index: u64 = undefined,

    meshes: std.ArrayList(ProcMesh),
    query_camera: flecs.Query,
    query_lights: flecs.Query,
    query_mesh: flecs.Query,

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

fn appendShapeMesh(
    id: IdLocal,
    // entity: flecs.EntityId,
    z_mesh: zmesh.Shape,
    meshes: *std.ArrayList(ProcMesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) u64 {
    var mesh = ProcMesh{
        .id = id,
        // .entity = entity,
        .mesh = .{
            .num_lods = 1,
            .lods = undefined,
            .bounding_box = undefined,
        },
    };

    mesh.mesh.lods[0] = .{
        .index_offset = @intCast(u32, meshes_indices.items.len),
        .index_count = @intCast(u32, z_mesh.indices.len),
        .vertex_offset = @intCast(u32, meshes_vertices.items.len),
        .vertex_count = @intCast(u32, z_mesh.positions.len),
    };

    var min = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var max = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };

    meshes_indices.appendSlice(z_mesh.indices) catch unreachable;
    var i: u64 = 0;
    while (i < z_mesh.positions.len) : (i += 1) {
        min[0] = @min(min[0], z_mesh.positions[i][0]);
        min[1] = @min(min[1], z_mesh.positions[i][1]);
        min[2] = @min(min[2], z_mesh.positions[i][2]);

        max[0] = @max(max[0], z_mesh.positions[i][0]);
        max[1] = @max(max[1], z_mesh.positions[i][1]);
        max[2] = @max(max[2], z_mesh.positions[i][2]);

        meshes_vertices.append(.{
            .position = z_mesh.positions[i],
            .normal = z_mesh.normals.?[i],
            .uv = [2]f32{ 0.0, 0.0 },
            .tangent = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
            .color = [3]f32{ 1.0, 1.0, 1.0 },
        }) catch unreachable;
    }

    mesh.mesh.bounding_box = .{
        .min = min,
        .max = max,
    };
    meshes.append(mesh) catch unreachable;

    return meshes.items.len - 1;
}

fn appendObjMesh(
    allocator: std.mem.Allocator,
    id: IdLocal,
    path: []const u8,
    meshes: *std.ArrayList(ProcMesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) !u64 {
    const mesh = mesh_loader.loadObjMeshFromFile(allocator, path, meshes_indices, meshes_vertices) catch unreachable;

    meshes.append(.{ .id = id, .mesh = mesh }) catch unreachable;

    return meshes.items.len - 1;
}

fn initScene(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(ProcMesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) void {
    {
        var mesh = zmesh.Shape.initParametricSphere(20, 20);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendShapeMesh(IdLocal.init("sphere"), mesh, meshes, meshes_indices, meshes_vertices);
    }

    {
        var mesh = zmesh.Shape.initCube();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        _ = appendShapeMesh(IdLocal.init("cube"), mesh, meshes, meshes_indices, meshes_vertices);
    }

    {
        var mesh = zmesh.Shape.initCylinder(10, 10);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.scale(0.5, 1.0, 0.5);
        mesh.translate(0.0, 1.0, 0.0);

        // Top cap.
        var top = zmesh.Shape.initParametricDisk(10, 2);
        defer top.deinit();
        top.rotate(-math.pi * 0.5, 1.0, 0.0, 0.0);
        top.scale(0.5, 1.0, 0.5);
        top.translate(0.0, 1.0, 0.0);

        // Bottom cap.
        var bottom = zmesh.Shape.initParametricDisk(10, 2);
        defer bottom.deinit();
        bottom.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        bottom.scale(0.5, 1.0, 0.5);
        bottom.translate(0.0, 0.0, 0.0);

        mesh.merge(top);
        mesh.merge(bottom);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendShapeMesh(IdLocal.init("cylinder"), mesh, meshes, meshes_indices, meshes_vertices);
    }

    {
        var mesh = zmesh.Shape.initCylinder(4, 4);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.scale(0.5, 1.0, 0.5);
        mesh.translate(0.0, 1.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendShapeMesh(IdLocal.init("tree_trunk"), mesh, meshes, meshes_indices, meshes_vertices);
    }

    {
        var mesh = zmesh.Shape.initCone(4, 4);
        defer mesh.deinit();
        mesh.rotate(-math.pi * 0.5, 1.0, 0.0, 0.0);
        // mesh.scale(0.5, 1.0, 0.5);
        // mesh.translate(0.0, 1.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendShapeMesh(IdLocal.init("tree_crown"), mesh, meshes, meshes_indices, meshes_vertices);
    }

    _ = appendObjMesh(allocator, IdLocal.init("arrow"), "content/meshes/arrow.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("big_house"), "content/meshes/big_house.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("bow"), "content/meshes/bow.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("long_house"), "content/meshes/long_house.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("medium_house"), "content/meshes/medium_house.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("pine"), "content/meshes/pine.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("small_house_fireplace"), "content/meshes/small_house_fireplace.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("small_house"), "content/meshes/small_house.obj", meshes, meshes_indices, meshes_vertices) catch unreachable;
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, flecs_world: *flecs.World) !*SystemState {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var meshes = std.ArrayList(ProcMesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_vertices = std.ArrayList(Vertex).init(arena);
    initScene(allocator, &meshes, &meshes_indices, &meshes_vertices);

    const total_num_vertices = @intCast(u32, meshes_vertices.items.len);
    const total_num_indices = @intCast(u32, meshes_indices.items.len);

    // Create a vertex buffer.
    var vertex_buffer = gfxstate.createBuffer(.{
        .size = total_num_vertices * @sizeOf(Vertex),
        .state = d3d12.RESOURCE_STATES.GENERIC_READ,
        .name = L("Vertex Buffer"),
        .persistent = true,
        .has_cbv = false,
        .has_srv = true,
        .has_uav = false,
    }) catch unreachable;

    // Create an index buffer.
    var index_buffer = gfxstate.createBuffer(.{
        .size = total_num_indices * @sizeOf(IndexType),
        .state = .{ .INDEX_BUFFER = true },
        .name = L("Index Buffer"),
        .persistent = false,
        .has_cbv = false,
        .has_srv = false,
        .has_uav = false,
    }) catch unreachable;

    // Create instance buffers.
    const instance_transform_buffers = blk: {
        var buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const bufferDesc = gfx.BufferDesc{
                .size = max_instances * @sizeOf(InstanceTransform),
                .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                .name = L("Instance Transform Buffer"),
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
        for (buffers, 0..) |_, buffer_index| {
            const bufferDesc = gfx.BufferDesc{
                .size = max_instances * @sizeOf(InstanceMaterial),
                .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                .name = L("Instance Material Buffer"),
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
    // var sys_post = flecs_world.newWrappedRunSystem(name.toCString(), .post_update, fd.NOCOMP, post_update, .{ .ctx = state });

    // Queries
    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Transform);
    var query_builder_lights = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_lights
        .with(fd.Light)
        .with(fd.Transform);
    var query_builder_mesh = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_mesh
        .withReadonly(fd.Transform)
        .withReadonly(fd.ShapeMeshInstance);
    var query_camera = query_builder_camera.buildQuery();
    var query_lights = query_builder_lights.buildQuery();
    var query_mesh = query_builder_mesh.buildQuery();

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
        .query_lights = query_lights,
        .query_mesh = query_mesh,
    };

    // flecs_world.observer(ShapeMeshDefinitionObserverCallback, .on_set, state);
    flecs_world.observer(ShapeMeshInstanceObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.query_lights.deinit();
    state.query_mesh.deinit();
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
                flecs.c.ecs_iter_fini(entity_iter_camera.iter);
                break :blk comps;
            }
        }

        break :blk null;
    };

    if (camera_comps == null) {
        return;
    }

    const cam = camera_comps.?.cam;
    state.gpu_frame_profiler_index = state.gfx.gpu_profiler.startProfile(state.gfx.gctx.cmdlist, "Procedural System");

    const pipeline_info = state.gfx.getPipeline(IdLocal.init("instanced"));
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
        const mem = state.gfx.gctx.allocateUploadMemory(gfx.FrameUniforms, 1);
        mem.cpu_slice[0].view_projection = zm.transpose(zm.loadMat(cam.view_projection[0..]));
        mem.cpu_slice[0].camera_position = camera_position;
        mem.cpu_slice[0].time = world_time;
        mem.cpu_slice[0].light_count = 0;

        var entity_iter_lights = state.query_lights.iterator(struct {
            light: *fd.Light,
            transform: *fd.Transform,
        });

        var light_i: u32 = 0;
        while (entity_iter_lights.next()) |comps| {
            const light_pos = comps.transform.getPos00();
            std.mem.copy(f32, mem.cpu_slice[0].light_positions[light_i][0..], light_pos[0..]);
            std.mem.copy(f32, mem.cpu_slice[0].light_radiances[light_i][0..3], comps.light.radiance.elemsConst().*[0..]);
            mem.cpu_slice[0].light_radiances[light_i][3] = comps.light.range;
            // std.debug.print("light: {any}{any}\n", .{ light_i, mem.slice[0].light_positions[light_i] });

            light_i += 1;
        }
        mem.cpu_slice[0].light_count = light_i;

        state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
    }

    var entity_iter_mesh = state.query_mesh.iterator(struct {
        transform: *const fd.Transform,
        mesh: *const fd.ShapeMeshInstance,
    });

    // Reset transforms, materials and draw calls array list
    state.instance_transforms.clearRetainingCapacity();
    state.instance_materials.clearRetainingCapacity();
    state.draw_calls.clearRetainingCapacity();

    var instance_count: u32 = 0;
    var start_instance_location: u32 = 0;

    var last_lod_index: u32 = 0;
    var last_mesh_index: u32 = 0xffffffff;
    var last_mesh_index_count: u32 = 0;
    var last_mesh_index_offset: u32 = 0;
    var last_mesh_vertex_offset: i32 = 0;
    var lod_index: u32 = 0;

    while (entity_iter_mesh.next()) |comps| {
        var mesh = &state.meshes.items[comps.mesh.mesh_index].mesh;
        lod_index = pickLOD(camera_position, comps.transform.getPos00(), max_draw_distance, mesh.num_lods);

        if (last_mesh_index == 0xffffffff) {
            last_mesh_index = @intCast(u32, comps.mesh.mesh_index);
            last_lod_index = lod_index;
            last_mesh_index_count = mesh.lods[lod_index].index_count;
            last_mesh_index_offset = mesh.lods[lod_index].index_offset;
            last_mesh_vertex_offset = @intCast(i32, mesh.lods[lod_index].vertex_offset);
        }

        if (last_mesh_index == comps.mesh.mesh_index and lod_index == last_lod_index) {
            if (instance_count < max_instances_per_draw_call) {
                instance_count += 1;
            } else {
                state.draw_calls.append(.{
                    .mesh_index = last_mesh_index,
                    .index_count = last_mesh_index_count,
                    .instance_count = instance_count,
                    .index_offset = last_mesh_index_offset,
                    .vertex_offset = last_mesh_vertex_offset,
                    .start_instance_location = start_instance_location,
                }) catch unreachable;

                start_instance_location += instance_count;
                instance_count = 1;
            }
        } else if (last_mesh_index == comps.mesh.mesh_index and lod_index != last_lod_index) {
            state.draw_calls.append(.{
                .mesh_index = last_mesh_index,
                .index_count = last_mesh_index_count,
                .instance_count = instance_count,
                .index_offset = last_mesh_index_offset,
                .vertex_offset = last_mesh_vertex_offset,
                .start_instance_location = start_instance_location,
            }) catch unreachable;

            start_instance_location += instance_count;
            instance_count = 1;
            last_lod_index = lod_index;
            mesh = &state.meshes.items[comps.mesh.mesh_index].mesh;
            last_mesh_index_count = mesh.lods[lod_index].index_count;
            last_mesh_index_offset = mesh.lods[lod_index].index_offset;
            last_mesh_vertex_offset = @intCast(i32, mesh.lods[lod_index].vertex_offset);
        } else if (last_mesh_index != comps.mesh.mesh_index) {
            state.draw_calls.append(.{
                .mesh_index = last_mesh_index,
                .index_count = last_mesh_index_count,
                .instance_count = instance_count,
                .index_offset = last_mesh_index_offset,
                .vertex_offset = last_mesh_vertex_offset,
                .start_instance_location = start_instance_location,
            }) catch unreachable;

            start_instance_location += instance_count;
            instance_count = 1;

            last_mesh_index = @intCast(u32, comps.mesh.mesh_index);
            mesh = &state.meshes.items[comps.mesh.mesh_index].mesh;
            lod_index = pickLOD(camera_position, comps.transform.getPos00(), max_draw_distance, mesh.num_lods);

            last_lod_index = lod_index;
            last_mesh_index_count = mesh.lods[lod_index].index_count;
            last_mesh_index_offset = mesh.lods[lod_index].index_offset;
            last_mesh_vertex_offset = @intCast(i32, mesh.lods[lod_index].vertex_offset);
        }

        const object_to_world = zm.loadMat43(comps.transform.matrix[0..]);
        const invalid_texture_index = std.math.maxInt(u32);
        state.instance_transforms.append(.{ .object_to_world = zm.transpose(object_to_world) }) catch unreachable;
        state.instance_materials.append(.{
            .albedo_color = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            .roughness = 1.0,
            .metallic = 0.0,
            .normal_intensity = 1.0,
            .albedo_texture_index = invalid_texture_index,
            .emissive_texture_index = invalid_texture_index,
            .normal_texture_index = invalid_texture_index,
            .arm_texture_index = invalid_texture_index,
            .padding = 42,
        }) catch unreachable;
    }

    if (instance_count >= 1) {
        state.draw_calls.append(.{
            .mesh_index = last_mesh_index,
            .index_count = last_mesh_index_count,
            .instance_count = instance_count,
            .index_offset = last_mesh_index_offset,
            .vertex_offset = last_mesh_vertex_offset,
            .start_instance_location = start_instance_location,
        }) catch unreachable;
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

fn pickLOD(camera_position: [3]f32, entity_position: [3]f32, draw_distance: f32, num_lods: u32) u32 {
    if (num_lods == 1) {
        return 0;
    }

    const z_camera_postion = zm.loadArr3(camera_position);
    const z_entity_postion = zm.loadArr3(entity_position);
    const squared_distance: f32 = zm.lengthSq3(z_camera_postion - z_entity_postion)[0];

    const squared_draw_distance = draw_distance * draw_distance;
    const t = squared_distance / squared_draw_distance;

    // TODO(gmodarelli): Store these LODs percentages in the Mesh itself.
    // assert(num_lods == 4);
    if (t <= 0.05) {
        return 0;
    } else if (t <= 0.1) {
        return std.math.min(num_lods - 1, 1);
    } else if (t <= 0.2) {
        return std.math.min(num_lods - 1, 2);
    } else {
        return std.math.min(num_lods - 1, 3);
    }
}

// const ShapeMeshDefinitionObserverCallback = struct {
//     comp: *const fd.CIShapeMeshDefinition,

//     pub const name = "CIShapeMeshDefinition";
//     pub const run = onSetCIShapeMeshDefinition;
// };

const ShapeMeshInstanceObserverCallback = struct {
    comp: *const fd.CIShapeMeshInstance,

    pub const name = "CIShapeMeshInstance";
    pub const run = onSetCIShapeMeshInstance;
};

// fn onSetCIShapeMeshDefinition(it: *flecs.Iterator(ShapeMeshDefinitionObserverCallback)) void {
//     var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
//     var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));

//     while (it.next()) |_| {
//         const ci_ptr = flecs.c.ecs_field_w_size(it.iter, @sizeOf(fd.CIShapeMeshDefinition), @intCast(i32, it.index)).?;
//         var ci = @ptrCast(*fd.CIShapeMeshDefinition, @alignCast(@alignOf(fd.CIShapeMeshDefinition), ci_ptr));

//         const ent = it.entity();
//         const mesh_index = appendMesh(
//             ci.id,
//             ent.id,
//             ci.shape,
//             &state.meshes,
//             &state.meshes_indices,
//             &state.meshes_positions,
//             &state.meshes_normals,
//         );

//         ent.remove(fd.CIShapeMeshDefinition);
//         ent.set(fd.ShapeMeshDefinition{
//             .id = ci.id,
//             .mesh_index = mesh_index,
//         });
//     }
// }

fn onSetCIShapeMeshInstance(it: *flecs.Iterator(ShapeMeshInstanceObserverCallback)) void {
    var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));

    while (it.next()) |_| {
        const ci_ptr = flecs.c.ecs_field_w_size(it.iter, @sizeOf(fd.CIShapeMeshInstance), @intCast(i32, it.index)).?;
        var ci = @ptrCast(*fd.CIShapeMeshInstance, @alignCast(@alignOf(fd.CIShapeMeshInstance), ci_ptr));

        const mesh_index = mesh_blk: {
            for (state.meshes.items, 0..) |mesh, i| {
                if (mesh.id.eqlHash(ci.id)) {
                    break :mesh_blk i;
                }
            }
            unreachable;
        };

        const ent = it.entity();
        ent.remove(fd.CIShapeMeshInstance);
        ent.set(fd.ShapeMeshInstance{
            .mesh_index = mesh_index,
            .basecolor_roughness = ci.basecolor_roughness,
        });
    }
}
