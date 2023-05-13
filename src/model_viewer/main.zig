const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;
const zm = @import("zmath");
const args = @import("args");

const gfx = @import("../gfx_d3d12.zig");
const zwin32 = @import("zwin32");
const zpix = @import("zpix");
const d3d12 = zwin32.d3d12;
const window = @import("../window.zig");

const IdLocal = @import("../variant.zig").IdLocal;

const Vertex = @import("../renderer/renderer_types.zig").Vertex;
const IndexType = @import("../renderer/renderer_types.zig").IndexType;
const Mesh = @import("../renderer/renderer_types.zig").Mesh;
const mesh_loader = @import("../renderer/mesh_loader.zig");
const fd = @import("../flecs_data.zig");

const DrawUniforms = struct {
    start_instance_location: u32,
    vertex_offset: i32,
    vertex_buffer_index: u32,
    instance_transform_buffer_index: u32,
    instance_material_buffer_index: u32,
};

const EnvUniforms = struct {
    object_to_clip: zm.Mat,
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

const max_instances = 100000;
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
    id: IdLocal,
    mesh: Mesh,
};

const ModelViewerState = struct {
    vertex_buffer: gfx.BufferHandle,
    index_buffer: gfx.BufferHandle,
    instance_transform_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_material_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_transforms: std.ArrayList(InstanceTransform),
    instance_materials: std.ArrayList(InstanceMaterial),
    draw_calls: std.ArrayList(DrawCall),

    meshes: std.ArrayList(ProcMesh),

    // TODO(gmodarelli): Place these in a hash so they can be associated to a Material
    // PBR textures
    albedo: gfx.TextureHandle,
    emissive: gfx.TextureHandle,
    normal: gfx.TextureHandle,
    arm: gfx.TextureHandle,
    albedo_color: [4]f32,
    roughness: f32,
    metallic: f32,
    normal_intensity: f32,

    camera: struct {
        position: [3]f32 = .{ 0.0, 0.0, 4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, -1.0 },
        pitch: f32 = 0.0,
        yaw: f32 = 0.0,
    } = .{},
};

