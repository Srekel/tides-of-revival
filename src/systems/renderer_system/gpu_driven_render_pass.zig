const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const ID = @import("../../core/core.zig").ID;
const renderer = @import("../../renderer/renderer.zig");
const geometry = @import("../../renderer/geometry.zig");
const renderer_types = @import("../../renderer/types.zig");
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");
const zgui = @import("zgui");
const im3d = @import("im3d");

const graphics = zforge.graphics;
const DescriptorSet = graphics.DescriptorSet;
const Renderer = renderer.Renderer;
const frames_count = Renderer.data_buffer_count;
const renderer_bins_count = renderer.renderer_bins_count;
const BufferHandle = renderer.BufferHandle;
const RenderPass = renderer.RenderPass;
const InstanceData = renderer_types.InstanceData;
const InstanceDataIndirection = renderer_types.InstanceDataIndirection;

const instancens_max_count = 1000000;
const meshlets_max_count = 1 << 20;
// NOTE: This could be a set, but it is a hashmap because we might want to store the GPU index as the value to evict instances that are streamed out
const EntityMap = std.AutoHashMap(ecs.entity_t, bool);

const GpuInstance = struct {
    world: [16]f32,
    local_bounds_origin: [3]f32,
    _pad0: u32,
    local_bounds_extents: [3]f32,
    id: u32,
    mesh_index: u32,
    material_index: u32,
    _pad1: [2]u32,
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

pub const GpuDrivenRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *Renderer,
    render_pass: RenderPass,
    prefab_mgr: *PrefabManager,
    query_renderables: *ecs.query_t,
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
    meshlets_rasterizer_uniform_buffers: [renderer_bins_count][frames_count]BufferHandle,
    meshlets_rasterizer_descriptor_sets: [renderer_bins_count][*c]DescriptorSet,

    pub fn init(self: *GpuDrivenRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, prefab_mgr: *PrefabManager, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.ecsu_world = ecsu_world;
        self.renderer = rctx;
        self.prefab_mgr = prefab_mgr;

        // Global Buffers
        for (self.instance_buffers, 0..) |_, buffer_index| {
            self.instance_buffers[buffer_index].init(rctx, instancens_max_count, @sizeOf(GpuInstance), false, "GPU Instances");
        }

        // Meshlet Culling Buffers
        {
            self.candidate_meshlets_counters_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = renderer_bins_count * @sizeOf([4]u32),
                };
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Meshlet Binning: Meshlets Offset and Count");
                }
                break :blk buffers;
            };

            self.meshlet_global_count_buffers = blk: {
                var buffers: [frames_count]renderer.BufferHandle = undefined;
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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
                const buffer_data = renderer.Slice{
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

            for (0..renderer_bins_count) |bin_id| {
                self.meshlets_rasterizer_uniform_buffers[bin_id] = blk: {
                    var buffers: [frames_count]renderer.BufferHandle = undefined;
                    for (buffers, 0..) |_, buffer_index| {
                        buffers[buffer_index] = rctx.createUniformBuffer(RasterizerParams);
                    }

                    break :blk buffers;
                };
            }
        }

        self.query_renderables = ecs.query_init(ecsu_world.world, &.{
            .entity = ecs.new_entity(ecsu_world.world, "query_renderables"),
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(fd.Renderable), .inout = .In },
                .{ .id = ecs.id(fd.Transform), .inout = .In },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
        }) catch unreachable;

        self.instances = std.ArrayList(GpuInstance).init(self.allocator);
        self.entity_maps = blk: {
            var entity_maps: [frames_count]EntityMap = undefined;
            for (entity_maps, 0..) |_, index| {
                entity_maps[index] = EntityMap.init(self.allocator);
            }
            break :blk entity_maps;
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .update_fn = update,
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_gbuffer_pass_fn = renderGBuffer,
            .render_imgui_fn = renderImGui,
            .render_shadow_pass_fn = null,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *GpuDrivenRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);
        self.instances.deinit();
        for (self.entity_maps, 0..) |_, index| {
            self.entity_maps[index].deinit();
        }
        unloadDescriptorSets(@ptrCast(self));
    }
};

