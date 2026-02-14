const std = @import("std");

const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const geometry = @import("../geometry.zig");
const renderer = @import("../renderer.zig");
const renderer_types = @import("../types.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const OpaqueSlice = util.OpaqueSlice;
const zgui = @import("zgui");
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

const Batch = struct {
    instances: std.ArrayList(InstanceData),
    start_instance_location: u32,
};

const BatchKey = struct {
    material_id: IdLocal.HashType,
    mesh_handle: renderer.LegacyMeshHandle,
    sub_mesh_index: u32,
    surface_type: renderer.SurfaceType,
};

const BatchMap = std.AutoHashMap(BatchKey, Batch);

const max_instances = 100000;
const max_draw_distance: f32 = 20000.0;

const cutout_entities_index: u32 = 0;
const opaque_entities_index: u32 = 1;
const max_entity_types: u32 = 2;

pub const DynamicGeometryPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,

    uniform_frame_buffers_gbuffer: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    descriptor_sets_gbuffer: [max_entity_types][*c]graphics.DescriptorSet,

    uniform_frame_buffers_shadow_caster: [renderer.Renderer.cascades_max_count][renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Descriptor Set should be associated to materials
    descriptor_sets_shadow_caster: [renderer.Renderer.cascades_max_count][max_entity_types][*c]graphics.DescriptorSet,

    gbuffer_batches: BatchMap,
    shadow_map_batches: [renderer.Renderer.cascades_max_count]BatchMap,

    gbuffer_instances: std.ArrayList(InstanceData),
    gbuffer_instance_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    shadow_map_instances: [renderer.Renderer.cascades_max_count]std.ArrayList(InstanceData),
    shadow_map_instance_buffers: [renderer.Renderer.cascades_max_count][renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    pub fn init(self: *@This(), rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;

        self.uniform_frame_buffers_gbuffer = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        for (0..renderer.Renderer.cascades_max_count) |i| {
            self.uniform_frame_buffers_shadow_caster[i] = blk: {
                var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createUniformBuffer(ShadowsUniformFrameData);
                }

                break :blk buffers;
            };
        }

        self.gbuffer_instances = std.ArrayList(InstanceData).init(allocator);
        self.gbuffer_instance_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createBindlessBuffer(max_instances * @sizeOf(InstanceData), "GBuffer Dynamic Instances");
            }

            break :blk buffers;
        };

        for (0..renderer.Renderer.cascades_max_count) |i| {
            self.shadow_map_instances[i] = std.ArrayList(InstanceData).init(allocator);
            self.shadow_map_instance_buffers[i] = blk: {
                var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(max_instances * @sizeOf(InstanceData), "Shadow Map Dynamic Instances");
                }

                break :blk buffers;
            };
        }

        self.gbuffer_batches = BatchMap.init(allocator);
        self.gbuffer_batches.ensureTotalCapacity(32) catch unreachable;
        for (0..renderer.Renderer.cascades_max_count) |i| {
            self.shadow_map_batches[i] = BatchMap.init(allocator);
            self.shadow_map_batches[i].ensureTotalCapacity(32) catch unreachable;
        }
    }

    pub fn destroy(self: *@This()) void {
        {
            var batch_keys_iterator = self.gbuffer_batches.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = self.gbuffer_batches.getPtr(batch_key.*).?;
                batch.start_instance_location = 0;
                batch.instances.deinit();
            }
            self.gbuffer_batches.deinit();
        }

        for (0..renderer.Renderer.cascades_max_count) |i| {
            var batch_keys_iterator = self.shadow_map_batches[i].keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = self.shadow_map_batches[i].getPtr(batch_key.*).?;
                batch.start_instance_location = 0;
                batch.instances.deinit();
            }
        }
    }

    fn bindMeshBuffers(self: *@This(), mesh: renderer.LegacyMesh, cmd_list: [*c]graphics.Cmd) void {
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

    pub fn renderImGui(self: *@This()) void {
        if (zgui.collapsingHeader("Dynamic Renderer", .{})) {
            var batch_keys_iterator = self.gbuffer_batches.keyIterator();
            _ = zgui.text("Batches: {}", .{batch_keys_iterator.len});
            var batch_index: u32 = 0;
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = self.gbuffer_batches.getPtr(batch_key.*).?;
                _ = zgui.text("Batch {} | {} | {} instance count: {}", .{ batch_key.*.mesh_handle.id, batch_key.*.sub_mesh_index, batch_key.*.material_id, batch.instances.items.len });
                batch_index += 1;
            }
        }
    }

    pub fn renderGBuffer(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "GBuffer: Geometry Render Pass", 0x00_ff_00_00);
        defer trazy_zone.End();

        const frame_index = self.renderer.frame_index;

        self.renderer.gpu_geometry_pass_profile_index = self.renderer.startGpuProfile(cmd_list, "Geometry");
        defer self.renderer.endGpuProfile(cmd_list, self.renderer.gpu_geometry_pass_profile_index);

        var uniform_frame_data_gbuffer: UniformFrameData = undefined;
        zm.storeMat(&uniform_frame_data_gbuffer.projection_view, render_view.view_projection);
        zm.storeMat(&uniform_frame_data_gbuffer.projection_view_inverted, render_view.view_projection_inverse);
        uniform_frame_data_gbuffer.camera_position = [4]f32{ render_view.position[0], render_view.position[1], render_view.position[2], 1.0 };
        uniform_frame_data_gbuffer.time = @floatCast(self.renderer.time);

        {
            batchEntities(self, render_view, &self.gbuffer_batches);
            self.gbuffer_instances.clearRetainingCapacity();

            var batch_keys_iterator = self.gbuffer_batches.keyIterator();
            var start_instance_location: u32 = 0;
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = self.gbuffer_batches.getPtr(batch_key.*).?;
                batch.start_instance_location = start_instance_location;
                start_instance_location += @intCast(batch.instances.items.len);

                const index = self.gbuffer_instances.items.len;
                self.gbuffer_instances.insertSlice(index, batch.instances.items) catch unreachable;
            }

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "Upload instance data", 0x00_ff_ff_00);
                defer trazy_zone2.End();

                const instance_data_slice = OpaqueSlice{
                    .data = @ptrCast(self.gbuffer_instances.items),
                    .size = self.gbuffer_instances.items.len * @sizeOf(InstanceData),
                };
                self.renderer.updateBuffer(instance_data_slice, 0, InstanceData, self.gbuffer_instance_buffers[frame_index]);
            }
        }

        // Update Uniform Frame Buffer
        {
            const data = OpaqueSlice{
                .data = @ptrCast(&uniform_frame_data_gbuffer),
                .size = @sizeOf(UniformFrameData),
            };
            self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers_gbuffer[frame_index]);
        }

        // Render Cutout Objects
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Cutout Objects", 0x00_ff_00_00);
            defer trazy_zone1.End();

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "Render Batches", 0x00_ff_00_00);
                defer trazy_zone2.End();

                const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.gbuffer_instance_buffers[frame_index]);
                const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);

                var batch_keys_iterator = self.gbuffer_batches.keyIterator();
                while (batch_keys_iterator.next()) |batch_key| {
                    if (batch_key.surface_type != .cutout) {
                        continue;
                    }

                    const batch = self.gbuffer_batches.getPtr(batch_key.*).?;
                    if (batch.instances.items.len == 0) {
                        continue;
                    }

                    const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_id);
                    const pipeline_id = pipeline_ids.gbuffer_pipeline_id.?;
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    const root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    std.debug.assert(pipeline_id.hash == renderer.cutout_pipelines[0].hash);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_gbuffer[cutout_entities_index]);

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

                const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.gbuffer_instance_buffers[frame_index]);
                const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);

                var batch_keys_iterator = self.gbuffer_batches.keyIterator();
                while (batch_keys_iterator.next()) |batch_key| {
                    if (batch_key.surface_type != .@"opaque") {
                        continue;
                    }

                    const batch = self.gbuffer_batches.getPtr(batch_key.*).?;
                    if (batch.instances.items.len == 0) {
                        continue;
                    }

                    const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_id);
                    const pipeline_id = pipeline_ids.gbuffer_pipeline_id.?;
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    const root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    std.debug.assert(pipeline_id.hash == renderer.opaque_pipelines[0].hash);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_gbuffer[opaque_entities_index]);

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

    pub fn renderShadowMap(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView, cascade_index: u32) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Shadow Map: Geometry Render Pass", 0x00_ff_00_00);
        defer trazy_zone.End();

        const frame_index = self.renderer.frame_index;

        // self.renderer.gpu_geometry_pass_profile_index = self.renderer.startGpuProfile(cmd_list, "Geometry");
        // defer self.renderer.endGpuProfile(cmd_list, self.renderer.gpu_geometry_pass_profile_index);

        var uniform_frame_data: ShadowsUniformFrameData = undefined;
        zm.storeMat(&uniform_frame_data.projection_view, render_view.view_projection);
        uniform_frame_data.time = @floatCast(self.renderer.time);

        {
            batchEntities(self, render_view, &self.shadow_map_batches[cascade_index]);
            self.shadow_map_instances[cascade_index].clearRetainingCapacity();

            var batch_keys_iterator = self.shadow_map_batches[cascade_index].keyIterator();
            var start_instance_location: u32 = 0;
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = self.shadow_map_batches[cascade_index].getPtr(batch_key.*).?;
                batch.start_instance_location = start_instance_location;
                start_instance_location += @intCast(batch.instances.items.len);

                const index = self.shadow_map_instances[cascade_index].items.len;
                self.shadow_map_instances[cascade_index].insertSlice(index, batch.instances.items) catch unreachable;
            }

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "Upload instance data", 0x00_ff_ff_00);
                defer trazy_zone2.End();

                const instance_data_slice = OpaqueSlice{
                    .data = @ptrCast(self.shadow_map_instances[cascade_index].items),
                    .size = self.shadow_map_instances[cascade_index].items.len * @sizeOf(InstanceData),
                };
                self.renderer.updateBuffer(instance_data_slice, 0, InstanceData, self.shadow_map_instance_buffers[cascade_index][frame_index]);
            }
        }

        // Update Uniform Frame Buffer
        {
            const data = OpaqueSlice{
                .data = @ptrCast(&uniform_frame_data),
                .size = @sizeOf(ShadowsUniformFrameData),
            };
            self.renderer.updateBuffer(data, 0, ShadowsUniformFrameData, self.uniform_frame_buffers_shadow_caster[cascade_index][frame_index]);
        }

        // Update Descriptor Sets
        {
            var params: [1]graphics.DescriptorData = undefined;
            var shadows_uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers_shadow_caster[cascade_index][frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbFrame";
            params[0].__union_field3.ppBuffers = @ptrCast(&shadows_uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.descriptor_sets_shadow_caster[cascade_index][opaque_entities_index], @intCast(params.len), @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.descriptor_sets_shadow_caster[cascade_index][cutout_entities_index], @intCast(params.len), @ptrCast(&params));
        }

        // Render Cutout Objects
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Cutout Objects", 0x00_ff_00_00);
            defer trazy_zone1.End();

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "Render Batches", 0x00_ff_00_00);
                defer trazy_zone2.End();

                const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.shadow_map_instance_buffers[cascade_index][frame_index]);
                const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);

                var batch_keys_iterator = self.shadow_map_batches[cascade_index].keyIterator();
                while (batch_keys_iterator.next()) |batch_key| {
                    if (batch_key.surface_type != .cutout) {
                        continue;
                    }

                    const batch = self.shadow_map_batches[cascade_index].getPtr(batch_key.*).?;
                    if (batch.instances.items.len == 0) {
                        continue;
                    }

                    const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_id);
                    const pipeline_id = pipeline_ids.shadow_caster_pipeline_id.?;
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    const root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    std.debug.assert(pipeline_id.hash == renderer.cutout_pipelines[1].hash);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_shadow_caster[cascade_index][cutout_entities_index]);

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

                const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.shadow_map_instance_buffers[cascade_index][frame_index]);
                const material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);

                var batch_keys_iterator = self.shadow_map_batches[cascade_index].keyIterator();
                while (batch_keys_iterator.next()) |batch_key| {
                    if (batch_key.surface_type != .@"opaque") {
                        continue;
                    }

                    const batch = self.shadow_map_batches[cascade_index].getPtr(batch_key.*).?;
                    if (batch.instances.items.len == 0) {
                        continue;
                    }

                    const pipeline_ids = self.renderer.getMaterialPipelineIds(batch_key.material_id);
                    const pipeline_id = pipeline_ids.shadow_caster_pipeline_id.?;
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    const root_signature = self.renderer.getRootSignature(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    std.debug.assert(pipeline_id.hash == renderer.opaque_pipelines[1].hash);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets_shadow_caster[cascade_index][opaque_entities_index]);

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

    pub fn createDescriptorSets(self: *@This()) void {
        for (0..renderer.Renderer.cascades_max_count) |i| {
            self.descriptor_sets_shadow_caster[i] = blk: {
                const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("lit_shadow_caster_opaque"));
                const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("lit_shadow_caster_cutout"));

                var descriptor_set: [max_entity_types][*c]graphics.DescriptorSet = undefined;
                for (descriptor_set, 0..) |_, index| {
                    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
                    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
                    desc.mMaxSets = renderer.Renderer.data_buffer_count;
                    if (index == opaque_entities_index) {
                        desc.pRootSignature = root_signature_lit;
                    } else {
                        desc.pRootSignature = root_signature_lit_masked;
                    }
                    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_set[index]));
                }

                break :blk descriptor_set;
            };
        }

        self.descriptor_sets_gbuffer = blk: {
            const root_signature_lit = self.renderer.getRootSignature(IdLocal.init("lit_gbuffer_opaque"));
            const root_signature_lit_masked = self.renderer.getRootSignature(IdLocal.init("lit_gbuffer_cutout"));

            var descriptor_set: [max_entity_types][*c]graphics.DescriptorSet = undefined;
            for (descriptor_set, 0..) |_, index| {
                var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
                desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
                desc.mMaxSets = renderer.Renderer.data_buffer_count;
                if (index == opaque_entities_index) {
                    desc.pRootSignature = root_signature_lit;
                } else {
                    desc.pRootSignature = root_signature_lit_masked;
                }
                graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_set[index]));
            }

            break :blk descriptor_set;
        };
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        var params: [2]graphics.DescriptorData = undefined;

        for (0..renderer.Renderer.data_buffer_count) |i| {
            var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers_gbuffer[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbFrame";
            params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets_gbuffer[opaque_entities_index], 1, @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets_gbuffer[cutout_entities_index], 1, @ptrCast(&params));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_gbuffer[opaque_entities_index]);
        graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_gbuffer[cutout_entities_index]);
        for (0..renderer.Renderer.cascades_max_count) |i| {
            graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_shadow_caster[i][opaque_entities_index]);
            graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets_shadow_caster[i][cutout_entities_index]);
        }
    }

    fn batchEntities(self: *@This(), render_view: renderer.RenderView, batch_map: *BatchMap) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Batch Entities", 0x00_ff_ff_00);
        defer trazy_zone.End();

        const camera_position = render_view.position;

        // Clear existing batches' instances
        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Clear", 0x00_ff_ff_00);
            defer trazy_zone2.End();
            var batch_keys_iterator = batch_map.keyIterator();
            while (batch_keys_iterator.next()) |batch_key| {
                const batch = batch_map.getPtr(batch_key.*).?;
                batch.start_instance_location = 0;
                batch.instances.clearRetainingCapacity();
            }
        }

        const max_draw_distance_squared = max_draw_distance * max_draw_distance;

        for (self.renderer.dynamic_entities.items) |dynamic_entity| {
            var lod: *const renderer_types.Lod = &dynamic_entity.lods[0];
            var sub_mesh_count = lod.materials_count;
            if (sub_mesh_count == 0) {
                continue;
            }

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "culling", 0x00_ff_ff_00);
                defer trazy_zone2.End();
                // Distance culling
                if (!isWithinCameraDrawDistance(camera_position, dynamic_entity.position, max_draw_distance_squared)) {
                    continue;
                }

                const mesh = self.renderer.getLegacyMesh(lod.mesh_handle);
                const z_aabbcenter = zm.loadArr3w(mesh.geometry.*.mAabbCenter, 1.0);
                var bounding_sphere_center: [3]f32 = .{ 0.0, 0.0, 0.0 };
                zm.storeArr3(&bounding_sphere_center, zm.mul(z_aabbcenter, dynamic_entity.world));
                const bounding_sphere_radius = mesh.geometry.*.mRadius * dynamic_entity.scale;
                if (!render_view.frustum.isVisible(bounding_sphere_center, bounding_sphere_radius)) {
                    continue;
                }
            }

            // LOD Selection
            const trazy_zone2 = ztracy.ZoneNC(@src(), "selectlod", 0x00_ff_ff_00);
            lod = selectLOD(dynamic_entity.lods[0..dynamic_entity.lod_count], camera_position, dynamic_entity.position);
            sub_mesh_count = lod.materials_count;
            trazy_zone2.End();

            {
                const trazy_zone3 = ztracy.ZoneNC(@src(), "batch", 0x00_ff_ff_00);
                defer trazy_zone3.End();
                for (0..sub_mesh_count) |sub_mesh_index| {
                    const material_id = lod.materials[sub_mesh_index];

                    var batch_key: BatchKey = undefined;
                    batch_key.material_id = material_id;
                    batch_key.mesh_handle = lod.mesh_handle;
                    batch_key.sub_mesh_index = @intCast(sub_mesh_index);
                    batch_key.surface_type = .@"opaque";

                    const material_index = self.renderer.getMaterialIndex(material_id);
                    const alpha_test = self.renderer.getMaterialAlphaTest(material_id);
                    if (alpha_test) {
                        batch_key.surface_type = .cutout;
                    }

                    var instance_data: InstanceData = undefined;
                    zm.storeMat(&instance_data.object_to_world, dynamic_entity.world);
                    instance_data.material_index = @intCast(material_index);

                    if (!batch_map.contains(batch_key)) {
                        const batch = Batch{
                            .instances = std.ArrayList(InstanceData).initCapacity(self.allocator, 10000) catch unreachable,
                            .start_instance_location = 0,
                        };
                        batch_map.putAssumeCapacity(batch_key, batch);
                    }

                    const batch = batch_map.getPtr(batch_key).?;
                    batch.*.instances.appendAssumeCapacity(instance_data);
                }
            }
        }
    }
};

inline fn isWithinCameraDrawDistance(camera_position: [3]f32, entity_position: [3]f32, max_draw_distance_squared: f32) bool {
    const z_camera_position = zm.loadArr3(camera_position);
    const z_entity_position = zm.loadArr3(entity_position);
    if (zm.lengthSq3(z_camera_position - z_entity_position)[0] <= (max_draw_distance_squared)) {
        return true;
    }

    return false;
}

fn selectLOD(lods: []const renderer_types.Lod, camera_position: [3]f32, entity_position: [3]f32) *const renderer_types.Lod {
    if (lods.len == 1) {
        return &lods[0];
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

    lod = @min(lod, lods.len - 1);
    return &lods[lod];
}
