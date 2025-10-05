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

const instancens_max_count = 1000000;
const meshlets_max_count = 1 << 20;
const EntityMap = std.AutoHashMap(u64, struct { index: usize, count: u32 });

const GpuInstanceFlags = packed struct(u32) {
    destroyed: u1,
    _padding: u31,
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

const GpuMeshletCandidate = struct {
    instance_id: u32,
    meshlet_index: u32,
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
    _padding0: u32,
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

    instances: std.ArrayList(GpuInstance),
    entity_maps: [frames_count]EntityMap,

    // Global Buffers
    instance_buffers: [frames_count]renderer.ElementBindlessBuffer,
    // Meshlet Culling Buffers
    candidate_meshlets_counters_buffers: [frames_count]BufferHandle,
    candidate_meshlets_buffers: [frames_count]BufferHandle,
    visible_meshlets_counters_buffers: [frames_count]BufferHandle,
    visible_meshlets_buffers: [frames_count]BufferHandle,
    meshlet_cull_args_buffers: [frames_count]BufferHandle,
    // Meshlet Binning Buffers
    meshlet_count_buffers: [frames_count]BufferHandle,
    meshlet_offset_and_count_buffers: [frames_count]BufferHandle,
    meshlet_global_count_buffers: [frames_count]BufferHandle,
    binned_meshlets_buffers: [frames_count]BufferHandle,
    classify_meshes_dispatch_args_buffers: [frames_count]BufferHandle,

    frame_uniform_buffers: [frames_count]BufferHandle,

    // Culling: All PSOs
    frame_culling_uniform_data: [frames_count]Frame,
    frame_culling_uniform_buffers: [frames_count]BufferHandle,
    // Culling: Clear Counters
    clear_uav_uniform_buffers: [frames_count]BufferHandle,
    clear_uav_descriptor_set: [*c]DescriptorSet,
    // Culling: Cull Instances
    cull_instances_uniform_buffers: [frames_count]BufferHandle,
    cull_instances_descriptor_set: [*c]DescriptorSet,
    // Culling: Build Meshlet Cull Args
    build_meshlet_cull_args_uniform_buffers: [frames_count]BufferHandle,
    build_meshlet_cull_args_descriptor_set: [*c]DescriptorSet,
    // Culling: Cull Meshlets
    cull_meshlets_uniform_buffers: [frames_count]BufferHandle,
    cull_meshlets_descriptor_set: [*c]DescriptorSet,
    // Binning: All PSOs
    binning_meshlets_uniform_buffers: [frames_count]BufferHandle,
    // Binning: Prepare Args
    binning_prepare_args_descriptor_set: [*c]DescriptorSet,
    binning_classify_meshlets_descriptor_set: [*c]DescriptorSet,
    binning_allocate_bin_ranges_descriptor_set: [*c]DescriptorSet,
    binning_write_bin_ranges_descriptor_set: [*c]DescriptorSet,
    // Rasterizer
    meshlets_rasterizer_uniform_buffers: std.ArrayList([frames_count]BufferHandle),
    meshlets_rasterizer_descriptor_sets: std.ArrayList([*c]DescriptorSet),

    pub fn init(self: *StaticGeometryPass, rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;
        self.pso_mgr = &rctx.pso_manager;

        // Global Buffers
        for (self.instance_buffers, 0..) |_, buffer_index| {
            self.instance_buffers[buffer_index].init(rctx, instancens_max_count, @sizeOf(GpuInstance), false, "GPU Instances");
        }

        // Meshlet Culling Buffers
        {
            self.candidate_meshlets_counters_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = 8 * @sizeOf(u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Candidate Meshlets Counters Buffer");
                }
                break :blk buffers;
            };

            self.candidate_meshlets_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = meshlets_max_count * @sizeOf(GpuMeshletCandidate),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Candidate Meshlets Buffer");
                }
                break :blk buffers;
            };

            self.visible_meshlets_counters_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = 8 * @sizeOf(u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Visible Meshlets Counters Buffer");
                }
                break :blk buffers;
            };

            self.visible_meshlets_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = meshlets_max_count * @sizeOf(GpuMeshletCandidate),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Visible Meshlets Buffer");
                }
                break :blk buffers;
            };

            self.meshlet_cull_args_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = 8 * @sizeOf(u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlets Cull Dispatch Args Buffer");
                }
                break :blk buffers;
            };
        }

        // Meshlet Binning Buffers
        {
            self.meshlet_count_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = 16 * @sizeOf(u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlet Binning: Meshlets Count");
                }
                break :blk buffers;
            };

            self.meshlet_offset_and_count_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = pso.pso_bins_max_count * @sizeOf([4]u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlet Binning: Meshlets Offset and Count");
                }
                break :blk buffers;
            };

            self.meshlet_global_count_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = 16 * @sizeOf(u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlet Binning: Meshlets Global Count");
                }
                break :blk buffers;
            };

            self.binned_meshlets_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = meshlets_max_count * @sizeOf(u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlet Binning: Binned Meshlets");
                }
                break :blk buffers;
            };

            self.classify_meshes_dispatch_args_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = @sizeOf([4]u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlet Binning: Classify Meshlets Dispatch Args");
                }
                break :blk buffers;
            };
        }

        // Uniform Buffers
        {
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

            self.meshlets_rasterizer_uniform_buffers = std.ArrayList([frames_count]BufferHandle).init(self.allocator);
            self.meshlets_rasterizer_descriptor_sets = std.ArrayList([*c]DescriptorSet).init(self.allocator);

            for (0..pso.pso_bins_max_count) |_| {
                const meshlets_rasterizer_uniform_buffers = blk: {
                    var buffers: [frames_count]renderer.BufferHandle = undefined;
                    for (buffers, 0..) |_, buffer_index| {
                        buffers[buffer_index] = rctx.createUniformBuffer(RasterizerParams);
                    }

                    break :blk buffers;
                };
                self.meshlets_rasterizer_uniform_buffers.append(meshlets_rasterizer_uniform_buffers) catch unreachable;
            }
        }

        self.instances = std.ArrayList(GpuInstance).init(self.allocator);
        self.entity_maps = blk: {
            var entity_maps: [frames_count]EntityMap = undefined;
            for (entity_maps, 0..) |_, index| {
                entity_maps[index] = EntityMap.init(self.allocator);
            }
            break :blk entity_maps;
        };
    }

    pub fn destroy(self: *@This()) void {
        self.instances.deinit();
        for (self.entity_maps, 0..) |_, index| {
            self.entity_maps[index].deinit();
        }

        self.meshlets_rasterizer_uniform_buffers.deinit();
        self.meshlets_rasterizer_descriptor_sets.deinit();
    }

    pub fn update(self: *@This()) void {
        const frame_index = self.renderer.frame_index;

        self.instances.clearRetainingCapacity();

        for (self.renderer.static_entitites.items) |static_entity| {
            if (self.entity_maps[frame_index].contains(static_entity.entity_id)) {
                continue;
            }

            const instance_buffer_index: usize = self.instance_buffers[frame_index].element_count + self.instances.items.len;
            var instances_count: u32 = 0;

            const renderable_data = self.renderer.getRenderable(static_entity.renderable_id);
            for (0..renderable_data.lods_count) |lod_index| {
                const mesh_info = self.renderer.getMeshInfo(renderable_data.lods[lod_index].mesh_id);

                for (0..mesh_info.count) |mesh_index_offset| {
                    const mesh = &self.renderer.meshes.items[mesh_info.index + mesh_index_offset];

                    const material_index = self.renderer.getMaterialIndex(renderable_data.lods[lod_index].materials[mesh_index_offset]);
                    var gpu_instance = std.mem.zeroes(GpuInstance);
                    zm.storeMat(&gpu_instance.world, zm.transpose(static_entity.world));
                    gpu_instance.id = @intCast(self.instance_buffers[frame_index].element_count + self.instances.items.len);
                    gpu_instance.mesh_index = @intCast(mesh_info.index + mesh_index_offset);
                    gpu_instance.material_index = @intCast(material_index);
                    gpu_instance.local_bounds_origin = mesh.bounds.center;
                    gpu_instance.local_bounds_extents = mesh.bounds.extents;
                    gpu_instance.screen_percentage_min = renderable_data.lods[lod_index].screen_percentage_range[0];
                    gpu_instance.screen_percentage_max = renderable_data.lods[lod_index].screen_percentage_range[1];
                    gpu_instance.flags = std.mem.zeroes(GpuInstanceFlags);

                    self.instances.append(gpu_instance) catch unreachable;
                    instances_count += 1;
                }
            }

            self.entity_maps[frame_index].put(static_entity.entity_id, .{ .index = instance_buffer_index, .count = instances_count }) catch unreachable;
        }

        if (self.instances.items.len > 0) {
            self.instance_buffers[frame_index].element_count += @intCast(self.instances.items.len);

            const instance_data = OpaqueSlice{
                .data = @ptrCast(self.instances.items),
                .size = self.instances.items.len * @sizeOf(GpuInstance),
            };

            std.debug.assert(self.instance_buffers[frame_index].size > instance_data.size + self.instance_buffers[frame_index].offset);
            self.renderer.updateBuffer(instance_data, self.instance_buffers[frame_index].offset, GpuInstance, self.instance_buffers[frame_index].buffer);
            self.instance_buffers[frame_index].offset += instance_data.size;
        }
    }

    pub fn renderImGui(self: *@This()) void {
        if (zgui.collapsingHeader("Static Geometry Renderer", .{})) {
            zgui.text("Total loaded instances: {d}", .{self.instance_buffers[self.renderer.frame_index].element_count});
            _ = zgui.checkbox("Freeze Culling", .{ .v = &self.render_settings.freeze_rendering });
        }
    }

    pub fn renderGBuffer(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "GPU Driven: GBuffer", 0x00_ff_00_00);
        defer trazy_zone.End();

        const frame_index = self.renderer.frame_index;

        self.renderer.gpu_gpu_driven_pass_profile_index = self.renderer.startGpuProfile(cmd_list, "GPU-Driven");
        defer self.renderer.endGpuProfile(cmd_list, self.renderer.gpu_gpu_driven_pass_profile_index);

        // Frame Uniform Buffer
        {
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
            frame._padding0 = 42;
            frame.instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index].buffer);
            frame.material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);
            frame.meshes_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.mesh_buffer.buffer);
            frame.instance_count = self.instance_buffers[frame_index].element_count;
            // TODO: Create a getSamplerBindlessIndex in renderer.zig
            frame.linear_repeat_sampler_index = @intCast(self.renderer.linear_repeat_sampler.*.mDx.mDescriptor);

            const frame_data = OpaqueSlice{
                .data = @ptrCast(&frame),
                .size = @sizeOf(Frame),
            };
            self.renderer.updateBuffer(frame_data, 0, Frame, self.frame_uniform_buffers[frame_index]);
        }

        // Frame Culling Uniform Buffer
        {
            if (!self.render_settings.freeze_rendering) {
                zm.storeMat(&self.frame_culling_uniform_data[frame_index].view, zm.transpose(render_view.view));
                zm.storeMat(&self.frame_culling_uniform_data[frame_index].proj, zm.transpose(render_view.projection));
                zm.storeMat(&self.frame_culling_uniform_data[frame_index].view_proj, zm.transpose(render_view.view_projection));
                zm.storeMat(&self.frame_culling_uniform_data[frame_index].view_proj_inv, zm.transpose(render_view.view_projection_inverse));
                self.frame_culling_uniform_data[frame_index].camera_position[0] = render_view.position[0];
                self.frame_culling_uniform_data[frame_index].camera_position[1] = render_view.position[1];
                self.frame_culling_uniform_data[frame_index].camera_position[2] = render_view.position[2];
                self.frame_culling_uniform_data[frame_index].camera_position[3] = 1.0;
                self.frame_culling_uniform_data[frame_index].camera_near_plane = render_view.near_plane;
                self.frame_culling_uniform_data[frame_index].camera_far_plane = render_view.far_plane;
            }

            self.frame_culling_uniform_data[frame_index].time = @floatCast(self.renderer.time);
            self.frame_culling_uniform_data[frame_index]._padding0 = 42;
            self.frame_culling_uniform_data[frame_index].instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index].buffer);
            self.frame_culling_uniform_data[frame_index].material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);
            self.frame_culling_uniform_data[frame_index].meshes_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.mesh_buffer.buffer);
            self.frame_culling_uniform_data[frame_index].instance_count = self.instance_buffers[frame_index].element_count;

            const frame_culling_data = OpaqueSlice{
                .data = @ptrCast(&self.frame_culling_uniform_data[frame_index]),
                .size = @sizeOf(Frame),
            };
            self.renderer.updateBuffer(frame_culling_data, 0, Frame, self.frame_culling_uniform_buffers[frame_index]);
        }

        // Meshlets Culling
        {
            // Clear UAV Counters
            {
                const candidate_meshlets_counters_buffer = self.renderer.getBuffer(self.candidate_meshlets_counters_buffers[frame_index]);
                const visible_meshlets_counters_buffer = self.renderer.getBuffer(self.visible_meshlets_counters_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(candidate_meshlets_counters_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(visible_meshlets_counters_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    const clear_uav_params = ClearUavParams{
                        .candidate_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers[frame_index]),
                        .visible_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers[frame_index]),
                    };
                    const clear_uav_params_data = OpaqueSlice{
                        .data = @ptrCast(&clear_uav_params),
                        .size = @sizeOf(ClearUavParams),
                    };
                    self.renderer.updateBuffer(clear_uav_params_data, 0, ClearUavParams, self.clear_uav_uniform_buffers[frame_index]);

                    const pipeline_id = ID("meshlet_clear_counters");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.clear_uav_descriptor_set);
                    graphics.cmdDispatch(cmd_list, 1, 1, 1);
                }
            }

            // Cull Instances
            {
                const candidate_meshlets_buffer = self.renderer.getBuffer(self.candidate_meshlets_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(candidate_meshlets_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    const cull_instances_params = CullInstancesParams{
                        .candidate_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_buffers[frame_index]),
                        .candidate_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers[frame_index]),
                    };

                    const cull_instances_params_data = OpaqueSlice{
                        .data = @ptrCast(&cull_instances_params),
                        .size = @sizeOf(CullInstancesParams),
                    };
                    self.renderer.updateBuffer(cull_instances_params_data, 0, CullInstancesParams, self.cull_instances_uniform_buffers[frame_index]);

                    const pipeline_id = ID("meshlet_cull_instances");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.cull_instances_descriptor_set);
                    const cull_instances_threads_count: u32 = 64;
                    const group_count_x = (self.instance_buffers[frame_index].element_count + cull_instances_threads_count - 1) / cull_instances_threads_count;
                    if (group_count_x > 0) {
                        graphics.cmdDispatch(cmd_list, group_count_x, 1, 1);
                    }
                }

                const candidate_meshlets_counters_buffer = self.renderer.getBuffer(self.candidate_meshlets_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(candidate_meshlets_counters_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Build Meshlet Cull Dispatch Arguments
            {
                const meshlets_cull_args_buffer = self.renderer.getBuffer(self.meshlet_cull_args_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlets_cull_args_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    const build_meshlets_cull_args_params = BuildMeshletsCullArgsParams{
                        .candidate_meshlets_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers[frame_index]),
                        .dispatch_args_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_cull_args_buffers[frame_index]),
                    };
                    const params_data = OpaqueSlice{
                        .data = @ptrCast(&build_meshlets_cull_args_params),
                        .size = @sizeOf(BuildMeshletsCullArgsParams),
                    };
                    self.renderer.updateBuffer(params_data, 0, BuildMeshletsCullArgsParams, self.build_meshlet_cull_args_uniform_buffers[frame_index]);

                    const pipeline_id = ID("meshlet_build_meshlets_cull_args");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.build_meshlet_cull_args_descriptor_set);
                    graphics.cmdDispatch(cmd_list, 1, 1, 1);
                }

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlets_cull_args_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Cull Meshlets
            {
                const visible_meshlet_buffer = self.renderer.getBuffer(self.visible_meshlets_buffers[frame_index]);
                const meshlet_cull_args_buffer = self.renderer.getBuffer(self.meshlet_cull_args_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(visible_meshlet_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(meshlet_cull_args_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_INDIRECT_ARGUMENT),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                {
                    const cull_meshlets_params = CullMeshletsParams{
                        .candidate_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_buffers[frame_index]),
                        .candidate_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.candidate_meshlets_counters_buffers[frame_index]),
                        .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers[frame_index]),
                        .visible_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers[frame_index]),
                    };

                    const cull_meshlets_params_data = OpaqueSlice{
                        .data = @ptrCast(&cull_meshlets_params),
                        .size = @sizeOf(CullMeshletsParams),
                    };
                    self.renderer.updateBuffer(cull_meshlets_params_data, 0, CullMeshletsParams, self.cull_meshlets_uniform_buffers[frame_index]);

                    const pipeline_id = ID("meshlet_cull_meshlets");
                    const pipeline = self.renderer.getPSO(pipeline_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.cull_meshlets_descriptor_set);
                    graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH, 1, meshlet_cull_args_buffer, 0, null, 0);
                }

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(visible_meshlet_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(meshlet_cull_args_buffer, graphics.ResourceState.RESOURCE_STATE_INDIRECT_ARGUMENT, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }
        }

        // Binning Meshets
        {
            var binning_params = BinningParams{
                .bins_count = @intCast(self.pso_mgr.getPsoBinsCount()),
                .meshlet_counts_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_count_buffers[frame_index]),
                .meshlet_offset_and_counts_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_offset_and_count_buffers[frame_index]),
                .global_meshlet_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_global_count_buffers[frame_index]),
                .binned_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.binned_meshlets_buffers[frame_index]),
                .dispatch_args_buffer_index = self.renderer.getBufferBindlessIndex(self.classify_meshes_dispatch_args_buffers[frame_index]),
                .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers[frame_index]),
                .visible_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers[frame_index]),
            };

            const data = OpaqueSlice{
                .data = @ptrCast(&binning_params),
                .size = @sizeOf(BinningParams),
            };
            self.renderer.updateBuffer(data, 0, BinningParams, self.binning_meshlets_uniform_buffers[frame_index]);

            // Binning: Prepare Args
            {
                const meshlet_count_buffer = self.renderer.getBuffer(self.meshlet_count_buffers[frame_index]);
                const meshlet_global_count_buffer = self.renderer.getBuffer(self.meshlet_global_count_buffers[frame_index]);
                const classify_meshes_dispatch_args_buffer = self.renderer.getBuffer(self.classify_meshes_dispatch_args_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_count_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(meshlet_global_count_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                        graphics.BufferBarrier.init(classify_meshes_dispatch_args_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_prepare_args");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.binning_prepare_args_descriptor_set);
                graphics.cmdDispatch(cmd_list, 1, 1, 1);

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_count_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(meshlet_global_count_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Binning: Classify Meshlets
            {
                const classify_meshes_dispatch_args_buffer = self.renderer.getBuffer(self.classify_meshes_dispatch_args_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(classify_meshes_dispatch_args_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_INDIRECT_ARGUMENT),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_classify_meshlets");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.binning_classify_meshlets_descriptor_set);
                graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH, 1, classify_meshes_dispatch_args_buffer, 0, null, 0);
            }

            // Binning: Allocate Bin Ranges
            {
                const meshlet_offset_and_count_buffer = self.renderer.getBuffer(self.meshlet_offset_and_count_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_offset_and_count_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_allocate_bin_ranges");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.binning_allocate_bin_ranges_descriptor_set);
                graphics.cmdDispatch(cmd_list, 1, 1, 1);
            }

            // Binning: Write Bin Ranges
            {
                const classify_meshes_dispatch_args_buffer = self.renderer.getBuffer(self.classify_meshes_dispatch_args_buffers[frame_index]);
                const binned_meshlets_buffer = self.renderer.getBuffer(self.binned_meshlets_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(binned_meshlets_buffer, graphics.ResourceState.RESOURCE_STATE_COMMON, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                const pipeline_id = ID("meshlet_binning_write_bin_ranges");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.binning_write_bin_ranges_descriptor_set);
                graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH, 1, classify_meshes_dispatch_args_buffer, 0, null, 0);

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(binned_meshlets_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_COMMON),
                        graphics.BufferBarrier.init(classify_meshes_dispatch_args_buffer, graphics.ResourceState.RESOURCE_STATE_INDIRECT_ARGUMENT, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // Rasterizer
            {
                const meshlet_offset_and_count_buffer = self.renderer.getBuffer(self.meshlet_offset_and_count_buffers[frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_offset_and_count_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_INDIRECT_ARGUMENT),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                for (self.pso_mgr.pso_bins.items, 0..) |pso_bin, bin_id| {
                    var rasterizer_params = RasterizerParams{
                        .bin_index = @intCast(bin_id),
                        .binned_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.binned_meshlets_buffers[frame_index]),
                        .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers[frame_index]),
                        .meshlet_bin_data_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_offset_and_count_buffers[frame_index]),
                    };

                    const data_slice = OpaqueSlice{
                        .data = @ptrCast(&rasterizer_params),
                        .size = @sizeOf(RasterizerParams),
                    };
                    self.renderer.updateBuffer(data_slice, 0, RasterizerParams, self.meshlets_rasterizer_uniform_buffers.items[bin_id][frame_index]);

                    const pipeline = self.renderer.getPSO(pso_bin.gbuffer_id);
                    graphics.cmdBindPipeline(cmd_list, pipeline);

                    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.meshlets_rasterizer_descriptor_sets.items[bin_id]);
                    graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DISPATCH_MESH, 1, meshlet_offset_and_count_buffer, bin_id * @sizeOf([4]u32), null, 0);
                }

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(meshlet_offset_and_count_buffer, graphics.ResourceState.RESOURCE_STATE_INDIRECT_ARGUMENT, graphics.ResourceState.RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }
        }
    }

    pub fn createDescriptorSets(self: *@This()) void {
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

        self.meshlets_rasterizer_descriptor_sets.clearRetainingCapacity();

        for (self.pso_mgr.pso_bins.items, 0..) |pso_bin, bin_id| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = frames_count;
            desc.pRootSignature = self.renderer.getRootSignature(pso_bin.gbuffer_id);
            self.meshlets_rasterizer_descriptor_sets.append(null) catch unreachable;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.meshlets_rasterizer_descriptor_sets.items[bin_id]));
        }
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        var params: [2]graphics.DescriptorData = undefined;

        for (0..frames_count) |i| {
            var frame_buffer = self.renderer.getBuffer(self.frame_culling_uniform_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_Frame";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

            var uniform_buffer = self.renderer.getBuffer(self.clear_uav_uniform_buffers[i]);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_ClearUAVParams";
            params[1].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.clear_uav_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }

        for (0..renderer.Renderer.data_buffer_count) |i| {
            var frame_buffer = self.renderer.getBuffer(self.frame_culling_uniform_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_Frame";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

            var cull_instances_params_buffer = self.renderer.getBuffer(self.cull_instances_uniform_buffers[i]);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_CullInstancesParams";
            params[1].__union_field3.ppBuffers = @ptrCast(&cull_instances_params_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.cull_instances_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }

        for (0..frames_count) |i| {
            var frame_buffer = self.renderer.getBuffer(self.frame_culling_uniform_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_Frame";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

            var uniform_buffer = self.renderer.getBuffer(self.build_meshlet_cull_args_uniform_buffers[i]);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_MeshletsCullArgsParams";
            params[1].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.build_meshlet_cull_args_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }

        for (0..renderer.Renderer.data_buffer_count) |i| {
            var frame_buffer = self.renderer.getBuffer(self.frame_culling_uniform_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_Frame";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

            var cull_meshlets_params_buffer = self.renderer.getBuffer(self.cull_meshlets_uniform_buffers[i]);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_CullMeshletsParams";
            params[1].__union_field3.ppBuffers = @ptrCast(&cull_meshlets_params_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.cull_meshlets_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }

        for (0..renderer.Renderer.data_buffer_count) |i| {
            var frame_buffer = self.renderer.getBuffer(self.frame_uniform_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_Frame";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

            var binning_meshlets_params_buffer = self.renderer.getBuffer(self.binning_meshlets_uniform_buffers[i]);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_BinningParams";
            params[1].__union_field3.ppBuffers = @ptrCast(&binning_meshlets_params_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.binning_prepare_args_descriptor_set, @intCast(params.len), @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.binning_classify_meshlets_descriptor_set, @intCast(params.len), @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.binning_allocate_bin_ranges_descriptor_set, @intCast(params.len), @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.binning_write_bin_ranges_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }

        for (0..self.pso_mgr.getPsoBinsCount()) |bin_id| {
            for (0..renderer.Renderer.data_buffer_count) |i| {
                var frame_buffer = self.renderer.getBuffer(self.frame_uniform_buffers[i]);
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "g_Frame";
                params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

                var meshlet_rasterizer_buffer = self.renderer.getBuffer(self.meshlets_rasterizer_uniform_buffers.items[bin_id][i]);
                params[1] = std.mem.zeroes(graphics.DescriptorData);
                params[1].pName = "g_RasterizerParams";
                params[1].__union_field3.ppBuffers = @ptrCast(&meshlet_rasterizer_buffer);

                graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.meshlets_rasterizer_descriptor_sets.items[bin_id], @intCast(params.len), @ptrCast(&params));
            }
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
        for (0..self.pso_mgr.getPsoBinsCount()) |bin_id| {
            graphics.removeDescriptorSet(self.renderer.renderer, self.meshlets_rasterizer_descriptor_sets.items[bin_id]);
        }
    }
};
