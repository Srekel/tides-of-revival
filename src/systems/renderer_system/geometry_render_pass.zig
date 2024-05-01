const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const UniformFrameData = struct {
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
};

pub const ShadowsUniformFrameData = struct {
    projection_view: [16]f32,
};

const InstanceData = struct {
    object_to_world: [16]f32,
    materials_buffer_offset: u32,
};

const InstanceMaterial = struct {
    albedo_color: [4]f32,
    roughness: f32,
    metallic: f32,
    normal_intensity: f32,
    emissive_strength: f32,
    albedo_texture_index: u32,
    emissive_texture_index: u32,
    normal_texture_index: u32,
    arm_texture_index: u32,
};

const DrawCallInfo = struct {
    mesh_handle: renderer.MeshHandle,
    sub_mesh_index: u32,
};

const DrawCallInstanced = struct {
    mesh_handle: renderer.MeshHandle,
    sub_mesh_index: u32,
    start_instance_location: u32,
    instance_count: u32,
};

const DrawCallPushConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
    instance_material_buffer_index: u32,
};

const max_instances = 10000;
const max_instances_per_draw_call = 4096;
const max_draw_distance: f32 = 500.0;

const masked_entities_index: u32 = 0;
const opaque_entities_index: u32 = 1;
const max_entity_types: u32 = 2;

