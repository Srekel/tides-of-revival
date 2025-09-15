const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const renderer_types = @import("../../renderer/types.zig");
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;
const InstanceData = renderer_types.InstanceData;
const InstanceRootConstants = renderer_types.InstanceRootConstants;

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

const Batch = struct {
    instances: std.ArrayList(InstanceData),
    start_instance_location: u32,
};

const BatchKey = struct {
    material_handle: renderer.MaterialHandle,
    mesh_handle: renderer.LegacyMeshHandle,
    sub_mesh_index: u32,
    surface_type: fd.SurfaceType,
};

const BatchMap = std.AutoHashMap(BatchKey, Batch);

const max_instances = 100000;
const max_draw_distance: f32 = 20000.0;

const cutout_entities_index: u32 = 0;
const opaque_entities_index: u32 = 1;
const max_entity_types: u32 = 2;

pub const GeometryRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    prefab_mgr: *PrefabManager,
    query_static_mesh: *ecs.query_t,

    uniform_frame_data_gbuffer: UniformFrameData,
    uniform_frame_buffers_gbuffer: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet,

    uniform_frame_data_shadow_caster: ShadowsUniformFrameData,
    uniform_frame_buffers_shadow_caster: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    descriptor_sets_shadow_caster: [max_entity_types][*c]graphics.DescriptorSet,

    wind_noise_texture: renderer.TextureHandle,
    wind_gust_texture: renderer.TextureHandle,
    wind_frame_data: WindFrameData,
    wind_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    tree_descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet,
    tree_descriptor_sets_shadow_caster: [max_entity_types][*c]graphics.DescriptorSet,

    batches: BatchMap,
    instances: std.ArrayList(InstanceData),
    instance_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    pub fn init(self: *GeometryRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, prefab_mgr: *PrefabManager, allocator: std.mem.Allocator) void {
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

        const uniform_frame_buffers_gbuffer = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        const uniform_frame_buffers_shadow_caster = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ShadowsUniformFrameData);
            }

            break :blk buffers;
        };

        const instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, false, "Instances");
            }

            break :blk buffers;
        };

        const instances = std.ArrayList(InstanceData).init(allocator);

        // Queries
        const query_static_mesh = ecs.query_init(ecsu_world.world, &.{
            .entity = ecs.new_entity(ecsu_world.world, "query_static_mesh"),
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(fd.LodGroup), .inout = .In },
                .{ .id = ecs.id(fd.Transform), .inout = .In },
                .{ .id = ecs.id(fd.Scale), .inout = .In },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 3),
        }) catch unreachable;

        const batches = BatchMap.init(allocator);

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .prefab_mgr = prefab_mgr,
            .wind_frame_data = wind_frame_data,
            .wind_frame_buffers = wind_frame_buffers,
            .wind_noise_texture = wind_noise_texture,
            .wind_gust_texture = wind_gust_texture,
            .tree_descriptor_sets_gbuffer = undefined,
            .tree_descriptor_sets_shadow_caster = undefined,
            .uniform_frame_data_shadow_caster = std.mem.zeroes(ShadowsUniformFrameData),
            .uniform_frame_buffers_shadow_caster = uniform_frame_buffers_shadow_caster,
            .descriptor_sets_gbuffer = undefined,
            .descriptor_sets_shadow_caster = undefined,
            .uniform_frame_data_gbuffer = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers_gbuffer = uniform_frame_buffers_gbuffer,
            .instance_buffers = instance_data_buffers,
            .batches = batches,
            .instances = instances,
            .query_static_mesh = query_static_mesh,
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_gbuffer_pass_fn = renderGBuffer,
            .render_shadow_pass_fn = renderShadowMap,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *GeometryRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);

        unloadDescriptorSets(@ptrCast(self));

        {
            var batch_keys_iterator = self.batches.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = self.batches.getPtr(batch_key.*).?;
                batch.start_instance_location = 0;
                batch.instances.deinit();
            }
            self.batches.deinit();
        }

        self.instances.deinit();
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