fn update(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    self.instances.clearRetainingCapacity();

    var query_renderables_iter = ecs.query_iter(self.ecsu_world.world, self.query_renderables);
    while (ecs.query_next(&query_renderables_iter)) {
        const renderables = ecs.field(&query_renderables_iter, fd.Renderable, 0).?;
        const transforms = ecs.field(&query_renderables_iter, fd.Transform, 1).?;

        for (renderables, transforms, 0..) |renderable, transform, entity_index| {
            const entity_id: ecs.entity_t = query_renderables_iter.entities()[entity_index];
            if (self.entity_maps[frame_index].contains(entity_id)) {
                continue;
            }

            const renderable_data = self.renderer.getRenderable(renderable.id);
            const mesh_info = self.renderer.getMeshInfo(renderable_data.mesh_id);

            for (0..mesh_info.count) |mesh_index_offset| {
                const mesh = &self.renderer.meshes.items[mesh_info.index + mesh_index_offset];
                const material_index = self.renderer.getMaterialIndex(renderable_data.materials[mesh_index_offset]);
                var gpu_instance = std.mem.zeroes(GpuInstance);
                var world: [16]f32 = undefined;
                storeMat44(transform.matrix[0..], world[0..]);
                const z_world = zm.loadMat(&world);
                zm.storeMat(&gpu_instance.world, zm.transpose(z_world));
                gpu_instance.id = @intCast(self.instance_buffers[frame_index].element_count + self.instances.items.len);
                gpu_instance.mesh_index = @intCast(mesh_info.index + mesh_index_offset);
                gpu_instance.material_index = @intCast(material_index);
                gpu_instance.local_bounds_origin = mesh.bounds.center;
                gpu_instance.local_bounds_extents = mesh.bounds.extents;

                self.instances.append(gpu_instance) catch unreachable;
            }

            self.entity_maps[frame_index].put(entity_id, true) catch unreachable;
        }
    }

    if (self.instances.items.len > 0) {
        self.instance_buffers[frame_index].element_count += @intCast(self.instances.items.len);
        // std.log.debug("Loaded instances: {d}", .{self.instance_buffers[frame_index].element_count});

        const instance_data = renderer.Slice{
            .data = @ptrCast(self.instances.items),
            .size = self.instances.items.len * @sizeOf(GpuInstance),
        };

        std.debug.assert(self.instance_buffers[frame_index].size > instance_data.size + self.instance_buffers[frame_index].offset);
        self.renderer.updateBuffer(instance_data, self.instance_buffers[frame_index].offset, GpuInstance, self.instance_buffers[frame_index].buffer);
        self.instance_buffers[frame_index].offset += instance_data.size;
    }
}

fn renderImGui(user_data: *anyopaque) void {
    if (zgui.collapsingHeader("GPU Driven Renderer", .{})) {
        const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

        _ = zgui.checkbox("Freeze Culling", .{ .v = &self.render_settings.freeze_rendering });    }
}

