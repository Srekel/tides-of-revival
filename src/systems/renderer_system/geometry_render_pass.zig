const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
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
    time: f32,
};

pub const ShadowsUniformFrameData = struct {
    projection_view: [16]f32,
    time: f32,
};

pub const WindFrameData = struct {
    world_direction_and_speed: [4]f32,
    flex_noise_scale: f32,
    turbulence: f32,
    gust_speed: f32,
    gust_scale: f32,
    gust_world_scale: f32,
    noise_texture_index: u32,
    gust_texture_index: u32,
};

const InstanceData = struct {
    object_to_world: [16]f32,
    world_to_object: [16]f32,
    materials_buffer_offset: u32,
    _padding: [3]f32,
};

const DrawCallInfo = struct {
    pipeline_id: IdLocal,
    mesh_handle: renderer.MeshHandle,
    sub_mesh_index: u32,
};

const DrawCallInstanced = struct {
    pipeline_id: IdLocal,
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
    prefab_mgr: *PrefabManager,
    query_static_mesh: ecsu.Query,

    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet,

    shadows_uniform_frame_data: ShadowsUniformFrameData,
    shadows_uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    shadows_descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet,

    wind_noise_texture: renderer.TextureHandle,
    wind_gust_texture: renderer.TextureHandle,
    wind_frame_data: WindFrameData,
    wind_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    tree_descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet,
    shadows_tree_descriptor_sets: [max_entity_types][*c]graphics.DescriptorSet,

    gbuffer_instance_data_buffers: [max_entity_types][renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    shadow_caster_instance_data_buffers: [max_entity_types][renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    draw_calls_info: std.ArrayList(DrawCallInfo),

    gbuffer_instance_data: [max_entity_types]std.ArrayList(InstanceData),
    gbuffer_draw_calls: [max_entity_types]std.ArrayList(DrawCallInstanced),
    gbuffer_draw_calls_push_constants: [max_entity_types]std.ArrayList(DrawCallPushConstants),

    shadow_caster_instance_data: [max_entity_types]std.ArrayList(InstanceData),
    shadow_caster_draw_calls: [max_entity_types]std.ArrayList(DrawCallInstanced),
    shadow_caster_draw_calls_push_constants: [max_entity_types]std.ArrayList(DrawCallPushConstants),

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, prefab_mgr: *PrefabManager, allocator: std.mem.Allocator) *GeometryRenderPass {
        const wind_noise_texture = rctx.loadTexture("textures/noise/3d_noise.dds");
        const wind_gust_texture = rctx.loadTexture("textures/noise/gust_noise.dds");

        const wind_frame_data = WindFrameData{
            .world_direction_and_speed = [4]f32{ 0, 0, 1, 20 },
            .flex_noise_scale = 175,
            .turbulence = 0.25,
            .gust_speed = 20,
            .gust_scale = 1.6,
            .gust_world_scale = 600,
            .noise_texture_index = rctx.getTextureBindlessIndex(wind_noise_texture),
            .gust_texture_index = rctx.getTextureBindlessIndex(wind_gust_texture),
        };

        const wind_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(WindFrameData);
            }

            break :blk buffers;
        };

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

        const gbuffer_opaque_instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "GBuffer Instances Opaque");
            }

            break :blk buffers;
        };

        const gbuffer_masked_instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "GBuffer Instances Masked");
            }

            break :blk buffers;
        };

        const shadow_caster_opaque_instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Shadow Caster Instances Opaque");
            }

            break :blk buffers;
        };

        const shadow_caster_masked_instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Shadow Caster Instances Masked");
            }

            break :blk buffers;
        };

        const draw_calls_info = std.ArrayList(DrawCallInfo).init(allocator);

        const gbuffer_instance_data = [max_entity_types]std.ArrayList(InstanceData){ std.ArrayList(InstanceData).init(allocator), std.ArrayList(InstanceData).init(allocator) };
        const gbuffer_draw_calls = [max_entity_types]std.ArrayList(DrawCallInstanced){ std.ArrayList(DrawCallInstanced).init(allocator), std.ArrayList(DrawCallInstanced).init(allocator) };
        const gbuffer_draw_calls_push_constants = [max_entity_types]std.ArrayList(DrawCallPushConstants){ std.ArrayList(DrawCallPushConstants).init(allocator), std.ArrayList(DrawCallPushConstants).init(allocator) };

        const shadow_caster_instance_data = [max_entity_types]std.ArrayList(InstanceData){ std.ArrayList(InstanceData).init(allocator), std.ArrayList(InstanceData).init(allocator) };
        const shadow_caster_draw_calls = [max_entity_types]std.ArrayList(DrawCallInstanced){ std.ArrayList(DrawCallInstanced).init(allocator), std.ArrayList(DrawCallInstanced).init(allocator) };
        const shadow_caster_draw_calls_push_constants = [max_entity_types]std.ArrayList(DrawCallPushConstants){ std.ArrayList(DrawCallPushConstants).init(allocator), std.ArrayList(DrawCallPushConstants).init(allocator) };

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
            .prefab_mgr = prefab_mgr,
            .wind_frame_data = wind_frame_data,
            .wind_frame_buffers = wind_frame_buffers,
            .wind_noise_texture = wind_noise_texture,
            .wind_gust_texture = wind_gust_texture,
            .tree_descriptor_sets = undefined,
            .shadows_tree_descriptor_sets = undefined,
            .shadows_uniform_frame_data = std.mem.zeroes(ShadowsUniformFrameData),
            .shadows_uniform_frame_buffers = shadows_uniform_frame_buffers,
            .shadows_descriptor_sets = undefined,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .descriptor_sets = undefined,
            .gbuffer_instance_data_buffers = .{ gbuffer_masked_instance_data_buffers, gbuffer_opaque_instance_data_buffers },
            .shadow_caster_instance_data_buffers = .{ shadow_caster_masked_instance_data_buffers, shadow_caster_opaque_instance_data_buffers },
            .draw_calls_info = draw_calls_info,
            .gbuffer_instance_data = gbuffer_instance_data,
            .gbuffer_draw_calls = gbuffer_draw_calls,
            .gbuffer_draw_calls_push_constants = gbuffer_draw_calls_push_constants,
            .shadow_caster_instance_data = shadow_caster_instance_data,
            .shadow_caster_draw_calls = shadow_caster_draw_calls,
            .shadow_caster_draw_calls_push_constants = shadow_caster_draw_calls_push_constants,
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

        self.draw_calls_info.deinit();

        self.gbuffer_instance_data[opaque_entities_index].deinit();
        self.gbuffer_instance_data[masked_entities_index].deinit();
        self.gbuffer_draw_calls[opaque_entities_index].deinit();
        self.gbuffer_draw_calls[masked_entities_index].deinit();
        self.gbuffer_draw_calls_push_constants[opaque_entities_index].deinit();
        self.gbuffer_draw_calls_push_constants[masked_entities_index].deinit();

        self.shadow_caster_instance_data[opaque_entities_index].deinit();
        self.shadow_caster_instance_data[masked_entities_index].deinit();
        self.shadow_caster_draw_calls[opaque_entities_index].deinit();
        self.shadow_caster_draw_calls[masked_entities_index].deinit();
        self.shadow_caster_draw_calls_push_constants[opaque_entities_index].deinit();
        self.shadow_caster_draw_calls_push_constants[masked_entities_index].deinit();

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