pub fn run() !void {
    const allocator = std.heap.page_allocator;

    window.init(allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: Model Viewer") catch unreachable;

    var gfx_state = gfx.init(allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state, allocator);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var meshes = std.ArrayList(ProcMesh).init(allocator);
    defer meshes.deinit();
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_vertices = std.ArrayList(Vertex).init(arena);
    _ = appendObjMesh(allocator, IdLocal.init("cube"), "content/meshes/cube.obj", &meshes, &meshes_indices, &meshes_vertices) catch unreachable;
    _ = appendObjMesh(allocator, IdLocal.init("damaged_helmet"), "content/meshes/damaged_helmet.obj", &meshes, &meshes_indices, &meshes_vertices) catch unreachable;

    const total_num_vertices = @intCast(u32, meshes_vertices.items.len);
    const total_num_indices = @intCast(u32, meshes_indices.items.len);

    // Create a vertex buffer.
    var vertex_buffer = gfx_state.createBuffer(.{
        .size = total_num_vertices * @sizeOf(Vertex),
        .state = d3d12.RESOURCE_STATES.COMMON,
        .name = L("Vertex Buffer"),
        .persistent = true,
        .has_cbv = false,
        .has_srv = true,
        .has_uav = false,
    }) catch unreachable;

    // Create an index buffer.
    var index_buffer = gfx_state.createBuffer(.{
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
                .state = d3d12.RESOURCE_STATES.COMMON,
                .name = L("Instance Transform Buffer"),
                .persistent = true,
                .has_cbv = false,
                .has_srv = true,
                .has_uav = false,
            };

            buffers[buffer_index] = gfx_state.createBuffer(bufferDesc) catch unreachable;
        }

        break :blk buffers;
    };

    const instance_material_buffers = blk: {
        var buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const bufferDesc = gfx.BufferDesc{
                .size = max_instances * @sizeOf(InstanceMaterial),
                .state = d3d12.RESOURCE_STATES.COMMON,
                .name = L("Instance Material Buffer"),
                .persistent = true,
                .has_cbv = false,
                .has_srv = true,
                .has_uav = false,
            };

            buffers[buffer_index] = gfx_state.createBuffer(bufferDesc) catch unreachable;
        }

        break :blk buffers;
    };

    var draw_calls = std.ArrayList(DrawCall).init(allocator);
    defer draw_calls.deinit();
    var instance_transforms = std.ArrayList(InstanceTransform).init(allocator);
    defer instance_transforms.deinit();
    var instance_materials = std.ArrayList(InstanceMaterial).init(allocator);
    defer instance_materials.deinit();

    gfx_state.scheduleUploadDataToBuffer(Vertex, vertex_buffer, 0, meshes_vertices.items);
    gfx_state.scheduleUploadDataToBuffer(IndexType, index_buffer, 0, meshes_indices.items);

    gfx_state.gctx.beginFrame();

    const albedo_texture_handle = blk: {
        const resource_handle = try gfx_state.gctx.createAndUploadTex2dFromDdsFile("content/textures/damaged_helmet_albedo.dds", arena, .{});
        const resource = gfx_state.gctx.lookupResource(resource_handle);
        _ = resource.?.SetName(L("damaged_helmet_albedo.dds"));

        const srv_allocation = gfx_state.gctx.allocatePersistentGpuDescriptors(1);
        gfx_state.gctx.device.CreateShaderResourceView(
            resource.?,
            null,
            srv_allocation.cpu_handle,
        );

        gfx_state.gctx.addTransitionBarrier(resource_handle, .{ .PIXEL_SHADER_RESOURCE = true });
        gfx_state.gctx.flushResourceBarriers();

        const texture = gfx.Texture{
            .resource = resource.?,
            .persistent_descriptor = srv_allocation,
        };

        break :blk gfx_state.texture_pool.addTexture(texture);
    };

    const emissive_texture_handle = blk: {
        const resource_handle = try gfx_state.gctx.createAndUploadTex2dFromDdsFile("content/textures/damaged_helmet_emissive.dds", arena, .{});
        const resource = gfx_state.gctx.lookupResource(resource_handle);
        _ = resource.?.SetName(L("damaged_helmet_emissive.dds"));

        const srv_allocation = gfx_state.gctx.allocatePersistentGpuDescriptors(1);
        gfx_state.gctx.device.CreateShaderResourceView(
            resource.?,
            null,
            srv_allocation.cpu_handle,
        );

        gfx_state.gctx.addTransitionBarrier(resource_handle, .{ .PIXEL_SHADER_RESOURCE = true });
        gfx_state.gctx.flushResourceBarriers();

        const texture = gfx.Texture{
            .resource = resource.?,
            .persistent_descriptor = srv_allocation,
        };

        break :blk gfx_state.texture_pool.addTexture(texture);
    };

    const normal_texture_handle = blk: {
        const resource_handle = try gfx_state.gctx.createAndUploadTex2dFromDdsFile("content/textures/damaged_helmet_normal.dds", arena, .{});
        const resource = gfx_state.gctx.lookupResource(resource_handle);
        _ = resource.?.SetName(L("damaged_helmet_normal.dds"));

        const srv_allocation = gfx_state.gctx.allocatePersistentGpuDescriptors(1);
        gfx_state.gctx.device.CreateShaderResourceView(
            resource.?,
            null,
            srv_allocation.cpu_handle,
        );

        gfx_state.gctx.addTransitionBarrier(resource_handle, .{ .PIXEL_SHADER_RESOURCE = true });
        gfx_state.gctx.flushResourceBarriers();

        const texture = gfx.Texture{
            .resource = resource.?,
            .persistent_descriptor = srv_allocation,
        };

        break :blk gfx_state.texture_pool.addTexture(texture);
    };

    const arm_texture_handle = blk: {
        const resource_handle = try gfx_state.gctx.createAndUploadTex2dFromDdsFile("content/textures/damaged_helmet_arm.dds", arena, .{});
        const resource = gfx_state.gctx.lookupResource(resource_handle);
        _ = resource.?.SetName(L("damaged_helmet_arm.dds"));

        const srv_allocation = gfx_state.gctx.allocatePersistentGpuDescriptors(1);
        gfx_state.gctx.device.CreateShaderResourceView(
            resource.?,
            null,
            srv_allocation.cpu_handle,
        );

        gfx_state.gctx.addTransitionBarrier(resource_handle, .{ .PIXEL_SHADER_RESOURCE = true });
        gfx_state.gctx.flushResourceBarriers();

        const texture = gfx.Texture{
            .resource = resource.?,
            .persistent_descriptor = srv_allocation,
        };

        break :blk gfx_state.texture_pool.addTexture(texture);
    };

    gfx_state.gctx.endFrame();
    gfx_state.gctx.finishGpuCommands();

    var model_viewer_state = ModelViewerState{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .instance_transform_buffers = instance_transform_buffers,
        .instance_material_buffers = instance_material_buffers,
        .instance_transforms = instance_transforms,
        .instance_materials = instance_materials,
        .draw_calls = draw_calls,
        .meshes = meshes,
        .albedo = albedo_texture_handle,
        .emissive = emissive_texture_handle,
        .normal = normal_texture_handle,
        .arm = arm_texture_handle,
        .albedo_color = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
        .roughness = 1.0,
        .metallic = 1.0,
        .normal_intensity = 1.0,
    };

    while (true) {
        const window_status = window.update(&gfx_state) catch unreachable;
        if (window_status == .no_windows) {
            break;
        }

        // if (input_frame_data.just_pressed(config.input_exit)) {
        //     break;
        // }

        // world_patch_mgr.tickOne();
        update(&model_viewer_state);
        render(&gfx_state, &model_viewer_state);
    }
}

