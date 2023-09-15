const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const zmesh = @import("zmesh");
const ecs = @import("zflecs");

const gfx = @import("../gfx_d3d12.zig");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const input = @import("../input.zig");
const config = @import("../config.zig");

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
    bounding_sphere_matrix: zm.Mat,
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

const ProcMesh = struct {
    id: IdLocal,
    mesh: Mesh,
};

const IdLocalToMeshHandle = struct {
    id: IdLocal,
    mesh_handle: gfx.MeshHandle,
};

const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    sys: ecs.entity_t,

    gfx: *gfx.D3D12State,

    instance_transform_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_material_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_transforms: std.ArrayList(InstanceTransform),
    instance_materials: std.ArrayList(InstanceMaterial),
    draw_calls: std.ArrayList(gfx.DrawCall),
    draw_bounding_spheres: bool,
    gpu_frame_profiler_index: u64 = undefined,

    meshes: std.ArrayList(IdLocalToMeshHandle),
    query_camera: ecsu.Query,
    query_mesh: ecsu.Query,

    freeze_rendering: bool,
    frame_data: *input.FrameData,

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

fn appendShapeMesh(
    name: [:0]const u8,
    allocator: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    id: IdLocal,
    z_mesh: zmesh.Shape,
    meshes: *std.ArrayList(IdLocalToMeshHandle),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var vertices = std.ArrayList(Vertex).init(arena);
    defer vertices.deinit();

    // TODO(gmodarelli): use a different Mesh struct here since we're not interested in vertex and index buffers
    var mesh = Mesh{
        .vertex_buffer = undefined,
        .index_buffer = undefined,
        .sub_mesh_count = 1,
        .sub_meshes = undefined,
        .bounding_box = undefined,
    };

    mesh.sub_meshes[0] = .{
        .lod_count = 1,
        .lods = undefined,
        .bounding_box = undefined,
    };

    var min = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var max = [3]f32{ std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32) };

    var i: u64 = 0;
    while (i < z_mesh.positions.len) : (i += 1) {
        min[0] = @min(min[0], z_mesh.positions[i][0]);
        min[1] = @min(min[1], z_mesh.positions[i][1]);
        min[2] = @min(min[2], z_mesh.positions[i][2]);

        max[0] = @max(max[0], z_mesh.positions[i][0]);
        max[1] = @max(max[1], z_mesh.positions[i][1]);
        max[2] = @max(max[2], z_mesh.positions[i][2]);

        vertices.append(.{
            .position = z_mesh.positions[i],
            .normal = z_mesh.normals.?[i],
            .uv = [2]f32{ 0.0, 0.0 },
            .tangent = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
            .color = [3]f32{ 1.0, 1.0, 1.0 },
        }) catch unreachable;
    }

    mesh.sub_meshes[0].lods[0] = .{
        .index_offset = 0,
        .index_count = @as(u32, @intCast(z_mesh.indices.len)),
        .vertex_offset = 0,
        .vertex_count = @as(u32, @intCast(vertices.items.len)),
    };

    mesh.sub_meshes[0].bounding_box = .{
        .min = min,
        .max = max,
    };

    mesh.bounding_box = .{
        .min = min,
        .max = max,
    };

    const mesh_handle = gfxstate.uploadMeshData(name, mesh, vertices.items, z_mesh.indices) catch unreachable;

    meshes.append(.{ .id = id, .mesh_handle = mesh_handle }) catch unreachable;
}

fn appendObjMesh(
    name: [:0]const u8,
    allocator: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    id: IdLocal,
    path: []const u8,
    meshes: *std.ArrayList(IdLocalToMeshHandle),
) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var indices = std.ArrayList(IndexType).init(arena);
    var vertices = std.ArrayList(Vertex).init(arena);
    defer indices.deinit();
    defer vertices.deinit();

    const mesh = mesh_loader.loadObjMeshFromFile(allocator, path, &indices, &vertices) catch unreachable;
    const mesh_handle = gfxstate.uploadMeshData(name, mesh, vertices.items, indices.items) catch unreachable;

    meshes.append(.{ .id = id, .mesh_handle = mesh_handle }) catch unreachable;
}