fn bindMeshBuffers(self: *GeometryRenderPass, mesh: renderer.Mesh, cmd_list: [*c]graphics.Cmd) void {
    const vertex_layout = self.renderer.getVertexLayout(mesh.vertex_layout_id).?;
    const vertex_buffer_count_max = 12; // TODO(gmodarelli): Use MAX_SEMANTICS
    var vertex_buffers: [vertex_buffer_count_max][*c]graphics.Buffer = undefined;

    for (0..vertex_layout.mAttribCount) |attribute_index| {
        const buffer = mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(vertex_layout.mAttribs[attribute_index].mSemantic)]].pBuffer;
        vertex_buffers[attribute_index] = buffer;
    }

    graphics.cmdBindVertexBuffer(cmd_list, vertex_layout.mAttribCount, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
    graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
}

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "GBuffer: Geometry Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));
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
    self.uniform_frame_data.time = self.renderer.time;

    // Update Uniform Frame Buffer
    {
        const data = renderer.Slice{
            .data = @ptrCast(&self.uniform_frame_data),
            .size = @sizeOf(UniformFrameData),
        };
        self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);
    }

    // Update Wind Frame Buffer
    {
        const data = renderer.Slice{
            .data = @ptrCast(&self.wind_frame_data),
            .size = @sizeOf(WindFrameData),
        };
        self.renderer.updateBuffer(data, WindFrameData, self.wind_frame_buffers[frame_index]);
    }

    // Render GBuffer Masked Objects
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Masked Objects", 0x00_ff_ff_00);
        defer trazy_zone1.End();

        cullAndBatchDrawCalls(
            self,
            camera_entity,
            &self.gbuffer_instance_data[masked_entities_index],
            &self.gbuffer_draw_calls[masked_entities_index],
            &self.gbuffer_draw_calls_push_constants[masked_entities_index],
            self.gbuffer_instance_data_buffers[masked_entities_index][frame_index],
            .masked,
            .gbuffer,
        );

        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(self.gbuffer_instance_data[masked_entities_index].items),
            .size = self.gbuffer_instance_data[masked_entities_index].items.len * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data_slice, InstanceData, self.gbuffer_instance_data_buffers[masked_entities_index][frame_index]);

        var pipeline_id: IdLocal = undefined;
        var pipeline: [*c]graphics.Pipeline = undefined;
        var root_signature: [*c]graphics.RootSignature = undefined;
        var root_constant_index: u32 = 0;

        for (self.gbuffer_draw_calls[masked_entities_index].items, 0..) |draw_call, i| {
            if (i == 0) {
                pipeline_id = draw_call.pipeline_id;
                pipeline = self.renderer.getPSO(pipeline_id);
                root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                if (pipeline_id.hash == renderer.masked_pipelines[2].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets[masked_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[masked_entities_index]);
                }

                root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                std.debug.assert(root_constant_index != std.math.maxInt(u32));
            } else {
                if (pipeline_id.hash != draw_call.pipeline_id.hash) {
                    pipeline_id = draw_call.pipeline_id;
                    pipeline = self.renderer.getPSO(pipeline_id);
                    root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    if (pipeline_id.hash == renderer.masked_pipelines[2].hash) {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets[masked_entities_index]);
                    } else {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[masked_entities_index]);
                    }

                    root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                    std.debug.assert(root_constant_index != std.math.maxInt(u32));
                }
            }

            const push_constants = &self.gbuffer_draw_calls_push_constants[masked_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                bindMeshBuffers(self, mesh, cmd_list);

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

    // Render GBuffer Opauqe Objects
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Opaque Objects", 0x00_ff_ff_00);
        defer trazy_zone1.End();

        cullAndBatchDrawCalls(
            self,
            camera_entity,
            &self.gbuffer_instance_data[opaque_entities_index],
            &self.gbuffer_draw_calls[opaque_entities_index],
            &self.gbuffer_draw_calls_push_constants[opaque_entities_index],
            self.gbuffer_instance_data_buffers[opaque_entities_index][frame_index],
            .@"opaque",
            .gbuffer,
        );

        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(self.gbuffer_instance_data[opaque_entities_index].items),
            .size = self.gbuffer_instance_data[opaque_entities_index].items.len * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data_slice, InstanceData, self.gbuffer_instance_data_buffers[opaque_entities_index][frame_index]);

        var pipeline_id: IdLocal = undefined;
        var pipeline: [*c]graphics.Pipeline = undefined;
        var root_signature: [*c]graphics.RootSignature = undefined;
        var root_constant_index: u32 = 0;

        for (self.gbuffer_draw_calls[opaque_entities_index].items, 0..) |draw_call, i| {
            if (i == 0) {
                pipeline_id = draw_call.pipeline_id;
                pipeline = self.renderer.getPSO(pipeline_id);
                root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                if (pipeline_id.hash == renderer.opaque_pipelines[2].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets[opaque_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[opaque_entities_index]);
                }

                root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                std.debug.assert(root_constant_index != std.math.maxInt(u32));
            } else {
                if (pipeline_id.hash != draw_call.pipeline_id.hash) {
                    pipeline_id = draw_call.pipeline_id;
                    pipeline = self.renderer.getPSO(pipeline_id);
                    root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    if (pipeline_id.hash == renderer.opaque_pipelines[2].hash) {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets[opaque_entities_index]);
                    } else {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[opaque_entities_index]);
                    }

                    root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                    std.debug.assert(root_constant_index != std.math.maxInt(u32));
                }
            }

            const push_constants = &self.gbuffer_draw_calls_push_constants[opaque_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                bindMeshBuffers(self, mesh, cmd_list);

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
    self.shadows_uniform_frame_data.time = self.renderer.time;

    const data = renderer.Slice{
        .data = @ptrCast(&self.shadows_uniform_frame_data),
        .size = @sizeOf(ShadowsUniformFrameData),
    };
    self.renderer.updateBuffer(data, ShadowsUniformFrameData, self.shadows_uniform_frame_buffers[frame_index]);

    // Render Shadows Masked Objects
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Masked Objects", 0x00_ff_ff_00);
        defer trazy_zone1.End();

        cullAndBatchDrawCalls(
            self,
            camera_entity,
            &self.shadow_caster_instance_data[masked_entities_index],
            &self.shadow_caster_draw_calls[masked_entities_index],
            &self.shadow_caster_draw_calls_push_constants[masked_entities_index],
            self.shadow_caster_instance_data_buffers[masked_entities_index][frame_index],
            .masked,
            .shadow_caster,
        );

        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(self.shadow_caster_instance_data[masked_entities_index].items),
            .size = self.shadow_caster_instance_data[masked_entities_index].items.len * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data_slice, InstanceData, self.shadow_caster_instance_data_buffers[masked_entities_index][frame_index]);

        var pipeline_id: IdLocal = undefined;
        var pipeline: [*c]graphics.Pipeline = undefined;
        var root_signature: [*c]graphics.RootSignature = undefined;
        var root_constant_index: u32 = 0;

        for (self.shadow_caster_draw_calls[masked_entities_index].items, 0..) |draw_call, i| {
            if (i == 0) {
                pipeline_id = draw_call.pipeline_id;
                pipeline = self.renderer.getPSO(pipeline_id);
                root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                if (pipeline_id.hash == renderer.masked_pipelines[3].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_tree_descriptor_sets[masked_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_sets[masked_entities_index]);
                }

                root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                std.debug.assert(root_constant_index != std.math.maxInt(u32));
            } else {
                if (pipeline_id.hash != draw_call.pipeline_id.hash) {
                    pipeline_id = draw_call.pipeline_id;
                    pipeline = self.renderer.getPSO(pipeline_id);
                    root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    if (pipeline_id.hash == renderer.masked_pipelines[3].hash) {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_tree_descriptor_sets[masked_entities_index]);
                    } else {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_sets[masked_entities_index]);
                    }

                    root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                    std.debug.assert(root_constant_index != std.math.maxInt(u32));
                }
            }

            const push_constants = &self.shadow_caster_draw_calls_push_constants[masked_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                bindMeshBuffers(self, mesh, cmd_list);

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

    // Render Shadows Opauqe Objects
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Opaque Objects", 0x00_ff_ff_00);
        defer trazy_zone1.End();

        cullAndBatchDrawCalls(
            self,
            camera_entity,
            &self.shadow_caster_instance_data[opaque_entities_index],
            &self.shadow_caster_draw_calls[opaque_entities_index],
            &self.shadow_caster_draw_calls_push_constants[opaque_entities_index],
            self.shadow_caster_instance_data_buffers[opaque_entities_index][frame_index],
            .@"opaque",
            .shadow_caster,
        );

        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(self.shadow_caster_instance_data[opaque_entities_index].items),
            .size = self.shadow_caster_instance_data[opaque_entities_index].items.len * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data_slice, InstanceData, self.shadow_caster_instance_data_buffers[opaque_entities_index][frame_index]);

        var pipeline_id: IdLocal = undefined;
        var pipeline: [*c]graphics.Pipeline = undefined;
        var root_signature: [*c]graphics.RootSignature = undefined;
        var root_constant_index: u32 = 0;

        for (self.shadow_caster_draw_calls[opaque_entities_index].items, 0..) |draw_call, i| {
            if (i == 0) {
                pipeline_id = draw_call.pipeline_id;
                pipeline = self.renderer.getPSO(pipeline_id);
                root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                if (pipeline_id.hash == renderer.opaque_pipelines[3].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_tree_descriptor_sets[opaque_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_sets[opaque_entities_index]);
                }

                root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                std.debug.assert(root_constant_index != std.math.maxInt(u32));
            } else {
                if (pipeline_id.hash != draw_call.pipeline_id.hash) {
                    pipeline_id = draw_call.pipeline_id;
                    pipeline = self.renderer.getPSO(pipeline_id);
                    root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    if (pipeline_id.hash == renderer.opaque_pipelines[3].hash) {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_tree_descriptor_sets[opaque_entities_index]);
                    } else {
                        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_sets[opaque_entities_index]);
                    }

                    root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                    std.debug.assert(root_constant_index != std.math.maxInt(u32));
                }
            }

            const push_constants = &self.shadow_caster_draw_calls_push_constants[opaque_entities_index].items[i];
            const mesh = self.renderer.getMesh(draw_call.mesh_handle);

            if (mesh.loaded) {
                bindMeshBuffers(self, mesh, cmd_list);

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

    const shadows_tree_descriptor_sets = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("shadows_tree"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("shadows_tree_masked"));

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
    self.shadows_tree_descriptor_sets = shadows_tree_descriptor_sets;

    const tree_descriptor_sets = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("tree"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("tree_masked"));

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
    self.tree_descriptor_sets = tree_descriptor_sets;

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

    var params: [2]graphics.DescriptorData = undefined;

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

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        var wind_buffer = self.renderer.getBuffer(self.wind_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "cbWind";
        params[1].__union_field3.ppBuffers = @ptrCast(&wind_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.tree_descriptor_sets[opaque_entities_index], 2, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.tree_descriptor_sets[masked_entities_index], 2, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.shadows_uniform_frame_buffers[i]);
        var wind_buffer = self.renderer.getBuffer(self.wind_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "cbWind";
        params[1].__union_field3.ppBuffers = @ptrCast(&wind_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.shadows_tree_descriptor_sets[opaque_entities_index], 2, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.shadows_tree_descriptor_sets[masked_entities_index], 2, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets[masked_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_descriptor_sets[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_descriptor_sets[masked_entities_index]);

    graphics.removeDescriptorSet(self.renderer.renderer, self.tree_descriptor_sets[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.tree_descriptor_sets[masked_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_tree_descriptor_sets[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_tree_descriptor_sets[masked_entities_index]);
}

fn cullAndBatchDrawCalls(
    self: *GeometryRenderPass,
    camera_entity: ecsu.Entity,
    instances: *std.ArrayList(InstanceData),
    draw_calls: *std.ArrayList(DrawCallInstanced),
    draw_calls_push_constants: *std.ArrayList(DrawCallPushConstants),
    instances_buffer: renderer.BufferHandle,
    surface_type: fd.SurfaceType,
    technique: fd.ShadingTechnique,
) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Cull and Batch Draw Calls", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const trazy_zone1 = ztracy.ZoneNC(@src(), "Fetching entities", 0x00_ff_ff_00);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();

    var entity_iterator = self.query_static_mesh.iterator(struct {
        transform: *const fd.Transform,
        mesh: *const fd.StaticMesh,
    });
    trazy_zone1.End();

    {
        const trazy_zone2 = ztracy.ZoneNC(@src(), "Clearing memory", 0x00_ff_ff_00);
        defer trazy_zone2.End();

        instances.clearRetainingCapacity();
        draw_calls.clearRetainingCapacity();
        draw_calls_push_constants.clearRetainingCapacity();

        self.draw_calls_info.clearRetainingCapacity();
    }

    // Iterate over all renderable meshes, perform frustum culling and generate instance transforms and materials
    {
        const trazy_zone2 = ztracy.ZoneNC(@src(), "Collect Instance and Material data", 0x00_ff_ff_00);
        defer trazy_zone2.End();

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
                .pipeline_id = undefined,
                .mesh_handle = comps.mesh.mesh_handle,
                .sub_mesh_index = undefined,
            };

            for (0..sub_mesh_count) |sub_mesh_index| {
                draw_call_info.sub_mesh_index = @intCast(sub_mesh_index);

                const material_handle = comps.mesh.materials[sub_mesh_index];
                const pipeline_ids = self.renderer.getMaterialPipelineIds(material_handle);
                const material_buffer_offset = self.renderer.getMaterialBufferOffset(material_handle);

                draw_call_info.pipeline_id = undefined;

                if (technique == .gbuffer) {
                    if (pipeline_ids.gbuffer_pipeline_id) |p_id| {
                        draw_call_info.pipeline_id = p_id;
                    } else {
                        continue;
                    }
                } else if (technique == .shadow_caster) {
                    if (pipeline_ids.shadow_caster_pipeline_id) |p_id| {
                        draw_call_info.pipeline_id = p_id;
                    } else {
                        continue;
                    }
                }

                var should_parse_submesh = false;

                if (surface_type == .@"opaque") {
                    for (renderer.opaque_pipelines) |pipeline| {
                        if (draw_call_info.pipeline_id.hash == pipeline.hash) {
                            should_parse_submesh = true;
                            break;
                        }
                    }
                } else {
                    for (renderer.masked_pipelines) |pipeline| {
                        if (draw_call_info.pipeline_id.hash == pipeline.hash) {
                            should_parse_submesh = true;
                            break;
                        }
                    }
                }

                if (!should_parse_submesh) {
                    continue;
                }

                self.draw_calls_info.append(draw_call_info) catch unreachable;

                var instance_data: InstanceData = undefined;
                zm.storeMat(&instance_data.object_to_world, z_world);
                zm.storeMat(&instance_data.world_to_object, zm.inverse(z_world));
                instance_data.materials_buffer_offset = material_buffer_offset;
                instance_data._padding = [3]f32{ 42.0, 42.0, 42.0 };
                instances.append(instance_data) catch unreachable;
            }
        }
    }

    if (self.draw_calls_info.items.len == 0) return;

    var start_instance_location: u32 = 0;
    var current_draw_call: DrawCallInstanced = undefined;

    const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(instances_buffer);
    const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.materials_buffer);

    {
        const trazy_zone2 = ztracy.ZoneNC(@src(), "Batch draw calls", 0x00_ff_ff_00);
        defer trazy_zone2.End();

        for (self.draw_calls_info.items, 0..) |draw_call_info, i| {
            if (i == 0) {
                current_draw_call = .{
                    .pipeline_id = draw_call_info.pipeline_id,
                    .mesh_handle = draw_call_info.mesh_handle,
                    .sub_mesh_index = draw_call_info.sub_mesh_index,
                    .instance_count = 1,
                    .start_instance_location = start_instance_location,
                };

                start_instance_location += 1;

                if (i == self.draw_calls_info.items.len - 1) {
                    draw_calls.append(current_draw_call) catch unreachable;
                    draw_calls_push_constants.append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
                continue;
            }

            if (current_draw_call.mesh_handle.id == draw_call_info.mesh_handle.id and current_draw_call.sub_mesh_index == draw_call_info.sub_mesh_index and current_draw_call.pipeline_id.hash == draw_call_info.pipeline_id.hash) {
                current_draw_call.instance_count += 1;
                start_instance_location += 1;

                if (i == self.draw_calls_info.items.len - 1) {
                    draw_calls.append(current_draw_call) catch unreachable;
                    draw_calls_push_constants.append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
            } else {
                draw_calls.append(current_draw_call) catch unreachable;
                draw_calls_push_constants.append(.{
                    .start_instance_location = current_draw_call.start_instance_location,
                    .instance_material_buffer_index = material_buffer_index,
                    .instance_data_buffer_index = instance_data_buffer_index,
                }) catch unreachable;

                current_draw_call = .{
                    .pipeline_id = draw_call_info.pipeline_id,
                    .mesh_handle = draw_call_info.mesh_handle,
                    .sub_mesh_index = draw_call_info.sub_mesh_index,
                    .instance_count = 1,
                    .start_instance_location = start_instance_location,
                };

                start_instance_location += 1;

                if (i == self.draw_calls_info.items.len - 1) {
                    draw_calls.append(current_draw_call) catch unreachable;
                    draw_calls_push_constants.append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
            }
        }
    }
}
