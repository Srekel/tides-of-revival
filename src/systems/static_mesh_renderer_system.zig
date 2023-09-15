const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const gfx = @import("../gfx_d3d12.zig");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const input = @import("../input.zig");

const Vertex = @import("../renderer/renderer_types.zig").Vertex;
const IndexType = @import("../renderer/renderer_types.zig").IndexType;
const Mesh = @import("../renderer/renderer_types.zig").Mesh;

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

const DrawCallInfo = struct {
    mesh_handle: gfx.MeshHandle,
    lod_index: u32,
    sub_mesh_index: u32,
};

const max_instances = 1000000;
const max_instances_per_draw_call = 4096;
const max_draw_distance: f32 = 500.0;

const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: *ecsu.World,
    sys: ecs.entity_t,

    gfx: *gfx.D3D12State,

    instance_transform_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_material_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_transforms: std.ArrayList(InstanceTransform),
    instance_materials: std.ArrayList(InstanceMaterial),
    draw_calls: std.ArrayList(gfx.DrawCall),
    draw_calls_info: std.ArrayList(DrawCallInfo),
    gpu_frame_profiler_index: u64 = undefined,

    query_camera: ecsu.Query,
    query_mesh: ecsu.Query,

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, ecsu_world: *ecsu.World, _: *input.FrameData) !*SystemState {
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
    var draw_calls_info = std.ArrayList(DrawCallInfo).init(allocator);
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
        .withReadonly(fd.StaticMeshComponent);
    var query_camera = query_builder_camera.buildQuery();
    var query_mesh = query_builder_mesh.buildQuery();

    state.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .gfx = gfxstate,
        .instance_transform_buffers = instance_transform_buffers,
        .instance_material_buffers = instance_material_buffers,
        .draw_calls = draw_calls,
        .draw_calls_info = draw_calls_info,
        .instance_transforms = instance_transforms,
        .instance_materials = instance_materials,
        .query_camera = query_camera,
        .query_mesh = query_mesh,
    };

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.query_mesh.deinit();
    state.instance_transforms.deinit();
    state.instance_materials.deinit();
    state.draw_calls.deinit();
    state.draw_calls_info.deinit();
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

    var entity_iter_mesh = state.query_mesh.iterator(struct {
        transform: *const fd.Transform,
        mesh: *const fd.StaticMeshComponent,
    });

    // Reset transforms, materials and draw calls array list
    state.instance_transforms.clearRetainingCapacity();
    state.instance_materials.clearRetainingCapacity();
    state.draw_calls.clearRetainingCapacity();
    state.draw_calls_info.clearRetainingCapacity();

    // Iterate over all renderable meshes, perform frustum culling and generate instance transforms and materials
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
            const lod_index = pickLOD(camera_position, comps.transform.getPos00(), max_draw_distance, mesh.sub_meshes[0].lod_count);

            var draw_call_info = DrawCallInfo{
                .mesh_handle = comps.mesh.mesh_handle,
                .lod_index = lod_index,
                .sub_mesh_index = undefined,
            };

            const invalid_texture_index = std.math.maxInt(u32);
            for (0..mesh.sub_mesh_count) |sub_mesh_index| {
                draw_call_info.sub_mesh_index = @intCast(sub_mesh_index);
                state.draw_calls_info.append(draw_call_info) catch unreachable;

                state.instance_transforms.append(.{
                    .object_to_world = zm.transpose(z_world),
                    .bounding_sphere_matrix = zm.transpose(z_bb_matrix),
                }) catch unreachable;

                var maybe_material = state.gfx.lookUpMaterial(comps.mesh.material_handles[sub_mesh_index]);
                if (maybe_material) |material| {
                    const albedo = blk: {
                        if (state.gfx.lookupTexture(material.albedo)) |albedo| {
                            break :blk albedo.persistent_descriptor.index;
                        } else {
                            break :blk invalid_texture_index;
                        }
                    };

                    const arm = blk: {
                        if (state.gfx.lookupTexture(material.arm)) |arm| {
                            break :blk arm.persistent_descriptor.index;
                        } else {
                            break :blk invalid_texture_index;
                        }
                    };

                    const normal = blk: {
                        if (state.gfx.lookupTexture(material.normal)) |normal| {
                            break :blk normal.persistent_descriptor.index;
                        } else {
                            break :blk invalid_texture_index;
                        }
                    };

                    state.instance_materials.append(.{
                        .albedo_color = [4]f32{ material.base_color.r, material.base_color.g, material.base_color.b, 1.0 },
                        .roughness = material.roughness,
                        .metallic = material.metallic,
                        .normal_intensity = 1.0,
                        .albedo_texture_index = albedo,
                        .emissive_texture_index = invalid_texture_index,
                        .normal_texture_index = normal,
                        .arm_texture_index = arm,
                        .padding = 42,
                    }) catch unreachable;
                } else {
                    state.instance_materials.append(.{
                        .albedo_color = [4]f32{ 1.0, 0.0, 1.0, 1.0 },
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
            }
        }
    }

    var start_instance_location: u32 = 0;
    var current_draw_call: gfx.DrawCall = undefined;

    for (state.draw_calls_info.items, 0..) |draw_call_info, i| {
        if (i == 0) {
            current_draw_call = .{
                .mesh_handle = draw_call_info.mesh_handle,
                .sub_mesh_index = draw_call_info.sub_mesh_index,
                .lod_index = draw_call_info.lod_index,
                .instance_count = 1,
                .start_instance_location = start_instance_location,
            };

            start_instance_location += 1;

            if (i == state.draw_calls_info.items.len - 1) {
                state.draw_calls.append(current_draw_call) catch unreachable;
            }
            continue;
        }

        if (isSameMeshHandle(current_draw_call.mesh_handle, draw_call_info.mesh_handle) and current_draw_call.lod_index == draw_call_info.lod_index and current_draw_call.sub_mesh_index == draw_call_info.sub_mesh_index) {
            current_draw_call.instance_count += 1;
            start_instance_location += 1;

            if (i == state.draw_calls_info.items.len - 1) {
                state.draw_calls.append(current_draw_call) catch unreachable;
            }
        } else {
            state.draw_calls.append(current_draw_call) catch unreachable;

            current_draw_call = .{
                .mesh_handle = draw_call_info.mesh_handle,
                .sub_mesh_index = draw_call_info.sub_mesh_index,
                .lod_index = draw_call_info.lod_index,
                .instance_count = 1,
                .start_instance_location = start_instance_location,
            };

            start_instance_location += 1;

            if (i == state.draw_calls_info.items.len - 1) {
                state.draw_calls.append(current_draw_call) catch unreachable;
            }
        }
    }

    state.gpu_frame_profiler_index = state.gfx.gpu_profiler.startProfile(state.gfx.gctx.cmdlist, "Static Mesh Renderer System");

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