pub const GeometryRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    query_static_mesh: ecsu.Query,

    shadows_uniform_frame_data: ShadowsUniformFrameData,
    shadows_uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    shadows_descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet,

    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet,

    instance_data_buffers: [max_entity_types][renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    instance_material_buffers: [max_entity_types][renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    instance_data: [max_entity_types]std.ArrayList(InstanceData),
    instance_materials: [max_entity_types]std.ArrayList(InstanceMaterial),

    draw_calls_info: [max_entity_types]std.ArrayList(DrawCallInfo),
    draw_calls: [max_entity_types]std.ArrayList(DrawCallInstanced),
    draw_calls_push_constants: [max_entity_types]std.ArrayList(DrawCallPushConstants),

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *GeometryRenderPass {
        const shadows_uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ShadowsUniformFrameData);
            }

            break :blk buffers;
        };

        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        const opaque_instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Instance Transform Buffer: Opaque");
            }

            break :blk buffers;
        };

        const masked_instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Instance Transform Buffer: Masked");
            }

            break :blk buffers;
        };

        const opaque_instance_material_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceMaterial),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Instance Material Buffer: Opaque");
            }

            break :blk buffers;
        };

        const masked_instance_material_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceMaterial),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Instance Material Buffer: Masked");
            }

            break :blk buffers;
        };

        const draw_calls = [max_entity_types]std.ArrayList(DrawCallInstanced){ std.ArrayList(DrawCallInstanced).init(allocator), std.ArrayList(DrawCallInstanced).init(allocator) };
        const draw_calls_push_constants = [max_entity_types]std.ArrayList(DrawCallPushConstants){ std.ArrayList(DrawCallPushConstants).init(allocator), std.ArrayList(DrawCallPushConstants).init(allocator) };
        const draw_calls_info = [max_entity_types]std.ArrayList(DrawCallInfo){ std.ArrayList(DrawCallInfo).init(allocator), std.ArrayList(DrawCallInfo).init(allocator) };

        const instance_data = [max_entity_types]std.ArrayList(InstanceData){ std.ArrayList(InstanceData).init(allocator), std.ArrayList(InstanceData).init(allocator) };
        const instance_materials = [max_entity_types]std.ArrayList(InstanceMaterial){ std.ArrayList(InstanceMaterial).init(allocator), std.ArrayList(InstanceMaterial).init(allocator) };

        // Queries
        var query_builder_mesh = ecsu.QueryBuilder.init(ecsu_world);
        _ = query_builder_mesh
            .withReadonly(fd.Transform)
            .withReadonly(fd.StaticMesh);
        const query_static_mesh = query_builder_mesh.buildQuery();

        const pass = allocator.create(GeometryRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .shadows_uniform_frame_data = std.mem.zeroes(ShadowsUniformFrameData),
            .shadows_uniform_frame_buffers = shadows_uniform_frame_buffers,
            .shadows_descriptor_sets = undefined,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .descriptor_sets = undefined,
            .instance_data_buffers = .{ masked_instance_data_buffers, opaque_instance_data_buffers },
            .instance_material_buffers = .{ masked_instance_material_buffers, opaque_instance_material_buffers },
            .draw_calls = draw_calls,
            .draw_calls_push_constants = draw_calls_push_constants,
            .draw_calls_info = draw_calls_info,
            .instance_data = instance_data,
            .instance_materials = instance_materials,
            .query_static_mesh = query_static_mesh,
        };

        createDescriptorSets(@ptrCast(pass));
        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *GeometryRenderPass) void {
        self.query_static_mesh.deinit();

        for (self.descriptor_sets) |descriptor_set| {
            graphics.removeDescriptorSet(self.renderer.renderer, descriptor_set);
        }

        for (self.shadows_descriptor_sets) |descriptor_set| {
            graphics.removeDescriptorSet(self.renderer.renderer, descriptor_set);
        }

        self.instance_data[opaque_entities_index].deinit();
        self.instance_data[masked_entities_index].deinit();
        self.instance_materials[opaque_entities_index].deinit();
        self.instance_materials[masked_entities_index].deinit();
        self.draw_calls[opaque_entities_index].deinit();
        self.draw_calls[masked_entities_index].deinit();
        self.draw_calls_push_constants[opaque_entities_index].deinit();
        self.draw_calls_push_constants[masked_entities_index].deinit();
        self.draw_calls_info[opaque_entities_index].deinit();
        self.draw_calls_info[masked_entities_index].deinit();
        self.allocator.destroy(self);
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

pub const renderFn: renderer.renderPassRenderFn = render;
pub const renderShadowMapFn: renderer.renderPassRenderShadowMapFn = renderShadowMap;
pub const createDescriptorSetsFn: renderer.renderPassCreateDescriptorSetsFn = createDescriptorSets;
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Geometry Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));
    // HACK(gmodarelli): We're not really culling here but only batching. We need to pass
    // a view so we can cull and batch from different views (light or camera)
    // NOTE(gmodarelli): We're skipping this call now because we've already executed it
    // from the renderShadowMap pass. Once we introduce cull by views, we MUST call this again
    // cullStaticMeshes(self);

    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();
    const z_view = zm.loadMat(camera_comps.camera.view[0..]);
    const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
    const z_proj_view = zm.mul(z_view, z_proj);

    zm.storeMat(&self.uniform_frame_data.projection_view, z_proj_view);
    zm.storeMat(&self.uniform_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
    self.uniform_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data),
        .size = @sizeOf(UniformFrameData),
    };
    self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);

    // NOTE(gmodarelli): We're skipping this call now because we've already executed it
    // from the renderShadowMap pass. Once we introduce cull by views, we MUST call this again
    // for (0..max_entity_types) |entity_type_index| {
    //     const instance_data_slice = renderer.Slice{
    //         .data = @ptrCast(self.instance_data[entity_type_index].items),
    //         .size = self.instance_data[entity_type_index].items.len * @sizeOf(InstanceData),
    //     };
    //     self.renderer.updateBuffer(instance_data_slice, InstanceData, self.instance_data_buffers[entity_type_index][frame_index]);

    //     const instance_material_slice = renderer.Slice{
    //         .data = @ptrCast(self.instance_materials[entity_type_index].items),
    //         .size = self.instance_materials[entity_type_index].items.len * @sizeOf(InstanceMaterial),
    //     };
    //     self.renderer.updateBuffer(instance_material_slice, InstanceMaterial, self.instance_material_buffers[entity_type_index][frame_index]);
    // }

    // Render Lit Masked Objects
    {
        const pipeline_id = IdLocal.init("lit_masked");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[masked_entities_index]);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        for (self.draw_calls[masked_entities_index].items, 0..) |draw_call, i| {
            const push_constants = &self.draw_calls_push_constants[masked_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                const vertex_buffers = [_][*c]graphics.Buffer{
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.POSITION)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.NORMAL)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TANGENT)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TEXCOORD0)]].pBuffer,
                };

                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mIndexCount,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartIndex,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mInstanceCount * draw_call.instance_count,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartInstance + draw_call.start_instance_location,
                );
            }
        }
    }

    // Render Lit Objects
    {
        const pipeline_id = IdLocal.init("lit");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[opaque_entities_index]);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        for (self.draw_calls[opaque_entities_index].items, 0..) |draw_call, i| {
            const push_constants = &self.draw_calls_push_constants[opaque_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                const vertex_buffers = [_][*c]graphics.Buffer{
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.POSITION)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.NORMAL)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TANGENT)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TEXCOORD0)]].pBuffer,
                };

                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mIndexCount,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartIndex,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mInstanceCount * draw_call.instance_count,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartInstance + draw_call.start_instance_location,
                );
            }
        }
    }
}