fn update(model_viewer_state: *ModelViewerState) void {
    _ = model_viewer_state;
}

fn render(gfx_state: *gfx.D3D12State, model_viewer_state: *ModelViewerState) void {
    const stats = gfx_state.stats;

    // Camera
    const framebuffer_width = gfx_state.gctx.viewport_width;
    const framebuffer_height = gfx_state.gctx.viewport_height;
    const camera_position = model_viewer_state.camera.position;
    var z_forward = zm.loadArr3(model_viewer_state.camera.forward);
    var z_pos = zm.loadArr3(camera_position);

    var z_view = zm.lookToLh(
        z_pos,
        z_forward,
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );

    const z_projection =
        zm.perspectiveFovLh(
        0.25 * math.pi,
        @intToFloat(f32, framebuffer_width) / @intToFloat(f32, framebuffer_height),
        0.01,
        100.0,
    );

    const z_view_projection = zm.mul(z_view, z_projection);
    const z_view_projection_inverted = zm.inverse(z_view_projection);
    const ibl_textures = gfx_state.lookupIBLTextures();

    // Start rendering the frame
    gfx.beginFrame(gfx_state);

    zpix.beginEvent(gfx_state.gctx.cmdlist, "Instanced Objects");
    // Draw static objects
    {
        const pipeline_info = gfx_state.getPipeline(IdLocal.init("instanced"));
        gfx_state.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

        gfx_state.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
        const index_buffer = gfx_state.lookupBuffer(model_viewer_state.index_buffer);
        const index_buffer_resource = gfx_state.gctx.lookupResource(index_buffer.?.resource);
        gfx_state.gctx.cmdlist.IASetIndexBuffer(&.{
            .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
            .SizeInBytes = @intCast(c_uint, index_buffer_resource.?.GetDesc().Width),
            .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
        });

        // Upload per-scene constant data.
        {
            const mem = gfx_state.gctx.allocateUploadMemory(gfx.SceneUniforms, 1);
            mem.cpu_slice[0].irradiance_texture_index = ibl_textures.irradiance.?.persistent_descriptor.index;
            mem.cpu_slice[0].specular_texture_index = ibl_textures.specular.?.persistent_descriptor.index;
            mem.cpu_slice[0].brdf_integration_texture_index = ibl_textures.brdf.?.persistent_descriptor.index;
            gfx_state.gctx.cmdlist.SetGraphicsRootConstantBufferView(2, mem.gpu_base);
        }

        // Upload per-frame constant data.
        {
            const mem = gfx_state.gctx.allocateUploadMemory(gfx.FrameUniforms, 1);
            mem.cpu_slice[0].view_projection = zm.transpose(z_view_projection);
            mem.cpu_slice[0].view_projection_inverted = zm.transpose(z_view_projection_inverted);
            mem.cpu_slice[0].camera_position = camera_position;
            mem.cpu_slice[0].time = 0;
            mem.cpu_slice[0].light_count = 0;

            gfx_state.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
        }

        // Reset transforms, materials and draw calls array list
        model_viewer_state.instance_transforms.clearRetainingCapacity();
        model_viewer_state.instance_materials.clearRetainingCapacity();
        model_viewer_state.draw_calls.clearRetainingCapacity();

        // Helmet
        {
            const helmet_mesh_index: u32 = 1;
            var mesh = &model_viewer_state.meshes.items[helmet_mesh_index].mesh;
            const lod_index: u32 = 0;

            model_viewer_state.draw_calls.append(.{
                .mesh_index = helmet_mesh_index,
                .index_count = mesh.lods[lod_index].index_count,
                .instance_count = 1,
                .index_offset = mesh.lods[lod_index].index_offset,
                .vertex_offset = @intCast(i32, mesh.lods[lod_index].vertex_offset),
                .start_instance_location = 0,
            }) catch unreachable;

            const albedo = gfx_state.lookupTexture(model_viewer_state.albedo);
            const emissive = gfx_state.lookupTexture(model_viewer_state.emissive);
            const normal = gfx_state.lookupTexture(model_viewer_state.normal);
            const arm = gfx_state.lookupTexture(model_viewer_state.arm);

            const object_to_world = zm.rotationY(@floatCast(f32, 0.25 * stats.time));
            model_viewer_state.instance_transforms.append(.{ .object_to_world = zm.transpose(object_to_world) }) catch unreachable;
            model_viewer_state.instance_materials.append(.{
                .albedo_color = model_viewer_state.albedo_color,
                .roughness = model_viewer_state.roughness,
                .metallic = model_viewer_state.metallic,
                .normal_intensity = model_viewer_state.normal_intensity,
                .albedo_texture_index = albedo.?.persistent_descriptor.index,
                .emissive_texture_index = emissive.?.persistent_descriptor.index,
                .normal_texture_index = normal.?.persistent_descriptor.index,
                .arm_texture_index = arm.?.persistent_descriptor.index,
                .padding = 42,
            }) catch unreachable;
        }

        const frame_index = gfx_state.gctx.frame_index;
        gfx_state.uploadDataToBuffer(InstanceTransform, model_viewer_state.instance_transform_buffers[frame_index], 0, model_viewer_state.instance_transforms.items);
        gfx_state.uploadDataToBuffer(InstanceMaterial, model_viewer_state.instance_material_buffers[frame_index], 0, model_viewer_state.instance_materials.items);

        const vertex_buffer = gfx_state.lookupBuffer(model_viewer_state.vertex_buffer);
        const instance_transform_buffer = gfx_state.lookupBuffer(model_viewer_state.instance_transform_buffers[frame_index]);
        const instance_material_buffer = gfx_state.lookupBuffer(model_viewer_state.instance_material_buffers[frame_index]);

        for (model_viewer_state.draw_calls.items) |draw_call| {
            const mem = gfx_state.gctx.allocateUploadMemory(DrawUniforms, 1);
            mem.cpu_slice[0].start_instance_location = draw_call.start_instance_location;
            mem.cpu_slice[0].vertex_offset = draw_call.vertex_offset;
            mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
            mem.cpu_slice[0].instance_transform_buffer_index = instance_transform_buffer.?.persistent_descriptor.index;
            mem.cpu_slice[0].instance_material_buffer_index = instance_material_buffer.?.persistent_descriptor.index;
            gfx_state.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

            gfx_state.gctx.cmdlist.DrawIndexedInstanced(
                draw_call.index_count,
                draw_call.instance_count,
                draw_call.index_offset,
                draw_call.vertex_offset,
                draw_call.start_instance_location,
            );
        }
    }
    zpix.endEvent(gfx_state.gctx.cmdlist);

    zpix.beginEvent(gfx_state.gctx.cmdlist, "Skybox");
    {
        const pipeline_info = gfx_state.getPipeline(IdLocal.init("skybox"));
        gfx_state.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

        gfx_state.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
        const index_buffer = gfx_state.lookupBuffer(model_viewer_state.index_buffer);
        const index_buffer_resource = gfx_state.gctx.lookupResource(index_buffer.?.resource);
        gfx_state.gctx.cmdlist.IASetIndexBuffer(&.{
            .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
            .SizeInBytes = @intCast(c_uint, index_buffer_resource.?.GetDesc().Width),
            .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
        });

        z_view[3] = zm.f32x4(0.0, 0.0, 0.0, 1.0);

        {
            const mem = gfx_state.gctx.allocateUploadMemory(EnvUniforms, 1);
            mem.cpu_slice[0].object_to_clip = zm.transpose(zm.mul(z_view, z_projection));

            gfx_state.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
        }

        const vertex_buffer = gfx_state.lookupBuffer(model_viewer_state.vertex_buffer);

        const cube_mesh_index: u32 = 0;
        var mesh = &model_viewer_state.meshes.items[cube_mesh_index].mesh;
        const lod_index: u32 = 0;

        {
            const mem = gfx_state.gctx.allocateUploadMemory(DrawUniforms, 1);
            mem.cpu_slice[0].start_instance_location = 0;
            mem.cpu_slice[0].vertex_offset = @intCast(i32, mesh.lods[lod_index].vertex_offset);
            mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
            mem.cpu_slice[0].instance_transform_buffer_index = 0;
            mem.cpu_slice[0].instance_material_buffer_index = 0;
            gfx_state.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
        }

        gfx_state.gctx.cmdlist.DrawIndexedInstanced(
            mesh.lods[lod_index].index_count,
            1,
            mesh.lods[lod_index].index_offset,
            @intCast(i32, mesh.lods[lod_index].vertex_offset),
            0,
        );
    }

    var view: [16]f32 = undefined;
    zm.storeMat(view[0..], z_view);

    var projection: [16]f32 = undefined;
    zm.storeMat(projection[0..], z_projection);

    var view_projection: [16]f32 = undefined;
    zm.storeMat(view_projection[0..], z_view_projection);

    const camera = fd.Camera{
        .near = 0.01,
        .far = 100.0,
        .view = view,
        .projection = projection,
        .view_projection = view_projection,
        .window = undefined,
        .active = true,
        .class = 0,
    };

    gfx.endFrame(gfx_state, &camera, camera_position);
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