fn initScene(
    allocator: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    meshes: *std.ArrayList(IdLocalToMeshHandle),
) void {
    {
        var mesh = zmesh.Shape.initParametricSphere(20, 20);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        appendShapeMesh("procedural_sphere", allocator, gfxstate, IdLocal.init("sphere"), mesh, meshes);
    }

    {
        var mesh = zmesh.Shape.initCube();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        appendShapeMesh("procedural_cube", allocator, gfxstate, IdLocal.init("cube"), mesh, meshes);
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

        appendShapeMesh("procedural_cylinder", allocator, gfxstate, IdLocal.init("cylinder"), mesh, meshes);
    }

    appendObjMesh("big_house", allocator, gfxstate, IdLocal.init("big_house"), "content/meshes/big_house.obj", meshes) catch unreachable;
    appendObjMesh("long_house", allocator, gfxstate, IdLocal.init("long_house"), "content/meshes/long_house.obj", meshes) catch unreachable;
    appendObjMesh("medium_house", allocator, gfxstate, IdLocal.init("medium_house"), "content/meshes/medium_house.obj", meshes) catch unreachable;
    appendObjMesh("pine", allocator, gfxstate, IdLocal.init("pine"), "content/meshes/pine.obj", meshes) catch unreachable;
    appendObjMesh("small_house_fireplace", allocator, gfxstate, IdLocal.init("small_house_fireplace"), "content/meshes/small_house_fireplace.obj", meshes) catch unreachable;
    appendObjMesh("small_house", allocator, gfxstate, IdLocal.init("small_house"), "content/meshes/small_house.obj", meshes) catch unreachable;
    appendObjMesh("unit_sphere_lp", allocator, gfxstate, IdLocal.init("unit_sphere_lp"), "content/meshes/unit_sphere_lp.obj", meshes) catch unreachable;
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, ecsu_world: *ecsu.World, frame_data: *input.FrameData) !*SystemState {
    var meshes = std.ArrayList(IdLocalToMeshHandle).init(allocator);
    initScene(allocator, gfxstate, &meshes);

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

    var draw_calls = std.ArrayList(gfx.DrawCall).init(allocator);
    var instance_transforms = std.ArrayList(InstanceTransform).init(allocator);
    var instance_materials = std.ArrayList(InstanceMaterial).init(allocator);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = state });
    // var sys_post = ecsu_world.newWrappedRunSystem(name.toCString(), .post_update, fd.NOCOMP, post_update, .{ .ctx = state });

    // Queries
    var query_builder_camera = ecsu.QueryBuilder.init(ecsu_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Transform);
    var query_builder_mesh = ecsu.QueryBuilder.init(ecsu_world.*);
    _ = query_builder_mesh
        .withReadonly(fd.Transform)
        .withReadonly(fd.StaticMesh);
    var query_camera = query_builder_camera.buildQuery();
    var query_mesh = query_builder_mesh.buildQuery();

    state.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world.*,
        .sys = sys,
        .gfx = gfxstate,
        .instance_transform_buffers = instance_transform_buffers,
        .instance_material_buffers = instance_material_buffers,
        .draw_calls = draw_calls,
        .instance_transforms = instance_transforms,
        .instance_materials = instance_materials,
        .meshes = meshes,
        .query_camera = query_camera,
        .query_mesh = query_mesh,
        .freeze_rendering = false,
        .draw_bounding_spheres = false,
        .frame_data = frame_data,
    };

    ecsu_world.observer(StaticMeshObserverCallback, ecs.OnSet, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
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

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    var state: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    const CameraQueryComps = struct {
        cam: *const fd.Camera,
        transform: *const fd.Transform,
    };
    var camera_comps: ?CameraQueryComps = blk: {
        var entity_iter_camera = state.query_camera.iterator(CameraQueryComps);
        while (entity_iter_camera.next()) |comps| {
            if (comps.cam.active) {
                ecs.iter_fini(entity_iter_camera.iter);
                break :blk comps;
            }
        }

        break :blk null;
    };

    if (camera_comps == null) {
        return;
    }

    const cam = camera_comps.?.cam;
    const camera_position = camera_comps.?.transform.getPos00();

    // NOTE(gmodarelli): Testing a frustum culling implementation directly in this system
    // since it's the one we generate the most draw calls from. I'll move it to the camera
    // once I know it works
    if (state.frame_data.just_pressed(config.input_camera_freeze_rendering)) {
        state.freeze_rendering = !state.freeze_rendering;
    }

    if (state.frame_data.just_pressed(config.input_draw_bounding_spheres)) {
        state.draw_bounding_spheres = !state.draw_bounding_spheres;
    }

    var entity_iter_mesh = state.query_mesh.iterator(struct {
        transform: *const fd.Transform,
        mesh: *const fd.StaticMesh,
    });

    // Reset transforms, materials and draw calls array list
    state.instance_transforms.clearRetainingCapacity();
    state.instance_materials.clearRetainingCapacity();
    state.draw_calls.clearRetainingCapacity();

    var instance_count: u32 = 0;
    var start_instance_location: u32 = 0;

    var last_lod_index: u32 = 0;
    var last_mesh_handle: gfx.MeshHandle = undefined;
    var lod_index: u32 = 0;
    var first_iteration = true;

    while (entity_iter_mesh.next()) |comps| {
        var maybe_mesh = state.gfx.lookupMesh(comps.mesh.mesh_handle);

        if (maybe_mesh) |mesh| {
            const z_world = zm.loadMat43(comps.transform.matrix[0..]);

            const bb_ws = mesh.bounding_box.calculateBoundingBoxCoordinates(z_world);
            if (!cam.isVisible(bb_ws.center, bb_ws.radius)) {
                continue;
            }

            // Build bounding sphere matrix for debugging purpouses
            const z_bb_matrix = zm.mul(zm.scaling(bb_ws.radius, bb_ws.radius, bb_ws.radius), zm.translation(bb_ws.center[0], bb_ws.center[1], bb_ws.center[2]));

            // NOTE(gmodarelli): We're assuming all sub-meshes have the same number of LODs (which makes sense)
            lod_index = pickLOD(camera_position, comps.transform.getPos00(), max_draw_distance, mesh.sub_meshes[0].lod_count);

            if (first_iteration) {
                last_mesh_handle = comps.mesh.mesh_handle;
                last_lod_index = lod_index;
                first_iteration = false;
            }

            if (isSameMeshHandle(last_mesh_handle, comps.mesh.mesh_handle) and lod_index == last_lod_index) {
                if (instance_count < max_instances_per_draw_call) {
                    instance_count += 1;
                } else {
                    state.draw_calls.append(.{
                        .mesh_handle = comps.mesh.mesh_handle,
                        .sub_mesh_index = 0,
                        .lod_index = lod_index,
                        .instance_count = instance_count,
                        .start_instance_location = start_instance_location,
                    }) catch unreachable;

                    start_instance_location += instance_count;
                    instance_count = 1;
                }
            } else if (isSameMeshHandle(last_mesh_handle, comps.mesh.mesh_handle) and lod_index != last_lod_index) {
                state.draw_calls.append(.{
                    .mesh_handle = last_mesh_handle,
                    .sub_mesh_index = 0,
                    .lod_index = last_lod_index,
                    .instance_count = instance_count,
                    .start_instance_location = start_instance_location,
                }) catch unreachable;

                start_instance_location += instance_count;
                instance_count = 1;
                last_lod_index = lod_index;
            } else if (!isSameMeshHandle(last_mesh_handle, comps.mesh.mesh_handle)) {
                state.draw_calls.append(.{
                    .mesh_handle = last_mesh_handle,
                    .sub_mesh_index = 0,
                    .lod_index = last_lod_index,
                    .instance_count = instance_count,
                    .start_instance_location = start_instance_location,
                }) catch unreachable;

                start_instance_location += instance_count;
                instance_count = 1;

                last_mesh_handle = comps.mesh.mesh_handle;
                lod_index = pickLOD(camera_position, comps.transform.getPos00(), max_draw_distance, mesh.sub_meshes[0].lod_count);

                last_lod_index = lod_index;
            }

            const invalid_texture_index = std.math.maxInt(u32);
            state.instance_transforms.append(.{
                .object_to_world = zm.transpose(z_world),
                .bounding_sphere_matrix = zm.transpose(z_bb_matrix),
            }) catch unreachable;
            const material = comps.mesh.material;
            state.instance_materials.append(.{
                .albedo_color = [4]f32{ material.base_color.r, material.base_color.g, material.base_color.b, 1.0 },
                .roughness = material.roughness,
                .metallic = material.metallic,
                .normal_intensity = 1.0,
                .albedo_texture_index = invalid_texture_index,
                .emissive_texture_index = invalid_texture_index,
                .normal_texture_index = invalid_texture_index,
                .arm_texture_index = invalid_texture_index,
                .padding = 42,
            }) catch unreachable;
        }
    }

    if (instance_count >= 1) {
        state.draw_calls.append(.{
            .mesh_handle = last_mesh_handle,
            .sub_mesh_index = 0,
            .lod_index = last_lod_index,
            .instance_count = instance_count,
            .start_instance_location = start_instance_location,
        }) catch unreachable;
    }

    state.gpu_frame_profiler_index = state.gfx.gpu_profiler.startProfile(state.gfx.gctx.cmdlist, "Procedural System");

    if (state.draw_calls.items.len > 0) {
        const pipeline_info = state.gfx.getPipeline(IdLocal.init("instanced"));
        state.gfx.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

        // Upload per-frame constant data.
        const z_view_projection = zm.loadMat(cam.view_projection[0..]);
        const z_view_projection_inverted = zm.inverse(z_view_projection);
        {
            const mem = state.gfx.gctx.allocateUploadMemory(gfx.FrameUniforms, 1);
            mem.cpu_slice[0].view_projection = zm.transpose(z_view_projection);
            mem.cpu_slice[0].view_projection_inverted = zm.transpose(z_view_projection_inverted);
            mem.cpu_slice[0].camera_position = camera_position;

            state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
        }

        const frame_index = state.gfx.gctx.frame_index;
        _ = state.gfx.uploadDataToBuffer(InstanceTransform, state.instance_transform_buffers[frame_index], 0, state.instance_transforms.items);
        _ = state.gfx.uploadDataToBuffer(InstanceMaterial, state.instance_material_buffers[frame_index], 0, state.instance_materials.items);

        const instance_transform_buffer = state.gfx.lookupBuffer(state.instance_transform_buffers[frame_index]);
        const instance_material_buffer = state.gfx.lookupBuffer(state.instance_material_buffers[frame_index]);

        for (state.draw_calls.items) |draw_call| {
            var maybe_mesh = state.gfx.lookupMesh(draw_call.mesh_handle);

            if (maybe_mesh) |mesh| {
                state.gfx.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
                const index_buffer = state.gfx.lookupBuffer(mesh.index_buffer);
                const index_buffer_resource = state.gfx.gctx.lookupResource(index_buffer.?.resource);
                state.gfx.gctx.cmdlist.IASetIndexBuffer(&.{
                    .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
                    .SizeInBytes = @as(c_uint, @intCast(index_buffer_resource.?.GetDesc().Width)),
                    .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
                });

                const vertex_buffer = state.gfx.lookupBuffer(mesh.vertex_buffer);
                const mesh_lod = mesh.sub_meshes[draw_call.sub_mesh_index].lods[draw_call.lod_index];
                const mem = state.gfx.gctx.allocateUploadMemory(DrawUniforms, 1);
                mem.cpu_slice[0].start_instance_location = draw_call.start_instance_location;
                mem.cpu_slice[0].vertex_offset = @as(i32, @intCast(mesh_lod.vertex_offset));
                mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
                mem.cpu_slice[0].instance_transform_buffer_index = instance_transform_buffer.?.persistent_descriptor.index;
                mem.cpu_slice[0].instance_material_buffer_index = instance_material_buffer.?.persistent_descriptor.index;
                state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

                state.gfx.gctx.cmdlist.DrawIndexedInstanced(
                    mesh_lod.index_count,
                    draw_call.instance_count,
                    mesh_lod.index_offset,
                    @as(i32, @intCast(mesh_lod.vertex_offset)),
                    draw_call.start_instance_location,
                );
            }
        }
    }

    if (state.draw_bounding_spheres and state.draw_calls.items.len > 0) {
        const pipeline_info = state.gfx.getPipeline(IdLocal.init("frustum_debug"));
        state.gfx.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

        // Upload per-frame constant data.
        const z_view_projection = zm.loadMat(cam.view_projection[0..]);
        const z_view_projection_inverted = zm.inverse(z_view_projection);
        {
            const mem = state.gfx.gctx.allocateUploadMemory(gfx.FrameUniforms, 1);
            mem.cpu_slice[0].view_projection = zm.transpose(z_view_projection);
            mem.cpu_slice[0].view_projection_inverted = zm.transpose(z_view_projection_inverted);
            mem.cpu_slice[0].camera_position = camera_position;

            state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
        }

        const frame_index = state.gfx.gctx.frame_index;

        const instance_transform_buffer = state.gfx.lookupBuffer(state.instance_transform_buffers[frame_index]);
        const instance_material_buffer = state.gfx.lookupBuffer(state.instance_material_buffers[frame_index]);

        var mesh_handle = state.gfx.findMeshByName("procedural_sphere");
        var maybe_mesh = state.gfx.lookupMesh(mesh_handle.?);
        if (maybe_mesh) |mesh| {
            for (state.draw_calls.items) |draw_call| {
                state.gfx.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
                const index_buffer = state.gfx.lookupBuffer(mesh.index_buffer);
                const index_buffer_resource = state.gfx.gctx.lookupResource(index_buffer.?.resource);
                state.gfx.gctx.cmdlist.IASetIndexBuffer(&.{
                    .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
                    .SizeInBytes = @as(c_uint, @intCast(index_buffer_resource.?.GetDesc().Width)),
                    .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
                });

                const vertex_buffer = state.gfx.lookupBuffer(mesh.vertex_buffer);
                const mesh_lod = mesh.sub_meshes[0].lods[0];
                const mem = state.gfx.gctx.allocateUploadMemory(DrawUniforms, 1);
                mem.cpu_slice[0].start_instance_location = draw_call.start_instance_location;
                mem.cpu_slice[0].vertex_offset = @as(i32, @intCast(mesh_lod.vertex_offset));
                mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
                mem.cpu_slice[0].instance_transform_buffer_index = instance_transform_buffer.?.persistent_descriptor.index;
                mem.cpu_slice[0].instance_material_buffer_index = instance_material_buffer.?.persistent_descriptor.index;
                state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

                state.gfx.gctx.cmdlist.DrawIndexedInstanced(
                    mesh_lod.index_count,
                    draw_call.instance_count,
                    mesh_lod.index_offset,
                    @as(i32, @intCast(mesh_lod.vertex_offset)),
                    draw_call.start_instance_location,
                );
            }
        }
    }

    state.gfx.gpu_profiler.endProfile(state.gfx.gctx.cmdlist, state.gpu_frame_profiler_index, state.gfx.gctx.frame_index);
}