fn bindMeshBuffers(self: *GeometryRenderPass, mesh: renderer.LegacyMesh, cmd_list: [*c]graphics.Cmd) void {
    const vertex_layout = self.renderer.getVertexLayout(mesh.vertex_layout_id).?;
    const vertex_buffer_count_max = 12; // TODO(gmodarelli): Use MAX_SEMANTICS
    var vertex_buffers: [vertex_buffer_count_max][*c]graphics.Buffer = undefined;

    for (0..vertex_layout.mAttribCount) |attribute_index| {
        const buffer = mesh.geometry.*.__union_field1.__struct_field1.pVertexBuffers[mesh.buffer_layout_desc.mSemanticBindings[@intCast(vertex_layout.mAttribs[attribute_index].mSemantic.bits)]];
        vertex_buffers[attribute_index] = buffer;
    }

    graphics.cmdBindVertexBuffer(cmd_list, vertex_layout.mAttribCount, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
    graphics.cmdBindIndexBuffer(cmd_list, mesh.geometry.*.__union_field1.__struct_field1.pIndexBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
}

fn renderGBuffer(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "GBuffer: Geometry Render Pass", 0x00_ff_00_00);
    defer trazy_zone.End();

    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();
    const z_proj_view = zm.loadMat(camera_comps.camera.view_projection[0..]);

    zm.storeMat(&self.uniform_frame_data_gbuffer.projection_view, z_proj_view);
    zm.storeMat(&self.uniform_frame_data_gbuffer.projection_view_inverted, zm.inverse(z_proj_view));
    self.uniform_frame_data_gbuffer.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
    self.uniform_frame_data_gbuffer.time = @floatCast(self.renderer.time); // keep f64?

    // Update Uniform Frame Buffer
    {
        const data = renderer.Slice{
            .data = @ptrCast(&self.uniform_frame_data_gbuffer),
            .size = @sizeOf(UniformFrameData),
        };
        self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers_gbuffer[frame_index]);
    }

    // Update Wind Frame Buffer
    {
        const data = renderer.Slice{
            .data = @ptrCast(&self.wind_frame_data),
            .size = @sizeOf(WindFrameData),
        };
        self.renderer.updateBuffer(data, 0, WindFrameData, self.wind_frame_buffers[frame_index]);
    }

    // Render Cutout Objects
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Cutout Objects", 0x00_ff_00_00);
        defer trazy_zone1.End();

        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Render Batches", 0x00_ff_00_00);
            defer trazy_zone2.End();

            const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index]);
            const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.materials_buffer);

            var batch_keys_iterator = self.batches.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                if (batch_key.surface_type != .cutout) {
                    continue;
                }

                const batch = self.batches.getPtr(batch_key.*).?;
                if (batch.instances.items.len == 0) {
                    continue;
                }

                const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_handle);
                const pipeline_id = pipeline_ids.gbuffer_pipeline_id.?;
                const pipeline = self.renderer.getPSO(pipeline_id);
                const root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);

                if (pipeline_id.hash == renderer.cutout_pipelines[2].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets_gbuffer[cutout_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_gbuffer[cutout_entities_index]);
                }

                const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                const push_constants = InstanceRootConstants{
                    .start_instance_location = batch.start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
                    .instance_material_buffer_index = material_buffer_index,
                };

                const mesh = self.renderer.getLegacyMesh(batch_key.mesh_handle);
                const sub_mesh_index = batch_key.sub_mesh_index;

                if (mesh.loaded) {
                    bindMeshBuffers(self, mesh, cmd_list);

                    graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                    graphics.cmdDrawIndexedInstanced(
                        cmd_list,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mIndexCount,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartIndex,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mInstanceCount * @as(u32, @intCast(batch.instances.items.len)),
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mVertexOffset,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartInstance + batch.start_instance_location,
                    );
                }
            }
        }
    }

    // Render Opaque Objects
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Opaque Objects", 0x00_ff_00_00);
        defer trazy_zone1.End();

        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Render Batches", 0x00_ff_00_00);
            defer trazy_zone2.End();

            const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index]);
            const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.materials_buffer);

            var batch_keys_iterator = self.batches.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                if (batch_key.surface_type != .@"opaque") {
                    continue;
                }

                const batch = self.batches.getPtr(batch_key.*).?;
                if (batch.instances.items.len == 0) {
                    continue;
                }

                const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_handle);
                const pipeline_id = pipeline_ids.gbuffer_pipeline_id.?;
                const pipeline = self.renderer.getPSO(pipeline_id);
                const root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);

                if (pipeline_id.hash == renderer.opaque_pipelines[2].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets_gbuffer[opaque_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_gbuffer[opaque_entities_index]);
                }

                const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                const push_constants = InstanceRootConstants{
                    .start_instance_location = batch.start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
                    .instance_material_buffer_index = material_buffer_index,
                };

                const mesh = self.renderer.getLegacyMesh(batch_key.mesh_handle);
                const sub_mesh_index = batch_key.sub_mesh_index;

                if (mesh.loaded) {
                    bindMeshBuffers(self, mesh, cmd_list);

                    graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                    graphics.cmdDrawIndexedInstanced(
                        cmd_list,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mIndexCount,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartIndex,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mInstanceCount * @as(u32, @intCast(batch.instances.items.len)),
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mVertexOffset,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartInstance + batch.start_instance_location,
                    );
                }
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
    zm.storeMat(&self.uniform_frame_data_shadow_caster.projection_view, z_proj_view);
    self.uniform_frame_data_shadow_caster.time = @floatCast(self.renderer.time);

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data_shadow_caster),
        .size = @sizeOf(ShadowsUniformFrameData),
    };
    self.renderer.updateBuffer(data, 0, ShadowsUniformFrameData, self.uniform_frame_buffers_shadow_caster[frame_index]);

    // TODO: Move this out of the renderShadowMap and into an "update" function
    {
        batchEntities(self, camera_entity, &self.batches);
        self.instances.clearRetainingCapacity();

        var batch_keys_iterator = self.batches.keyIterator();
        var start_instance_location: u32 = 0;
        while (batch_keys_iterator.next()) |batch_key| {
            const batch = self.batches.getPtr(batch_key.*).?;
            batch.start_instance_location = start_instance_location;
            start_instance_location += @intCast(batch.instances.items.len);

            const index = self.instances.items.len;
            self.instances.insertSlice(index, batch.instances.items) catch unreachable;
        }

        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Upload instance data", 0x00_ff_ff_00);
            defer trazy_zone2.End();

            const instance_data_slice = renderer.Slice{
                .data = @ptrCast(self.instances.items),
                .size = self.instances.items.len * @sizeOf(InstanceData),
            };
            self.renderer.updateBuffer(instance_data_slice, 0, InstanceData, self.instance_buffers[frame_index]);
        }
    }

    // Render Cutout Shadow Casters
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Cutout Objects", 0x00_ff_ff_00);
        defer trazy_zone1.End();

        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Render Batches", 0x00_ff_ff_00);
            defer trazy_zone2.End();

            const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index]);
            const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.materials_buffer);

            var batch_keys_iterator = self.batches.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                if (batch_key.surface_type != .cutout) {
                    continue;
                }

                const batch = self.batches.getPtr(batch_key.*).?;
                if (batch.instances.items.len == 0) {
                    continue;
                }

                const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_handle);
                const pipeline_id = pipeline_ids.shadow_caster_pipeline_id.?;
                const pipeline = self.renderer.getPSO(pipeline_id);
                const root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);

                if (pipeline_id.hash == renderer.cutout_pipelines[3].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets_shadow_caster[cutout_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_shadow_caster[cutout_entities_index]);
                }

                const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                const push_constants = InstanceRootConstants{
                    .start_instance_location = batch.start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
                    .instance_material_buffer_index = material_buffer_index,
                };

                const mesh = self.renderer.getLegacyMesh(batch_key.mesh_handle);
                const sub_mesh_index = batch_key.sub_mesh_index;

                if (mesh.loaded) {
                    bindMeshBuffers(self, mesh, cmd_list);

                    graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                    graphics.cmdDrawIndexedInstanced(
                        cmd_list,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mIndexCount,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartIndex,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mInstanceCount * @as(u32, @intCast(batch.instances.items.len)),
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mVertexOffset,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartInstance + batch.start_instance_location,
                    );
                }
            }
        }
    }

    // Render Opaque Shadow Casters
    {
        const trazy_zone1 = ztracy.ZoneNC(@src(), "Opaque Objects", 0x00_ff_ff_00);
        defer trazy_zone1.End();

        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Render Batches", 0x00_ff_ff_00);
            defer trazy_zone2.End();

            const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index]);
            const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.materials_buffer);

            var batch_keys_iterator = self.batches.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                if (batch_key.surface_type != .@"opaque") {
                    continue;
                }

                const batch = self.batches.getPtr(batch_key.*).?;
                if (batch.instances.items.len == 0) {
                    continue;
                }

                const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_handle);
                const pipeline_id = pipeline_ids.shadow_caster_pipeline_id.?;
                const pipeline = self.renderer.getPSO(pipeline_id);
                const root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);

                if (pipeline_id.hash == renderer.opaque_pipelines[3].hash) {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.tree_descriptor_sets_shadow_caster[opaque_entities_index]);
                } else {
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_shadow_caster[opaque_entities_index]);
                }

                const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                const push_constants = InstanceRootConstants{
                    .start_instance_location = batch.start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
                    .instance_material_buffer_index = material_buffer_index,
                };

                const mesh = self.renderer.getLegacyMesh(batch_key.mesh_handle);
                const sub_mesh_index = batch_key.sub_mesh_index;

                if (mesh.loaded) {
                    bindMeshBuffers(self, mesh, cmd_list);

                    graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                    graphics.cmdDrawIndexedInstanced(
                        cmd_list,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mIndexCount,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartIndex,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mInstanceCount * @as(u32, @intCast(batch.instances.items.len)),
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mVertexOffset,
                        mesh.geometry.*.pDrawArgs[sub_mesh_index].mStartInstance + batch.start_instance_location,
                    );
                }
            }
        }
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    const descriptor_sets_shadow_caster = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("lit_shadow_caster_opaque"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("lit_shadow_caster_cutout"));

        var descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet = undefined;
        for (descriptor_sets_gbuffer, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == opaque_entities_index) {
                desc.pRootSignature = root_signature_lit;
            } else {
                desc.pRootSignature = root_signature_lit_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets_gbuffer[index]));
        }

        break :blk descriptor_sets_gbuffer;
    };
    self.descriptor_sets_shadow_caster = descriptor_sets_shadow_caster;

    const tree_descriptor_sets_shadow_caster = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("tree_shadow_caster_opaque"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("tree_shadow_caster_cutout"));

        var descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet = undefined;
        for (descriptor_sets_gbuffer, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == opaque_entities_index) {
                desc.pRootSignature = root_signature_lit;
            } else {
                desc.pRootSignature = root_signature_lit_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets_gbuffer[index]));
        }

        break :blk descriptor_sets_gbuffer;
    };
    self.tree_descriptor_sets_shadow_caster = tree_descriptor_sets_shadow_caster;

    const tree_descriptor_sets_gbuffer = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("tree_gbuffer_opaque"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("tree_gbuffer_cutout"));

        var descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet = undefined;
        for (descriptor_sets_gbuffer, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == opaque_entities_index) {
                desc.pRootSignature = root_signature_lit;
            } else {
                desc.pRootSignature = root_signature_lit_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets_gbuffer[index]));
        }

        break :blk descriptor_sets_gbuffer;
    };
    self.tree_descriptor_sets_gbuffer = tree_descriptor_sets_gbuffer;

    const descriptor_sets_gbuffer = blk: {
        const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("lit_gbuffer_opaque"));
        const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("lit_gbuffer_cutout"));

        var descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet = undefined;
        for (descriptor_sets_gbuffer, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == opaque_entities_index) {
                desc.pRootSignature = root_signature_lit;
            } else {
                desc.pRootSignature = root_signature_lit_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets_gbuffer[index]));
        }

        break :blk descriptor_sets_gbuffer;
    };
    self.descriptor_sets_gbuffer = descriptor_sets_gbuffer;
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    var params: [2]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers_gbuffer[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets_gbuffer[opaque_entities_index], 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets_gbuffer[cutout_entities_index], 1, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var shadows_uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers_shadow_caster[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&shadows_uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets_shadow_caster[opaque_entities_index], 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets_shadow_caster[cutout_entities_index], 1, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers_gbuffer[i]);
        var wind_buffer = self.renderer.getBuffer(self.wind_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "cbWind";
        params[1].__union_field3.ppBuffers = @ptrCast(&wind_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.tree_descriptor_sets_gbuffer[opaque_entities_index], 2, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.tree_descriptor_sets_gbuffer[cutout_entities_index], 2, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers_shadow_caster[i]);
        var wind_buffer = self.renderer.getBuffer(self.wind_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "cbWind";
        params[1].__union_field3.ppBuffers = @ptrCast(&wind_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.tree_descriptor_sets_shadow_caster[opaque_entities_index], 2, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.tree_descriptor_sets_shadow_caster[cutout_entities_index], 2, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *GeometryRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_gbuffer[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_gbuffer[cutout_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_shadow_caster[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_shadow_caster[cutout_entities_index]);

    graphics.removeDescriptorSet(self.renderer.renderer, self.tree_descriptor_sets_gbuffer[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.tree_descriptor_sets_gbuffer[cutout_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.tree_descriptor_sets_shadow_caster[opaque_entities_index]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.tree_descriptor_sets_shadow_caster[cutout_entities_index]);
}

fn batchEntities(
    self: *GeometryRenderPass,
    camera_entity: ecsu.Entity,
    batch_map: *BatchMap,
) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Batch Entities", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();

    // Clear existing batches' instances
    {
        var batch_keys_iterator = batch_map.keyIterator();
        while (batch_keys_iterator.next()) |batch_key| {
            const batch = batch_map.getPtr(batch_key.*).?;
            batch.start_instance_location = 0;
            batch.instances.clearRetainingCapacity();
        }
    }

    const max_draw_distance_squared = max_draw_distance * max_draw_distance;
    var query_static_mesh_iter = ecs.query_iter(self.ecsu_world.world, self.query_static_mesh);
    while (ecs.query_next(&query_static_mesh_iter)) {
        const static_meshes = ecs.field(&query_static_mesh_iter, fd.LodGroup, 0).?;
        const transforms = ecs.field(&query_static_mesh_iter, fd.Transform, 1).?;
        const scales = ecs.field(&query_static_mesh_iter, fd.Scale, 2).?;

        for (static_meshes, transforms, scales) |*lod_group_component, transform, scale| {
            var static_mesh = lod_group_component.lods[0];
            var sub_mesh_count = static_mesh.materials.items.len;
            if (sub_mesh_count == 0) {
                continue;
            }

            {
                // Distance culling
                if (!isWithinCameraDrawDistance(camera_position, transform.getPos00(), max_draw_distance_squared)) {
                    continue;
                }

                // TODO(gmodarelli): If we're in a shadow-casting pass, we should use the "light's camera frustum"
                const mesh = self.renderer.getLegacyMesh(static_mesh.mesh_handle);
                var world: [16]f32 = undefined;
                storeMat44(transform.matrix[0..], &world);
                const z_world = zm.loadMat(world[0..]);
                const z_aabbcenter = zm.loadArr3w(mesh.geometry.*.mAabbCenter, 1.0);
                var bounding_sphere_center: [3]f32 = .{ 0.0, 0.0, 0.0 };
                zm.storeArr3(&bounding_sphere_center, zm.mul(z_aabbcenter, z_world));
                const bounding_sphere_radius = mesh.geometry.*.mRadius * @max(scale.x, @max(scale.y, scale.z));
                if (!camera_comps.camera.isVisible(bounding_sphere_center, bounding_sphere_radius)) {
                    continue;
                }
            }

            // LOD Selection
            static_mesh = selectLOD(lod_group_component, camera_position, transform.getPos00());
            sub_mesh_count = static_mesh.materials.items.len;

            {
                for (0..sub_mesh_count) |sub_mesh_index| {
                    const material_handle = static_mesh.materials.items[sub_mesh_index];

                    var batch_key: BatchKey = undefined;
                    batch_key.material_handle = material_handle;
                    batch_key.mesh_handle = static_mesh.mesh_handle;
                    batch_key.sub_mesh_index = @intCast(sub_mesh_index);
                    batch_key.surface_type = .@"opaque";

                    const material_buffer_offset = self.renderer.getMaterialBufferOffset(material_handle);
                    const alpha_test = self.renderer.getMaterialAlphaTest(material_handle);
                    if (alpha_test) {
                        batch_key.surface_type = .cutout;
                    }

                    var instance_data: InstanceData = undefined;
                    storeMat44(transform.matrix[0..], &instance_data.object_to_world);
                    storeMat44(transform.inv_matrix[0..], &instance_data.world_to_object);
                    instance_data.materials_buffer_offset = material_buffer_offset;
                    instance_data._padding = [3]f32{ 42.0, 42.0, 42.0 };

                    if (!batch_map.contains(batch_key)) {
                        const batch = Batch{
                            .instances = std.ArrayList(InstanceData).init(self.allocator),
                            .start_instance_location = 0,
                        };
                        batch_map.put(batch_key, batch) catch unreachable;
                    }

                    const batch = batch_map.getPtr(batch_key).?;
                    batch.*.instances.append(instance_data) catch unreachable;
                }
            }
        }
    }
}

inline fn isWithinCameraDrawDistance(camera_position: [3]f32, entity_position: [3]f32, max_draw_distance_squared: f32) bool {
    const z_camera_position = zm.loadArr3(camera_position);
    const z_entity_position = zm.loadArr3(entity_position);
    if (zm.lengthSq3(z_camera_position - z_entity_position)[0] <= (max_draw_distance_squared)) {
        return true;
    }

    return false;
}

fn selectLOD(lod_group: *const fd.LodGroup, camera_position: [3]f32, entity_position: [3]f32) fd.StaticMesh {
    if (lod_group.lod_count == 1) {
        return lod_group.lods[0];
    }

    const z_camera_position = zm.loadArr3(camera_position);
    const z_entity_position = zm.loadArr3(entity_position);
    const distance_squared = zm.lengthSq3(z_camera_position - z_entity_position)[0];

    const lod1_distance_squared = 50.0 * 50.0;
    const lod2_distance_squared = 100.0 * 100.0;
    const lod3_distance_squared = 200.0 * 200.0;

    var lod: u32 = 0;

    if (distance_squared >= lod3_distance_squared) {
        lod = 3;
    } else if (distance_squared >= lod2_distance_squared) {
        lod = 2;
    } else if (distance_squared >= lod1_distance_squared) {
        lod = 1;
    } else {
        lod = 0;
    }

    lod = @min(lod, lod_group.lod_count - 1);
    return lod_group.lods[lod];
}

inline fn storeMat44(mat43: *const [12]f32, mat44: *[16]f32) void {
    mat44[0] = mat43[0];
    mat44[1] = mat43[1];
    mat44[2] = mat43[2];
    mat44[3] = 0;
    mat44[4] = mat43[3];
    mat44[5] = mat43[4];
    mat44[6] = mat43[5];
    mat44[7] = 0;
    mat44[8] = mat43[6];
    mat44[9] = mat43[7];
    mat44[10] = mat43[8];
    mat44[11] = 0;
    mat44[12] = mat43[9];
    mat44[13] = mat43[10];
    mat44[14] = mat43[11];
    mat44[15] = 1;
}