fn renderGBuffer(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "GPU Driven: GBuffer", 0x00_ff_00_00);
    defer trazy_zone.End();

    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();
    const z_view = zm.loadMat(camera_comps.camera.view[0..]);
    const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
    const z_view_proj = zm.loadMat(camera_comps.camera.view_projection[0..]);

    // Frame Uniform Buffer
    {
        var frame = std.mem.zeroes(Frame);

        zm.storeMat(&frame.view, zm.transpose(z_view));
        zm.storeMat(&frame.proj, zm.transpose(z_proj));
        zm.storeMat(&frame.view_proj, zm.transpose(z_view_proj));
        zm.storeMat(&frame.view_proj_inv, zm.transpose(zm.inverse(z_view_proj)));
        frame.camera_position[0] = camera_position[0];
        frame.camera_position[1] = camera_position[1];
        frame.camera_position[2] = camera_position[2];
        frame.camera_position[3] = 1.0;
        frame.camera_near_plane = camera_comps.camera.near;
        frame.camera_far_plane = camera_comps.camera.far;
        frame.time = @floatCast(self.renderer.time);
        frame._padding0 = 42;
        frame.instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index].buffer);
        frame.material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);
        frame.meshes_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.mesh_buffer.buffer);
        frame.instance_count = self.instance_buffers[frame_index].element_count;

        const frame_data = renderer.Slice{
            .data = @ptrCast(&frame),
            .size = @sizeOf(Frame),
        };
        self.renderer.updateBuffer(frame_data, 0, Frame, self.frame_uniform_buffers[frame_index]);
    }

    // Frame Culling Uniform Buffer
    {
        if (!self.render_settings.freeze_rendering) {
            zm.storeMat(&self.frame_culling_uniform_data[frame_index].view, zm.transpose(z_view));
            zm.storeMat(&self.frame_culling_uniform_data[frame_index].proj, zm.transpose(z_proj));
            zm.storeMat(&self.frame_culling_uniform_data[frame_index].view_proj, zm.transpose(z_view_proj));
            zm.storeMat(&self.frame_culling_uniform_data[frame_index].view_proj_inv, zm.transpose(zm.inverse(z_view_proj)));
            self.frame_culling_uniform_data[frame_index].camera_position[0] = camera_position[0];
            self.frame_culling_uniform_data[frame_index].camera_position[1] = camera_position[1];
            self.frame_culling_uniform_data[frame_index].camera_position[2] = camera_position[2];
            self.frame_culling_uniform_data[frame_index].camera_position[3] = 1.0;
            self.frame_culling_uniform_data[frame_index].camera_near_plane = camera_comps.camera.near;
            self.frame_culling_uniform_data[frame_index].camera_far_plane = camera_comps.camera.far;
        }

        self.frame_culling_uniform_data[frame_index].time = @floatCast(self.renderer.time);
        self.frame_culling_uniform_data[frame_index]._padding0 = 42;
        self.frame_culling_uniform_data[frame_index].instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index].buffer);
        self.frame_culling_uniform_data[frame_index].material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.material_buffer.buffer);
        self.frame_culling_uniform_data[frame_index].meshes_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.mesh_buffer.buffer);
        self.frame_culling_uniform_data[frame_index].instance_count = self.instance_buffers[frame_index].element_count;

        const frame_culling_data = renderer.Slice{
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
                const clear_uav_params_data = renderer.Slice{
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

                const cull_instances_params_data = renderer.Slice{
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
                const params_data = renderer.Slice{
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

                const cull_meshlets_params_data = renderer.Slice{
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
            .bins_count = renderer_bins_count,
            .meshlet_counts_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_count_buffers[frame_index]),
            .meshlet_offset_and_counts_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_offset_and_count_buffers[frame_index]),
            .global_meshlet_counter_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_global_count_buffers[frame_index]),
            .binned_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.binned_meshlets_buffers[frame_index]),
            .dispatch_args_buffer_index = self.renderer.getBufferBindlessIndex(self.classify_meshes_dispatch_args_buffers[frame_index]),
            .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers[frame_index]),
            .visible_meshlets_counters_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_counters_buffers[frame_index]),
        };

        const data = renderer.Slice{
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

            for (0..renderer_bins_count) |bin_id| {
                var rasterizer_params = RasterizerParams{
                    .bin_index = @intCast(bin_id),
                    .binned_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.binned_meshlets_buffers[frame_index]),
                    .visible_meshlets_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_meshlets_buffers[frame_index]),
                    .meshlet_bin_data_buffer_index = self.renderer.getBufferBindlessIndex(self.meshlet_offset_and_count_buffers[frame_index]),
                };

                const data_slice = renderer.Slice{
                    .data = @ptrCast(&rasterizer_params),
                    .size = @sizeOf(RasterizerParams),
                };
                self.renderer.updateBuffer(data_slice, 0, RasterizerParams, self.meshlets_rasterizer_uniform_buffers[bin_id][frame_index]);

                // TODO: Make a list of pipelines
                if (bin_id == 0) {
                    const pipeline = self.renderer.getPSO(IdLocal.init("meshlet_gbuffer_opaque"));
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                } else {
                    const pipeline = self.renderer.getPSO(IdLocal.init("meshlet_gbuffer_masked"));
                    graphics.cmdBindPipeline(cmd_list, pipeline);
                }

                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.meshlets_rasterizer_descriptor_sets[bin_id]);
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

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

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

    for (0..renderer_bins_count) |bin_id| {
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = frames_count;

        // TODO: Make a list of pipelines
        if (bin_id == 0) {
            desc.pRootSignature = self.renderer.getRootSignature(IdLocal.init("meshlet_gbuffer_opaque"));
        } else {
            desc.pRootSignature = self.renderer.getRootSignature(IdLocal.init("meshlet_gbuffer_masked"));
        }
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.meshlets_rasterizer_descriptor_sets[bin_id]));
    }
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

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

    for (0..renderer_bins_count) |bin_id| {
        for (0..renderer.Renderer.data_buffer_count) |i| {
            var frame_buffer = self.renderer.getBuffer(self.frame_uniform_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_Frame";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

            var meshlet_rasterizer_buffer = self.renderer.getBuffer(self.meshlets_rasterizer_uniform_buffers[bin_id][i]);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_RasterizerParams";
            params[1].__union_field3.ppBuffers = @ptrCast(&meshlet_rasterizer_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.meshlets_rasterizer_descriptor_sets[bin_id], @intCast(params.len), @ptrCast(&params));
        }
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.clear_uav_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.cull_instances_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.build_meshlet_cull_args_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.cull_meshlets_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.binning_prepare_args_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.binning_classify_meshlets_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.binning_allocate_bin_ranges_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.binning_write_bin_ranges_descriptor_set);
    for (0..renderer_bins_count) |bin_id| {
        graphics.removeDescriptorSet(self.renderer.renderer, self.meshlets_rasterizer_descriptor_sets[bin_id]);
    }
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
