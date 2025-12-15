const std = @import("std");

const BufferHandle = renderer.BufferHandle;
const DescriptorSet = graphics.DescriptorSet;
const fd = @import("../../config/flecs_data.zig");
const frames_count = Renderer.data_buffer_count;
const geometry = @import("../../renderer/geometry.zig");
const graphics = zforge.graphics;
const ID = @import("../../core/core.zig").ID;
const IdLocal = @import("../../core/core.zig").IdLocal;
const im3d = @import("im3d");
const OpaqueSlice = util.OpaqueSlice;
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
const pso = @import("../../renderer/pso.zig");
const renderer = @import("../../renderer/renderer.zig");
const Renderer = renderer.Renderer;
const renderer_types = @import("../../renderer/types.zig");
const util = @import("../../util.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const zm = @import("zmath");
const ztracy = @import("ztracy");

const instances_max_count = 1000000;
const meshlets_max_count = 1 << 20;
const EntityMap = std.AutoHashMap(u64, struct { index: usize, count: u32 });

const GpuInstanceFlags = packed struct(u32) {
    destroyed: u1,
    draw_bounds: u1,
    _padding: u30,
};

const GpuInstance = struct {
    world: [16]f32,
    local_bounds_origin: [3]f32,
    screen_percentage_min: f32,
    local_bounds_extents: [3]f32,
    screen_percentage_max: f32,
    id: u32,
    mesh_index: u32,
    material_index: u32,
    flags: GpuInstanceFlags,
};

const GpuInstance2 = struct {
    world: [16]f32,
    bounds_origin: [3]f32,
    renderable_item_id: u32,
    bounds_extents: [3]f32,
    renderable_item_count: u32,
    flags: GpuInstanceFlags,
    _pad: [3]u32,
};

const GpuMeshletCandidate = struct {
    instance_id: u32,
    mesh_index: u32,
    material_index: u32,
    meshlet_index: u32,
};

const GpuDestroyInstance = struct {
    index: u32,
    count: u32,
};

const GpuDestroyInstance2 = struct {
    index: u32,
};

const DestroyInstancesParams = struct {
    instances_buffer_index: u32,
    instances_to_destroy_buffer_index: u32,
    instances_to_destroy_count: u32,
    _padding: u32,
};

const Frame = struct {
    view: [16]f32,
    proj: [16]f32,
    view_proj: [16]f32,
    view_proj_inv: [16]f32,
    viewport_info: [4]f32,
    camera_position: [4]f32,
    camera_near_plane: f32,
    camera_far_plane: f32,
    time: f32,
    renderable_buffer_index: u32,
    linear_repeat_sampler_index: u32,
    linear_clamp_sampler_index: u32,
    shadow_sampler_index: u32,
    shadow_pcf_sampler_index: u32,
    instance_buffer_index: u32,
    material_buffer_index: u32,
    meshes_buffer_index: u32,
    instance_count: u32,
};

const ClearUavParams = struct {
    candidate_meshlets_counter_buffer_index: u32,
    visible_meshlets_counter_buffer_index: u32,
};

const CullInstancesParams = struct {
    candidate_meshlets_counter_buffer_index: u32,
    candidate_meshlets_buffer_index: u32,
    shadow_pass: u32,
    _padding: u32,
};

const BuildMeshletsCullArgsParams = struct {
    candidate_meshlets_counter_buffer_index: u32,
    dispatch_args_buffer_index: u32,
};

const CullMeshletsParams = struct {
    candidate_meshlets_counters_buffer_index: u32,
    candidate_meshlets_buffer_index: u32,
    visible_meshlets_counters_buffer_index: u32,
    visible_meshlets_buffer_index: u32,
};

const BinningParams = struct {
    bins_count: u32,
    meshlet_counts_buffer_index: u32,
    meshlet_offset_and_counts_buffer_index: u32,
    global_meshlet_counter_buffer_index: u32,
    binned_meshlets_buffer_index: u32,
    dispatch_args_buffer_index: u32,
    visible_meshlets_buffer_index: u32,
    visible_meshlets_counters_buffer_index: u32,
};

const RasterizerParams = struct {
    bin_index: u32,
    visible_meshlets_buffer_index: u32,
    binned_meshlets_buffer_index: u32,
    meshlet_bin_data_buffer_index: u32,
};

const RenderSettings = struct {
    freeze_rendering: bool,
};

pub const StaticGeometryPass = struct {
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    pso_mgr: *pso.PSOManager,
    render_settings: RenderSettings,

    instances: std.ArrayList(GpuInstance2),
    instances_to_destroy: std.ArrayList(GpuDestroyInstance2),
    // compacted_instances_to_destroy: std.ArrayList(GpuDestroyInstance),
    entity_map: EntityMap,

    // Global Buffers
    instance_buffer: renderer.ElementBindlessBuffer,
    // Destroy Instance Buffers
    instance_to_destroy_buffer: renderer.ElementBindlessBuffer,
    destroy_instances_uniform_buffers: [frames_count]BufferHandle,
    destroy_instances_descriptor_set: [*c]DescriptorSet,
    // Meshlet Culling Buffers
    candidate_meshlets_counters_buffers: BufferHandle,
    candidate_meshlets_buffers: BufferHandle,
    visible_meshlets_counters_buffers: BufferHandle,
    visible_meshlets_buffers: BufferHandle,
    meshlet_cull_args_buffers: BufferHandle,
    // Meshlet Binning Buffers
    meshlet_count_buffers: BufferHandle,
    meshlet_offset_and_count_buffers: BufferHandle,
    meshlet_global_count_buffers: BufferHandle,
    binned_meshlets_buffers: BufferHandle,
    classify_meshes_dispatch_args_buffers: BufferHandle,

    gbuffer_bindings: PassBindings = undefined,
    shadows_bindings: [renderer.Renderer.cascades_max_count]PassBindings = undefined,

    pub fn init(self: *StaticGeometryPass, rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;
        self.pso_mgr = &rctx.pso_manager;

        // Global Buffers
        self.instance_buffer.init(rctx, instances_max_count, @sizeOf(GpuInstance2), false, "GPU Instances");

        // Meshlet Culling Buffers
        {
            self.candidate_meshlets_counters_buffers = rctx.createReadWriteBindlessBuffer(8 * @sizeOf(u32), "Candidate Meshlets Counters Buffer");
            self.candidate_meshlets_buffers = rctx.createReadWriteBindlessBuffer(meshlets_max_count * @sizeOf(GpuMeshletCandidate), "Candidate Meshlets Buffer");
            self.visible_meshlets_counters_buffers = rctx.createReadWriteBindlessBuffer(8 * @sizeOf(u32), "Visible Meshlets Counters Buffer");
            self.visible_meshlets_buffers = rctx.createReadWriteBindlessBuffer(meshlets_max_count * @sizeOf(GpuMeshletCandidate), "Visible Meshlets Buffer");
            self.meshlet_cull_args_buffers = rctx.createReadWriteBindlessBuffer(8 * @sizeOf(u32), "Meshlets Cull Dispatch Args Buffer");
        }

        // Meshlet Binning Buffers
        {
            self.meshlet_count_buffers = rctx.createReadWriteBindlessBuffer(16 * @sizeOf(u32), "Meshlet Binning: Meshlets Count");
            self.meshlet_offset_and_count_buffers = rctx.createReadWriteBindlessBuffer(pso.pso_bins_max_count * @sizeOf([4]u32), "Meshlet Binning: Meshlets Offset and Count");
            self.meshlet_global_count_buffers = rctx.createReadWriteBindlessBuffer(16 * @sizeOf(u32), "Meshlet Binning: Meshlets Global Count");
            self.binned_meshlets_buffers = rctx.createReadWriteBindlessBuffer(meshlets_max_count * @sizeOf(u32), "Meshlet Binning: Binned Meshlets");
            self.classify_meshes_dispatch_args_buffers = rctx.createReadWriteBindlessBuffer(@sizeOf([4]u32), "Meshlet Binning: Classify Meshlets Dispatch Args");
        }

        // Uniform Buffers
        {
            self.gbuffer_bindings.init(rctx);
            for (0..renderer.Renderer.cascades_max_count) |cascade_index| {
                self.shadows_bindings[cascade_index].init(rctx);
            }
        }

        // Destroy Instances GPU resources Data
        {
            // GPU Buffer
            self.instance_to_destroy_buffer.init(rctx, 8169, @sizeOf(GpuDestroyInstance2), false, "GPU Instances to Destroy");

            // Uniform Buffers
            self.destroy_instances_uniform_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createUniformBuffer(DestroyInstancesParams);
                }

                break :blk buffers;
            };
        }

        self.instances = std.ArrayList(GpuInstance2).init(self.allocator);
        self.instances_to_destroy = std.ArrayList(GpuDestroyInstance2).init(self.allocator);
        // self.compacted_instances_to_destroy = std.ArrayList(GpuDestroyInstance).init(self.allocator);
        self.entity_map = EntityMap.init(self.allocator);
    }

    pub fn destroy(self: *@This()) void {
        // self.compacted_instances_to_destroy.deinit();
        self.instances_to_destroy.deinit();
        self.instances.deinit();
        self.entity_map.deinit();
    }

    fn gpuDestroyInstancesSorter(_: void, a: GpuDestroyInstance, b: GpuDestroyInstance) bool {
        return a.index < b.index;
    }

    pub fn update(self: *@This(), cmd_list: [*c]graphics.Cmd) void {
        self.instances.clearRetainingCapacity();
        self.instances_to_destroy.clearRetainingCapacity();
        // self.compacted_instances_to_destroy.clearRetainingCapacity();

        for (self.renderer.removed_static_entities.items) |static_entity_id| {
            if (self.entity_map.get(static_entity_id)) |entity_info| {
                self.instances_to_destroy.append(.{ .index = @intCast(entity_info.index) }) catch unreachable;
                _ = self.entity_map.remove(static_entity_id);
            }
        }

        if (self.instances_to_destroy.items.len > 0)
        {
            // // Dumb sorting and compaction
            // {
            //     // Sort by index
            //     std.mem.sort(GpuDestroyInstance, self.instances_to_destroy.items, {}, gpuDestroyInstancesSorter);

            //     // Compact the prefix sum buffer
            //     var current_instance_to_destroy = self.instances_to_destroy.items[0];
            //     for (1..self.instances_to_destroy.items.len) |i| {
            //         const instance_to_destroy = self.instances_to_destroy.items[i];
            //         if (current_instance_to_destroy.index + current_instance_to_destroy.count == instance_to_destroy.index) {
            //             current_instance_to_destroy.count += instance_to_destroy.count;
            //         } else {
            //             self.compacted_instances_to_destroy.append(current_instance_to_destroy) catch unreachable;
            //             current_instance_to_destroy.index = instance_to_destroy.index;
            //             current_instance_to_destroy.count = instance_to_destroy.count;
            //         }
            //     }
            //     self.compacted_instances_to_destroy.append(current_instance_to_destroy) catch unreachable;
            // }

            const data = OpaqueSlice{
                .data = @ptrCast(self.instances_to_destroy.items),
                .size = self.instances_to_destroy.items.len * @sizeOf(GpuDestroyInstance2),
            };

            std.debug.assert(self.instance_to_destroy_buffer.size > data.size);
            self.renderer.updateBuffer(data, 0, GpuDestroyInstance2, self.instance_to_destroy_buffer.buffer);

            const uniform_buffer_handle = self.destroy_instances_uniform_buffers[self.renderer.frame_index];

            const destroy_instances_params = DestroyInstancesParams{
                .instances_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffer.buffer),
                .instances_to_destroy_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_to_destroy_buffer.buffer),
                .instances_to_destroy_count = @intCast(self.instances_to_destroy.items.len),
                ._padding = 42,
            };
            const params_data = OpaqueSlice{
                .data = @ptrCast(&destroy_instances_params),
                .size = @sizeOf(DestroyInstancesParams),
            };
            self.renderer.updateBuffer(params_data, 0, DestroyInstancesParams, uniform_buffer_handle);

            // Update Descriptor Set
            {
                var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);

                var params: [1]graphics.DescriptorData = undefined;
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "g_DestroyParams";
                params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                graphics.updateDescriptorSet(self.renderer.renderer, self.renderer.frame_index, self.destroy_instances_descriptor_set, @intCast(params.len), @ptrCast(&params));
            }

            const pipeline_id = ID("destroy_instances");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, self.renderer.frame_index, self.destroy_instances_descriptor_set);
            graphics.cmdDispatch(cmd_list, 1, 1, 1);
        }

        // for (self.renderer.added_static_entities.items) |static_entity| {
        //     const renderable_data = self.renderer.getRenderable(static_entity.renderable_id);
        //     const instances_count = renderable_data.gpu_instance_count;
        //     const instance_buffer_index = self.instance_buffer.element_count + self.instances.items.len;

        //     for (0..renderable_data.lods_count) |lod_index| {
        //         const mesh_info = self.renderer.getMeshInfo(renderable_data.lods[lod_index].mesh_id);

        //         for (0..mesh_info.count) |mesh_index_offset| {
        //             const mesh = &self.renderer.meshes.items[mesh_info.index + mesh_index_offset];

        //             const material_index = self.renderer.getMaterialIndex(renderable_data.lods[lod_index].materials[mesh_index_offset]);
        //             var gpu_instance = std.mem.zeroes(GpuInstance);
        //             zm.storeMat(&gpu_instance.world, zm.transpose(static_entity.world));
        //             gpu_instance.id = @intCast(self.instance_buffer.element_count + self.instances.items.len);
        //             gpu_instance.mesh_index = @intCast(mesh_info.index + mesh_index_offset);
        //             gpu_instance.material_index = @intCast(material_index);
        //             gpu_instance.local_bounds_origin = mesh.bounds.center;
        //             gpu_instance.local_bounds_extents = mesh.bounds.extents;
        //             gpu_instance.screen_percentage_min = renderable_data.lods[lod_index].screen_percentage_range[0];
        //             gpu_instance.screen_percentage_max = renderable_data.lods[lod_index].screen_percentage_range[1];
        //             gpu_instance.flags = std.mem.zeroes(GpuInstanceFlags);
        //             if (static_entity.draw_bounds) {
        //                 gpu_instance.flags.draw_bounds = 1;
        //             }

        //             self.instances.append(gpu_instance) catch unreachable;
        //         }
        //     }

        //     self.entity_map.put(static_entity.entity_id, .{ .index = instance_buffer_index, .count = instances_count }) catch unreachable;
        // }

        for (self.renderer.added_static_entities.items) |static_entity| {
            const renderable_data = self.renderer.getRenderable(static_entity.renderable_id);
            const instance_buffer_index = self.instances.items.len;

            const renderable_item = self.renderer.renderable_item_map.get(static_entity.renderable_id.hash).?;

            var gpu_instance = std.mem.zeroes(GpuInstance2);
            gpu_instance.renderable_item_id = @intCast(renderable_item.index);
            gpu_instance.renderable_item_count = renderable_item.count;
            zm.storeMat(&gpu_instance.world, zm.transpose(static_entity.world));
            gpu_instance.bounds_origin = renderable_data.bounds_origin;
            gpu_instance.bounds_extents = renderable_data.bounds_extents;
            gpu_instance.flags = std.mem.zeroes(GpuInstanceFlags);
            if (static_entity.draw_bounds) {
                gpu_instance.flags.draw_bounds = 1;
            }

            self.instances.append(gpu_instance) catch unreachable;
            self.entity_map.put(static_entity.entity_id, .{ .index = instance_buffer_index, .count = 0 }) catch unreachable;
        }

        if (self.instances.items.len > 0) {
            self.instance_buffer.element_count += @intCast(self.instances.items.len);

            const instance_data = OpaqueSlice{
                .data = @ptrCast(self.instances.items),
                .size = self.instances.items.len * @sizeOf(GpuInstance),
            };

            std.debug.assert(self.instance_buffer.size > instance_data.size + self.instance_buffer.offset);
            self.renderer.updateBuffer(instance_data, self.instance_buffer.offset, GpuInstance, self.instance_buffer.buffer);
            self.instance_buffer.offset += instance_data.size;
        }
    }

    pub fn renderImGui(self: *@This()) void {
        if (zgui.collapsingHeader("Static Geometry Renderer", .{})) {
            zgui.text("Total loaded instances: {d}", .{self.instance_buffer.element_count});
            _ = zgui.checkbox("Freeze Culling", .{ .v = &self.render_settings.freeze_rendering });
        }
    }

    pub fn renderGBuffer(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "GPU Driven: GBuffer", 0x00_ff_00_00);
        defer trazy_zone.End();

        self.renderer.gpu_gpu_driven_pass_profile_index = self.renderer.startGpuProfile(cmd_list, "GPU-Driven");
        defer self.renderer.endGpuProfile(cmd_list, self.renderer.gpu_gpu_driven_pass_profile_index);

        self.cullAndRender(cmd_list, render_view, false, 0);
    }

    pub fn renderShadowMap(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView, cascade_index: u32) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "GPU Driven: Shadow Cascade", 0x00_ff_00_00);
        defer trazy_zone.End();

        self.cullAndRender(cmd_list, render_view, true, cascade_index);
    }

    fn createWritableBindlessBuffer(self: *@This(), size: u64, debug_name: []const u8) renderer.BufferHandle {
        const buffer_creation_desc = renderer.BufferCreationDesc{
            .bindless = true,
            .descriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits },
            .start_state = .RESOURCE_STATE_COMMON,
            .size = size,
            .debug_name = debug_name,
        };

        return self.renderer.createBuffer(buffer_creation_desc);
    }

    fn cullAndRender(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView, shadow_view: bool, cascade_index: u32) void {
        const frame_index = self.renderer.frame_index;

        // Frame Uniform Buffer
        {
            var uniform_buffer = self.gbuffer_bindings.frame_uniform_buffers[frame_index];
            if (shadow_view) {
                uniform_buffer = self.shadows_bindings[cascade_index].frame_uniform_buffers[frame_index];
            }

            var frame = std.mem.zeroes(Frame);
            zm.storeMat(&frame.view, zm.transpose(render_view.view));
            zm.storeMat(&frame.proj, zm.transpose(render_view.projection));
            zm.storeMat(&frame.view_proj, zm.transpose(render_view.view_projection));
            zm.storeMat(&frame.view_proj_inv, zm.transpose(render_view.view_projection_inverse));
            frame.camera_position[0] = render_view.position[0];
            frame.camera_position[1] = render_view.position[1];
            frame.camera_position[2] = render_view.position[2];
            frame.camera_position[3] = 1.0;
            frame.camera_near_plane = render_view.near_plane;
            frame.camera_far_plane = render_view.far_plane;
            frame.time = @floatCast(self.renderer.time);
            frame.renderable_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.renderable_buffer.buffer);
            frame.instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffer.buffer);
            frame.material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);
            frame.meshes_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.mesh_buffer.buffer);
            frame.instance_count = self.instance_buffer.element_count;
            // TODO: Create a getSamplerBindlessIndex in renderer.zig
            frame.linear_repeat_sampler_index = @intCast(self.renderer.linear_repeat_sampler.*.mDx.mDescriptor);

            const frame_data = OpaqueSlice{
                .data = @ptrCast(&frame),
                .size = @sizeOf(Frame),
            };
            self.renderer.updateBuffer(frame_data, 0, Frame, uniform_buffer);
        }

        // Frame Culling Uniform Buffer
        var frame_uniform_buffer_handle = self.gbuffer_bindings.frame_uniform_buffers[frame_index];
        var frame_uniform_buffer = self.renderer.getBuffer(frame_uniform_buffer_handle);
        {
            var frame_culling_uniform_data: *Frame = &self.gbuffer_bindings.frame_culling_uniform_data[frame_index];

            if (shadow_view) {
                frame_uniform_buffer_handle = self.shadows_bindings[cascade_index].frame_uniform_buffers[frame_index];
                frame_uniform_buffer = self.renderer.getBuffer(frame_uniform_buffer_handle);
                frame_culling_uniform_data = &self.shadows_bindings[cascade_index].frame_culling_uniform_data[frame_index];
            }

            if (!self.render_settings.freeze_rendering) {
                zm.storeMat(&frame_culling_uniform_data.view, zm.transpose(render_view.view));
                zm.storeMat(&frame_culling_uniform_data.proj, zm.transpose(render_view.projection));
                zm.storeMat(&frame_culling_uniform_data.view_proj, zm.transpose(render_view.view_projection));
                zm.storeMat(&frame_culling_uniform_data.view_proj_inv, zm.transpose(render_view.view_projection_inverse));
                frame_culling_uniform_data.camera_position[0] = render_view.position[0];
                frame_culling_uniform_data.camera_position[1] = render_view.position[1];
                frame_culling_uniform_data.camera_position[2] = render_view.position[2];
                frame_culling_uniform_data.camera_position[3] = 1.0;
                frame_culling_uniform_data.camera_near_plane = render_view.near_plane;
                frame_culling_uniform_data.camera_far_plane = render_view.far_plane;
            }

            frame_culling_uniform_data.time = @floatCast(self.renderer.time);
            frame_culling_uniform_data.renderable_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.renderable_buffer.buffer);
            frame_culling_uniform_data.instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffer.buffer);
            frame_culling_uniform_data.material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);
            frame_culling_uniform_data.meshes_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.mesh_buffer.buffer);
            frame_culling_uniform_data.instance_count = self.instance_buffer.element_count;

            const frame_culling_data = OpaqueSlice{
                .data = @ptrCast(frame_culling_uniform_data),
                .size = @sizeOf(Frame),
            };
            self.renderer.updateBuffer(frame_culling_data, 0, Frame, frame_uniform_buffer_handle);
        }

        // Meshlets Culling
        {
            // Clear UAV Counters
            {
                const candidate_meshlets_counters_buffer = self.renderer.getBuffer(self.candidate_meshlets_counters_buffers);
                const visible_meshlets_counters_buffer = self.renderer.getBuffer(self.visible_meshlets_counters_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(candidate_meshlets_counters_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(visible_meshlets_counters_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    var uniform_buffer_handle = self.gbuffer_bindings.clear_uav_uniform_buffers[frame_index];
                    if (shadow_view) {
                        uniform_buffer_handle = self.shadows_bindings[cascade_index].clear_uav_uniform_buffers[frame_index];
                    }

                    const clear_uav_params = ClearUavParams{
                        .candidate_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers),
                        .visible_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers),
                    };
                    const clear_uav_params_data = OpaqueSlice{
                        .data = @ptrCast(&clear_uav_params),
                        .size = @sizeOf(ClearUavParams),
                    };
                    self.renderer.updateBuffer(clear_uav_params_data, 0, ClearUavParams, uniform_buffer_handle);

                    // Update Descriptor Set
                    var descriptor_set = self.gbuffer_bindings.clear_uav_descriptor_set;
                    if (shadow_view) {
                        descriptor_set = self.shadows_bindings[cascade_index].clear_uav_descriptor_set;
                    }
                    {
                        var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);

                        var params: [1]graphics.DescriptorData = undefined;
                        params[0] = std.mem.zeroes(graphics.DescriptorData);
                        params[0].pName = "g_ClearUAVParams";
                        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                        graphics.updateDescriptorSet(self.renderer.renderer, frame_index, descriptor_set, @intCast(params.len), @ptrCast(&params));
                    }

                    const pipeline_id = ID("meshlet_clear_counters");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, descriptor_set);
                    graphics.cmdDispatch(cmd_list, 1, 1, 1);
                }
            }

            // Cull Instances
            {
                const candidate_meshlets_buffer = self.renderer.getBuffer(self.candidate_meshlets_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(candidate_meshlets_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    var uniform_buffer_handle = self.gbuffer_bindings.cull_instances_uniform_buffers[frame_index];
                    if (shadow_view) {
                        uniform_buffer_handle = self.shadows_bindings[cascade_index].cull_instances_uniform_buffers[frame_index];
                    }

                    const cull_instances_params = CullInstancesParams{
                        .candidate_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_buffers),
                        .candidate_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers),
                        .shadow_pass = if (shadow_view) 1 else 0,
                        ._padding = 42.0,
                    };

                    const cull_instances_params_data = OpaqueSlice{
                        .data = @ptrCast(&cull_instances_params),
                        .size = @sizeOf(CullInstancesParams),
                    };
                    self.renderer.updateBuffer(cull_instances_params_data, 0, CullInstancesParams, uniform_buffer_handle);

                    // Update Descriptor Set
                    var descriptor_set = self.gbuffer_bindings.cull_instances_descriptor_set;
                    if (shadow_view) {
                        descriptor_set = self.shadows_bindings[cascade_index].cull_instances_descriptor_set;
                    }
                    {
                        var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);
                        var debug_uniform_buffer = self.renderer.getBuffer(self.renderer.debug_frame_uniform_buffers[frame_index]);

                        var params: [3]graphics.DescriptorData = undefined;
                        params[0] = std.mem.zeroes(graphics.DescriptorData);
                        params[0].pName = "g_Frame";
                        params[0].__union_field3.ppBuffers = @ptrCast(&frame_uniform_buffer);
                        params[1] = std.mem.zeroes(graphics.DescriptorData);
                        params[1].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
                        params[1].pName = "g_CullInstancesParams";
                        params[2] = std.mem.zeroes(graphics.DescriptorData);
                        params[2].pName = "g_DebugFrame";
                        params[2].__union_field3.ppBuffers = @ptrCast(&debug_uniform_buffer);

                        graphics.updateDescriptorSet(self.renderer.renderer, frame_index, descriptor_set, @intCast(params.len), @ptrCast(&params));
                    }

                    const pipeline_id = ID("meshlet_cull_instances");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, descriptor_set);
                    const cull_instances_threads_count: u32 = 64;
                    const group_count_x = (self.instance_buffer.element_count + cull_instances_threads_count - 1) / cull_instances_threads_count;
                    if (group_count_x > 0) {
                        graphics.cmdDispatch(cmd_list, group_count_x, 1, 1);
                    }
                }

                const candidate_meshlets_counters_buffer = self.renderer.getBuffer(self.candidate_meshlets_counters_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(candidate_meshlets_counters_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Build Meshlet Cull Dispatch Arguments
            {
                const meshlets_cull_args_buffer = self.renderer.getBuffer(self.meshlet_cull_args_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlets_cull_args_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    var uniform_buffer_handle = self.gbuffer_bindings.build_meshlet_cull_args_uniform_buffers[frame_index];
                    if (shadow_view) {
                        uniform_buffer_handle = self.shadows_bindings[cascade_index].build_meshlet_cull_args_uniform_buffers[frame_index];
                    }

                    const build_meshlets_cull_args_params = BuildMeshletsCullArgsParams{
                        .candidate_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers),
                        .dispatch_args_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_cull_args_buffers),
                    };
                    const params_data = OpaqueSlice{
                        .data = @ptrCast(&build_meshlets_cull_args_params),
                        .size = @sizeOf(BuildMeshletsCullArgsParams),
                    };
                    self.renderer.updateBuffer(params_data, 0, BuildMeshletsCullArgsParams, uniform_buffer_handle);

                    // Update Descriptor Set
                    var descriptor_set = self.gbuffer_bindings.build_meshlet_cull_args_descriptor_set;
                    if (shadow_view) {
                        descriptor_set = self.shadows_bindings[cascade_index].build_meshlet_cull_args_descriptor_set;
                    }
                    {
                        var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);

                        var params: [1]graphics.DescriptorData = undefined;
                        params[0] = std.mem.zeroes(graphics.DescriptorData);
                        params[0].pName = "g_MeshletsCullArgsParams";
                        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                        graphics.updateDescriptorSet(self.renderer.renderer, frame_index, descriptor_set, @intCast(params.len), @ptrCast(&params));
                    }

                    const pipeline_id = ID("meshlet_build_meshlets_cull_args");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, descriptor_set);
                    graphics.cmdDispatch(cmd_list, 1, 1, 1);
                }

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlets_cull_args_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Cull Meshlets
            {
                const visible_meshlet_buffer = self.renderer.getBuffer(self.visible_meshlets_buffers);
                const meshlet_cull_args_buffer = self.renderer.getBuffer(self.meshlet_cull_args_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(visible_meshlet_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(meshlet_cull_args_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_INDIRECT_ARGUMENT),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    var uniform_buffer_handle = self.gbuffer_bindings.cull_meshlets_uniform_buffers[frame_index];
                    if (shadow_view) {
                        uniform_buffer_handle = self.shadows_bindings[cascade_index].cull_meshlets_uniform_buffers[frame_index];
                    }

                    const cull_meshlets_params = CullMeshletsParams{
                        .candidate_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_buffers),
                        .candidate_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers),
                        .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers),
                        .visible_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers),
                    };

                    const cull_meshlets_params_data = OpaqueSlice{
                        .data = @ptrCast(&cull_meshlets_params),
                        .size = @sizeOf(CullMeshletsParams),
                    };
                    self.renderer.updateBuffer(cull_meshlets_params_data, 0, CullMeshletsParams, uniform_buffer_handle);

                    // Update Descriptor Set
                    var descriptor_set = self.gbuffer_bindings.cull_meshlets_descriptor_set;
                    if (shadow_view) {
                        descriptor_set = self.shadows_bindings[cascade_index].cull_meshlets_descriptor_set;
                    }
                    {
                        var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);

                        var params: [2]graphics.DescriptorData = undefined;
                        params[0] = std.mem.zeroes(graphics.DescriptorData);
                        params[0].pName = "g_Frame";
                        params[0].__union_field3.ppBuffers = @ptrCast(&frame_uniform_buffer);
                        params[1] = std.mem.zeroes(graphics.DescriptorData);
                        params[1].pName = "g_CullMeshletsParams";
                        params[1].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                        graphics.updateDescriptorSet(self.renderer.renderer, frame_index, descriptor_set, @intCast(params.len), @ptrCast(&params));
                    }

                    const pipeline_id = ID("meshlet_cull_meshlets");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, descriptor_set);
                    graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH, 1, meshlet_cull_args_buffer, 0, null, 0);
                }

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(visible_meshlet_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(meshlet_cull_args_buffer, .RESOURCE_STATE_INDIRECT_ARGUMENT, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }
        }

        // Binning Meshets
        {
            var uniform_buffer_handle = self.gbuffer_bindings.binning_meshlets_uniform_buffers[frame_index];
            if (shadow_view) {
                uniform_buffer_handle = self.shadows_bindings[cascade_index].binning_meshlets_uniform_buffers[frame_index];
            }

            var binning_params = BinningParams{
                .bins_count = @intCast(self.pso_mgr.getPsoBinsCount()),
                .meshlet_counts_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_count_buffers),
                .meshlet_offset_and_counts_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_offset_and_count_buffers),
                .global_meshlet_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_global_count_buffers),
                .binned_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.binned_meshlets_buffers),
                .dispatch_args_buffer_index = self.renderer.getBufferBindlessIndex(self.classify_meshes_dispatch_args_buffers),
                .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers),
                .visible_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers),
            };

            const data = OpaqueSlice{
                .data = @ptrCast(&binning_params),
                .size = @sizeOf(BinningParams),
            };
            self.renderer.updateBuffer(data, 0, BinningParams, uniform_buffer_handle);

            // Update Descriptor Sets
            var binning_prepare_args_descriptor_set = self.gbuffer_bindings.binning_prepare_args_descriptor_set;
            var binning_classify_meshlets_descriptor_set = self.gbuffer_bindings.binning_classify_meshlets_descriptor_set;
            var binning_allocate_bin_ranges_descriptor_set = self.gbuffer_bindings.binning_allocate_bin_ranges_descriptor_set;
            var binning_write_bin_ranges_descriptor_set = self.gbuffer_bindings.binning_write_bin_ranges_descriptor_set;
            if (shadow_view) {
                binning_prepare_args_descriptor_set = self.shadows_bindings[cascade_index].binning_prepare_args_descriptor_set;
                binning_classify_meshlets_descriptor_set = self.shadows_bindings[cascade_index].binning_classify_meshlets_descriptor_set;
                binning_allocate_bin_ranges_descriptor_set = self.shadows_bindings[cascade_index].binning_allocate_bin_ranges_descriptor_set;
                binning_write_bin_ranges_descriptor_set = self.shadows_bindings[cascade_index].binning_write_bin_ranges_descriptor_set;
            }
            {
                var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);

                var params: [2]graphics.DescriptorData = undefined;
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "g_BinningParams";
                params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
                params[1] = std.mem.zeroes(graphics.DescriptorData);
                params[1].pName = "g_Frame";
                params[1].__union_field3.ppBuffers = @ptrCast(&frame_uniform_buffer);

                // These descriptor sets do not have g_Frame
                graphics.updateDescriptorSet(self.renderer.renderer, frame_index, binning_prepare_args_descriptor_set, 1, @ptrCast(&params));
                graphics.updateDescriptorSet(self.renderer.renderer, frame_index, binning_allocate_bin_ranges_descriptor_set, 1, @ptrCast(&params));

                graphics.updateDescriptorSet(self.renderer.renderer, frame_index, binning_classify_meshlets_descriptor_set, @intCast(params.len), @ptrCast(&params));
                graphics.updateDescriptorSet(self.renderer.renderer, frame_index, binning_write_bin_ranges_descriptor_set, @intCast(params.len), @ptrCast(&params));
            }

            // Binning: Prepare Args
            {
                const meshlet_count_buffer = self.renderer.getBuffer(self.meshlet_count_buffers);
                const meshlet_global_count_buffer = self.renderer.getBuffer(self.meshlet_global_count_buffers);
                const classify_meshes_dispatch_args_buffer = self.renderer.getBuffer(self.classify_meshes_dispatch_args_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_count_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(meshlet_global_count_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(classify_meshes_dispatch_args_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_prepare_args");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, binning_prepare_args_descriptor_set);
                graphics.cmdDispatch(cmd_list, 1, 1, 1);

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_count_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(meshlet_global_count_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Binning: Classify Meshlets
            {
                const classify_meshes_dispatch_args_buffer = self.renderer.getBuffer(self.classify_meshes_dispatch_args_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(classify_meshes_dispatch_args_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_INDIRECT_ARGUMENT),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_classify_meshlets");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, binning_classify_meshlets_descriptor_set);
                graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH, 1, classify_meshes_dispatch_args_buffer, 0, null, 0);
            }

            // Binning: Allocate Bin Ranges
            {
                const meshlet_offset_and_count_buffer = self.renderer.getBuffer(self.meshlet_offset_and_count_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_offset_and_count_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_allocate_bin_ranges");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, binning_allocate_bin_ranges_descriptor_set);
                graphics.cmdDispatch(cmd_list, 1, 1, 1);
            }

            // Binning: Write Bin Ranges
            {
                const classify_meshes_dispatch_args_buffer = self.renderer.getBuffer(self.classify_meshes_dispatch_args_buffers);
                const binned_meshlets_buffer = self.renderer.getBuffer(self.binned_meshlets_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(binned_meshlets_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_write_bin_ranges");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, binning_write_bin_ranges_descriptor_set);
                graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH, 1, classify_meshes_dispatch_args_buffer, 0, null, 0);

                const visible_meshlets_counters_buffer = self.renderer.getBuffer(self.visible_meshlets_counters_buffers);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(binned_meshlets_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(classify_meshes_dispatch_args_buffer, .RESOURCE_STATE_INDIRECT_ARGUMENT, .RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(visible_meshlets_counters_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }
        }

        // Rasterizer
        {
            const meshlet_offset_and_count_buffer = self.renderer.getBuffer(self.meshlet_offset_and_count_buffers);
            {
                const buffer_barriers = [_]graphics.BufferBarrier{
                    graphics.BufferBarrier.init(meshlet_offset_and_count_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_INDIRECT_ARGUMENT),
                };
                graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
            }

            for (self.pso_mgr.pso_bins.items, 0..) |pso_bin, bin_id| {
                var uniform_buffer_handle = self.gbuffer_bindings.meshlets_rasterizer_uniform_buffers[bin_id][frame_index];
                if (shadow_view) {
                    uniform_buffer_handle = self.shadows_bindings[cascade_index].meshlets_rasterizer_uniform_buffers[bin_id][frame_index];
                }

                var rasterizer_params = RasterizerParams{
                    .bin_index = @intCast(bin_id),
                    .binned_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.binned_meshlets_buffers),
                    .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers),
                    .meshlet_bin_data_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_offset_and_count_buffers),
                };

                const data_slice = OpaqueSlice{
                    .data = @ptrCast(&rasterizer_params),
                    .size = @sizeOf(RasterizerParams),
                };
                self.renderer.updateBuffer(data_slice, 0, RasterizerParams, uniform_buffer_handle);

                var descriptor_sets = self.gbuffer_bindings.meshlets_rasterizer_descriptor_sets[bin_id];
                if (shadow_view) {
                    descriptor_sets = self.shadows_bindings[cascade_index].meshlets_rasterizer_descriptor_sets[bin_id];
                }

                // Update Descriptor Set
                {
                    var uniform_buffer = self.renderer.getBuffer(uniform_buffer_handle);

                    var params: [2]graphics.DescriptorData = undefined;
                    params[0] = std.mem.zeroes(graphics.DescriptorData);
                    params[0].pName = "g_Frame";
                    params[0].__union_field3.ppBuffers = @ptrCast(&frame_uniform_buffer);
                    params[1] = std.mem.zeroes(graphics.DescriptorData);
                    params[1].pName = "g_RasterizerParams";
                    params[1].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                    graphics.updateDescriptorSet(self.renderer.renderer, frame_index, descriptor_sets, @intCast(params.len), @ptrCast(&params));
                }

                const pipeline = if (shadow_view) self.renderer.getPSO(pso_bin.shadow_caster_id) else self.renderer.getPSO(pso_bin.gbuffer_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, descriptor_sets);
                graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH_MESH, 1, meshlet_offset_and_count_buffer, bin_id * @sizeOf([4]u32), null, 0);
            }

            {
                const buffer_barriers = [_]graphics.BufferBarrier{
                    graphics.BufferBarrier.init(meshlet_offset_and_count_buffer, .RESOURCE_STATE_INDIRECT_ARGUMENT, .RESOURCE_STATE_COMMON),
                };
                graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
            }
        }
    }

    pub fn createDescriptorSets(self: *@This()) void {
        self.gbuffer_bindings.createDescriptorSets(false);

        for (0..renderer.Renderer.cascades_max_count) |cascade_index| {
            self.shadows_bindings[cascade_index].createDescriptorSets(true);
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("destroy_instances"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.destroy_instances_descriptor_set));
        }
    }

    pub fn prepareDescriptorSets(_: *@This()) void {}

    pub fn unloadDescriptorSets(self: *@This()) void {
        self.gbuffer_bindings.unloadDescriptorSets();

        for (0..renderer.Renderer.cascades_max_count) |cascade_index| {
            self.shadows_bindings[cascade_index].unloadDescriptorSets();
        }

        graphics.removeDescriptorSet(self.renderer.renderer, self.destroy_instances_descriptor_set);
    }
};

const PassBindings = struct {
    renderer: *renderer.Renderer,

    frame_culling_uniform_data: [frames_count]Frame,
    frame_uniform_buffers: [frames_count]BufferHandle,
    frame_culling_uniform_buffers: [frames_count]BufferHandle,
    clear_uav_uniform_buffers: [frames_count]BufferHandle,
    cull_instances_uniform_buffers: [frames_count]BufferHandle,
    build_meshlet_cull_args_uniform_buffers: [frames_count]BufferHandle,
    cull_meshlets_uniform_buffers: [frames_count]BufferHandle,
    binning_meshlets_uniform_buffers: [frames_count]BufferHandle,
    meshlets_rasterizer_uniform_buffers: [pso.pso_bins_max_count][frames_count]BufferHandle,

    clear_uav_descriptor_set: [*c]DescriptorSet,
    cull_instances_descriptor_set: [*c]DescriptorSet,
    build_meshlet_cull_args_descriptor_set: [*c]DescriptorSet,
    cull_meshlets_descriptor_set: [*c]DescriptorSet,
    binning_prepare_args_descriptor_set: [*c]DescriptorSet,
    binning_classify_meshlets_descriptor_set: [*c]DescriptorSet,
    binning_allocate_bin_ranges_descriptor_set: [*c]DescriptorSet,
    binning_write_bin_ranges_descriptor_set: [*c]DescriptorSet,
    meshlets_rasterizer_descriptor_sets: [pso.pso_bins_max_count]([*c]DescriptorSet),

    pub fn init(self: *@This(), rctx: *Renderer) void {
        self.renderer = rctx;

        // Frame Uniform Buffers
        self.frame_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(Frame);
            }

            break :blk buffers;
        };

        // Frame Culling Uniform Buffers
        self.frame_culling_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(Frame);
            }

            break :blk buffers;
        };

        // Clear UAV Uniform Buffers
        self.clear_uav_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ClearUavParams);
            }

            break :blk buffers;
        };

        // Cull Instances Uniform Buffers
        self.cull_instances_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(CullInstancesParams);
            }

            break :blk buffers;
        };

        // Build Meshlet Cull Args Uniform Buffers
        self.build_meshlet_cull_args_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(BuildMeshletsCullArgsParams);
            }

            break :blk buffers;
        };

        // Cull Meshlets Uniform Buffers
        self.cull_meshlets_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(CullMeshletsParams);
            }

            break :blk buffers;
        };

        // Meshlets Binning Uniform Buffers
        self.binning_meshlets_uniform_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(BinningParams);
            }

            break :blk buffers;
        };

        for (0..pso.pso_bins_max_count) |pso_index| {
            for (0..renderer.Renderer.data_buffer_count) |frame_index| {
                self.meshlets_rasterizer_uniform_buffers[pso_index][frame_index] = rctx.createUniformBuffer(RasterizerParams);
            }
        }
    }

    pub fn createDescriptorSets(self: *@This(), shadow_caster: bool) void {
        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_clear_counters"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.clear_uav_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_cull_instances"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.cull_instances_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_build_meshlets_cull_args"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.build_meshlet_cull_args_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_cull_meshlets"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.cull_meshlets_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_binning_prepare_args"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.binning_prepare_args_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_binning_classify_meshlets"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.binning_classify_meshlets_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_binning_allocate_bin_ranges"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.binning_allocate_bin_ranges_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("meshlet_binning_write_bin_ranges"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.binning_write_bin_ranges_descriptor_set));
        }

        for (self.renderer.pso_manager.pso_bins.items, 0..) |pso_bin, bin_id| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            if (shadow_caster) {
                desc.pRootSignature = self.renderer.getRootSignature(pso_bin.shadow_caster_id);
            } else {
                desc.pRootSignature = self.renderer.getRootSignature(pso_bin.gbuffer_id);
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.meshlets_rasterizer_descriptor_sets[bin_id]));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.clear_uav_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.cull_instances_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.build_meshlet_cull_args_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.cull_meshlets_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.binning_prepare_args_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.binning_classify_meshlets_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.binning_allocate_bin_ranges_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.binning_write_bin_ranges_descriptor_set);
        for (0..self.renderer.pso_manager.getPsoBinsCount()) |bin_id| {
            graphics.removeDescriptorSet(self.renderer.renderer, self.meshlets_rasterizer_descriptor_sets[bin_id]);
        }
    }
};