fn renderShadowMap(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Shadow Map: Geometry Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));
    // HACK(gmodarelli): We're not really culling here but only batching. We need to pass
    // a view so we can cull and batch from different views (light or camera)
    cullStaticMeshes(self);

    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();

    const sun_entity = util.getSun(self.ecsu_world);
    const sun_comps = sun_entity.?.getComps(struct {
        rotation: *const fd.Rotation,
        light: *const fd.DirectionalLight,
    });

    const z_forward = zm.rotate(sun_comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 });
    const z_view = zm.lookToLh(
        zm.f32x4(camera_position[0], camera_position[1], camera_position[2], 1.0),
        z_forward * zm.f32x4s(-1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );

    const shadow_range = sun_comps.light.shadow_range;
    const z_proj = zm.orthographicLh(shadow_range, shadow_range, -500.0, 500.0);
    const z_proj_view = zm.mul(z_view, z_proj);
    zm.storeMat(&self.shadows_uniform_frame_data.projection_view, z_proj_view);

    const data = renderer.Slice{
        .data = @ptrCast(&self.shadows_uniform_frame_data),
        .size = @sizeOf(ShadowsUniformFrameData),
    };
    self.renderer.updateBuffer(data, ShadowsUniformFrameData, self.shadows_uniform_frame_buffers[frame_index]);

    for (0..max_entity_types) |entity_type_index| {
        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(self.instance_data[entity_type_index].items),
            .size = self.instance_data[entity_type_index].items.len * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data_slice, InstanceData, self.instance_data_buffers[entity_type_index][frame_index]);

        const instance_material_slice = renderer.Slice{
            .data = @ptrCast(self.instance_materials[entity_type_index].items),
            .size = self.instance_materials[entity_type_index].items.len * @sizeOf(InstanceMaterial),
        };
        self.renderer.updateBuffer(instance_material_slice, InstanceMaterial, self.instance_material_buffers[entity_type_index][frame_index]);
    }

    // Render Shadows Lit Masked Objects
    {
        const pipeline_id = IdLocal.init("shadows_lit_masked");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_sets[masked_entities_index]);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        for (self.draw_calls[masked_entities_index].items, 0..) |draw_call, i| {
            const push_constants = &self.draw_calls_push_constants[masked_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                const vertex_buffers = [_][*c]graphics.Buffer{
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.POSITION)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.NORMAL)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TANGENT)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TEXCOORD0)]].pBuffer,
                };

                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mIndexCount,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartIndex,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mInstanceCount * draw_call.instance_count,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartInstance + draw_call.start_instance_location,
                );
            }
        }
    }

    // Render Lit Objects
    {
        const pipeline_id = IdLocal.init("shadows_lit");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_sets[opaque_entities_index]);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        for (self.draw_calls[opaque_entities_index].items, 0..) |draw_call, i| {
            const push_constants = &self.draw_calls_push_constants[opaque_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                const vertex_buffers = [_][*c]graphics.Buffer{
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.POSITION)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.NORMAL)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TANGENT)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TEXCOORD0)]].pBuffer,
                };

                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mIndexCount,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartIndex,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mInstanceCount * draw_call.instance_count,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[draw_call.sub_mesh_index].mStartInstance + draw_call.start_instance_location,
                );
            }
        }
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    const shadows_descriptor_sets = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("shadows_lit"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("shadows_lit_masked"));

        var descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet = undefined;
        for (descriptor_sets, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == opaque_entities_index) {
                desc.pRootSignature = root_signature_lit;
            } else {
                desc.pRootSignature = root_signature_lit_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets[index]));
        }

        break :blk descriptor_sets;
    };
    self.shadows_descriptor_sets = shadows_descriptor_sets;

    const descriptor_sets = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("lit"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("lit_masked"));

        var descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet = undefined;
        for (descriptor_sets, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == opaque_entities_index) {
                desc.pRootSignature = root_signature_lit;
            } else {
                desc.pRootSignature = root_signature_lit_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets[index]));
        }

        break :blk descriptor_sets;
    };
    self.descriptor_sets = descriptor_sets;
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    var params: [1]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets[opaque_entities_index], 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets[masked_entities_index], 1, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var shadows_uniform_buffer = self.renderer.getBuffer(self.shadows_uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&shadows_uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.shadows_descriptor_sets[opaque_entities_index], 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.shadows_descriptor_sets[masked_entities_index], 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets[masked_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_descriptor_sets[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_descriptor_sets[masked_entities_index]);
}

fn cullStaticMeshes(self: *GeometryRenderPass) void {
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();

    var entity_iterator = self.query_static_mesh.iterator(struct {
        transform: *const fd.Transform,
        mesh: *const fd.StaticMesh,
    });

    // Reset transforms, materials and draw calls array list
    for (0..max_entity_types) |entity_type_index| {
        self.instance_data[entity_type_index].clearRetainingCapacity();
        self.instance_materials[entity_type_index].clearRetainingCapacity();
        self.draw_calls[entity_type_index].clearRetainingCapacity();
        self.draw_calls_push_constants[entity_type_index].clearRetainingCapacity();
        self.draw_calls_info[entity_type_index].clearRetainingCapacity();
    }

    // Iterate over all renderable meshes, perform frustum culling and generate instance transforms and materials
    const loop1 = ztracy.ZoneNC(@src(), "Geometry Render Pass: Culling and Batching", 0x00_ff_ff_00);
    while (entity_iterator.next()) |comps| {
        const sub_mesh_count = self.renderer.getSubMeshCount(comps.mesh.mesh_handle);
        if (sub_mesh_count == 0) continue;

        const z_world_position = zm.loadArr3(comps.transform.getPos00());
        if (zm.lengthSq3(zm.loadArr3(camera_position) - z_world_position)[0] > (max_draw_distance * max_draw_distance)) {
            continue;
        }

        const z_world = zm.loadMat43(comps.transform.matrix[0..]);
        // TODO(gmodarelli): Store bounding boxes into The-Forge mesh's user data
        // const bb_ws = mesh.bounding_box.calculateBoundingBoxCoordinates(z_world);
        // if (!cam.isVisible(bb_ws.center, bb_ws.radius)) {
        //     continue;
        // }

        var draw_call_info = DrawCallInfo{
            .mesh_handle = comps.mesh.mesh_handle,
            .sub_mesh_index = undefined,
        };

        for (0..sub_mesh_count) |sub_mesh_index| {
            draw_call_info.sub_mesh_index = @intCast(sub_mesh_index);

            const material = comps.mesh.materials[sub_mesh_index];
            const entity_type_index = if (material.surface_type == .@"opaque") opaque_entities_index else masked_entities_index;

            const material_buffer_offset = self.instance_materials[entity_type_index].items.len * @sizeOf(InstanceMaterial);

            self.instance_materials[entity_type_index].append(.{
                .albedo_color = [4]f32{ material.base_color.r, material.base_color.g, material.base_color.b, 1.0 },
                .roughness = material.roughness,
                .metallic = material.metallic,
                .normal_intensity = material.normal_intensity,
                .emissive_strength = material.emissive_strength,
                .albedo_texture_index = self.renderer.getTextureBindlessIndex(material.albedo),
                .emissive_texture_index = self.renderer.getTextureBindlessIndex(material.emissive),
                .normal_texture_index = self.renderer.getTextureBindlessIndex(material.normal),
                .arm_texture_index = self.renderer.getTextureBindlessIndex(material.arm),
            }) catch unreachable;

            self.draw_calls_info[entity_type_index].append(draw_call_info) catch unreachable;

            var instance_data: InstanceData = undefined;
            zm.storeMat(&instance_data.object_to_world, z_world);
            instance_data.materials_buffer_offset = @intCast(material_buffer_offset);
            self.instance_data[entity_type_index].append(instance_data) catch unreachable;
        }
    }
    loop1.End();

    const loop2 = ztracy.ZoneNC(@src(), "Geometry Render Pass: Rendering", 0x00_ff_ff_00);
    for (0..max_entity_types) |entity_type_index| {
        var start_instance_location: u32 = 0;
        var current_draw_call: DrawCallInstanced = undefined;

        const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[entity_type_index][frame_index]);
        const instance_material_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_material_buffers[entity_type_index][frame_index]);

        if (self.draw_calls_info[entity_type_index].items.len == 0) continue;

        for (self.draw_calls_info[entity_type_index].items, 0..) |draw_call_info, i| {
            if (i == 0) {
                current_draw_call = .{
                    .mesh_handle = draw_call_info.mesh_handle,
                    .sub_mesh_index = draw_call_info.sub_mesh_index,
                    .instance_count = 1,
                    .start_instance_location = start_instance_location,
                };

                start_instance_location += 1;

                if (i == self.draw_calls_info[entity_type_index].items.len - 1) {
                    self.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                    self.draw_calls_push_constants[entity_type_index].append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = instance_material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
                continue;
            }

            if (current_draw_call.mesh_handle.id == draw_call_info.mesh_handle.id and current_draw_call.sub_mesh_index == draw_call_info.sub_mesh_index) {
                current_draw_call.instance_count += 1;
                start_instance_location += 1;

                if (i == self.draw_calls_info[entity_type_index].items.len - 1) {
                    self.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                    self.draw_calls_push_constants[entity_type_index].append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = instance_material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
            } else {
                self.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                self.draw_calls_push_constants[entity_type_index].append(.{
                    .start_instance_location = current_draw_call.start_instance_location,
                    .instance_material_buffer_index = instance_material_buffer_index,
                    .instance_data_buffer_index = instance_data_buffer_index,
                }) catch unreachable;

                current_draw_call = .{
                    .mesh_handle = draw_call_info.mesh_handle,
                    .sub_mesh_index = draw_call_info.sub_mesh_index,
                    .instance_count = 1,
                    .start_instance_location = start_instance_location,
                };

                start_instance_location += 1;

                if (i == self.draw_calls_info[entity_type_index].items.len - 1) {
                    self.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                    self.draw_calls_push_constants[entity_type_index].append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = instance_material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
            }
        }
    }
    loop2.End();
}