fn pickLOD(camera_position: [3]f32, entity_position: [3]f32, draw_distance: f32, lod_count: u32) u32 {
    if (lod_count == 1) {
        return 0;
    }

    const z_camera_postion = zm.loadArr3(camera_position);
    const z_entity_postion = zm.loadArr3(entity_position);
    const squared_distance: f32 = zm.lengthSq3(z_camera_postion - z_entity_postion)[0];

    const squared_draw_distance = draw_distance * draw_distance;
    const t = squared_distance / squared_draw_distance;

    // TODO(gmodarelli): Store these LODs percentages in the Mesh itself.
    // assert(lod_count == 4);
    if (t <= 0.05) {
        return 0;
    } else if (t <= 0.1) {
        return @min(lod_count - 1, 1);
    } else if (t <= 0.2) {
        return @min(lod_count - 1, 2);
    } else {
        return @min(lod_count - 1, 3);
    }
}

fn isSameMeshHandle(a: gfx.MeshHandle, b: gfx.MeshHandle) bool {
    return a.index() == b.index() and a.cycle() == b.cycle();
}

const StaticMeshObserverCallback = struct {
    comp: *const fd.CIStaticMesh,

    pub const name = "CIStaticMesh";
    pub const run = onSetCIStaticMesh;
};

fn onSetCIStaticMesh(it: *ecsu.Iterator(StaticMeshObserverCallback)) void {
    var observer: *ecs.observer_t = @ptrCast(@alignCast(it.iter.ctx));
    var state: *SystemState = @ptrCast(@alignCast(observer.*.ctx));

    while (it.next()) |_| {
        const ci_ptr = ecs.field_w_size(it.iter, @sizeOf(fd.CIStaticMesh), @as(i32, @intCast(it.index))).?;
        var ci: *fd.CIStaticMesh = @ptrCast(@alignCast(ci_ptr));

        const mesh_handle = mesh_blk: {
            for (state.meshes.items) |mesh| {
                if (mesh.id.eqlHash(ci.id)) {
                    break :mesh_blk mesh.mesh_handle;
                }
            }
            unreachable;
        };

        const ent = ecsu.Entity.init(it.world().world, it.entity());
        ent.remove(fd.CIStaticMesh);
        ent.set(fd.StaticMesh{
            .mesh_handle = mesh_handle,
            .material = ci.material,
        });
    }
}
