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
const im3d = @import("im3d");

const graphics = zforge.graphics;
const DescriptorSet = graphics.DescriptorSet;
const Renderer = renderer.Renderer;
const frames_count = Renderer.data_buffer_count;
const BufferHandle = renderer.BufferHandle;
const RenderPass = renderer.RenderPass;
const InstanceData = renderer_types.InstanceData;
const InstanceDataIndirection = renderer_types.InstanceDataIndirection;

const max_instances = 1000000;
const max_visible_instances = 10000;
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

pub const GBufferFrameData = struct {
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
    time: f32,
    instance_buffer_index: u32,
    instance_indirection_buffer_index: u32,
    gpu_mesh_buffer_index: u32,
    vertex_buffer_index: u32,
    material_buffer_index: u32,
};

pub const GpuCullingFrameData = struct {
    projection_view: [16]f32,
    counters_buffer_index: u32,
    counters_buffer_count: u32,
    instance_buffer_index: u32,
    instance_indirection_buffer_index: u32,
    instance_indirection_count: u32,
    visible_instance_indirection_buffer_index: u32,
    gpu_mesh_buffer_index: u32,
};

pub const GpuDrivenRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *Renderer,
    render_pass: RenderPass,
    prefab_mgr: *PrefabManager,
    query_renderables: *ecs.query_t,

    gbuffer_frame_data: GBufferFrameData,
    gbuffer_frame_data_buffers: [frames_count]BufferHandle,
    gbuffer_descriptor_sets: [renderer.renderer_buckets][*c]DescriptorSet,

    instances: std.ArrayList(GpuInstance),
    entity_maps: [frames_count]EntityMap,

    instance_buffers: [frames_count]renderer.ElementBindlessBuffer,
    counters_buffers: [frames_count]BufferHandle,

    gpu_culling_frame_data: GpuCullingFrameData,
    gpu_culling_frame_data_buffers: [frames_count]BufferHandle,
    gpu_culling_clear_counters_descriptor_set: [*c]DescriptorSet,
    gpu_culling_cull_instances_descriptor_set: [*c]DescriptorSet,

    pub fn init(self: *GpuDrivenRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, prefab_mgr: *PrefabManager, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.ecsu_world = ecsu_world;
        self.renderer = rctx;
        self.prefab_mgr = prefab_mgr;

        self.gbuffer_frame_data = std.mem.zeroes(GBufferFrameData);
        self.gbuffer_frame_data_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(GBufferFrameData);
            }

            break :blk buffers;
        };

        for (self.instance_buffers, 0..) |_, buffer_index| {
            self.instance_buffers[buffer_index].init(rctx, max_instances, @sizeOf(GpuInstance), false, "GPU Instances");
        }

        self.counters_buffers = blk: {
            var buffers: [frames_count]renderer.BufferHandle = undefined;
            const buffer_data = renderer.Slice{
                .data = null,
                .size = 32 * @sizeOf(u32),
            };
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, true, "Counters Buffer");
            }
            break :blk buffers;
        };

        self.gpu_culling_frame_data = std.mem.zeroes(GpuCullingFrameData);
        self.gpu_culling_frame_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(GpuCullingFrameData);
            }

            break :blk buffers;
        };

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

            const renderable_data = self .renderer.getRenderable(renderable.id);
            const mesh_info = self.renderer.getMeshInfo(renderable_data.mesh_id);

            for (0..mesh_info.count) |mesh_index_offset| {
                const mesh = &self.renderer.meshes.items[mesh_info.index + mesh_index_offset];
                const material_index = self.renderer.getMaterialIndex(renderable_data.materials[mesh_index_offset]);
                var gpu_instance = std.mem.zeroes(GpuInstance);
                storeMat44(transform.matrix[0..], gpu_instance.world[0..]);
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

        const instance_data = renderer.Slice{
            .data = @ptrCast(self.instances.items),
            .size = self.instances.items.len * @sizeOf(GpuInstance),
        };

        std.debug.assert(self.instance_buffers[frame_index].size > instance_data.size + self.instance_buffers[frame_index].offset);
        self.renderer.updateBuffer(instance_data, self.instance_buffers[frame_index].offset, GpuInstance, self.instance_buffers[frame_index].buffer);
        self.instance_buffers[frame_index].offset += instance_data.size;
    }
}

fn renderGBuffer(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "GPU Driven: GBuffer", 0x00_ff_00_00);
    defer trazy_zone.End();

    _ = cmd_list;
    _ = user_data;

    // const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));
    // const frame_index = self.renderer.frame_index;

    // var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    // const camera_comps = camera_entity.getComps(struct {
    //     camera: *const fd.Camera,
    //     transform: *const fd.Transform,
    // });
    // const camera_position = camera_comps.transform.getPos00();
    // const z_view_proj = zm.loadMat(camera_comps.camera.view_projection[0..]);

}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    const gbuffer_descriptor_sets = blk: {
        const root_signature_opaque = self.renderer.getRootSignature(IdLocal.init("gpu_driven_gbuffer_opaque"));
        const root_signature_masked = self.renderer.getRootSignature(IdLocal.init("gpu_driven_gbuffer_masked"));

        var gbuffer_descriptor_sets: [renderer.renderer_buckets][*c]graphics.DescriptorSet = undefined;
        for (gbuffer_descriptor_sets, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == renderer.renderer_bucket_opaque) {
                desc.pRootSignature = root_signature_opaque;
            } else {
                desc.pRootSignature = root_signature_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&gbuffer_descriptor_sets[index]));
        }

        break :blk gbuffer_descriptor_sets;
    };
    self.gbuffer_descriptor_sets = gbuffer_descriptor_sets;

    {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("gpu_culling_clear_counters"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.gpu_culling_clear_counters_descriptor_set));
    }

    {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("gpu_culling_cull_instances"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.gpu_culling_cull_instances_descriptor_set));
    }
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    var params: [1]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.gbuffer_frame_data_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.gbuffer_descriptor_sets[renderer.renderer_bucket_opaque], 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.gbuffer_descriptor_sets[renderer.renderer_bucket_masked], 1, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.gpu_culling_frame_data_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.gpu_culling_clear_counters_descriptor_set, 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.gpu_culling_cull_instances_descriptor_set, 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.gbuffer_descriptor_sets[renderer.renderer_bucket_opaque]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.gbuffer_descriptor_sets[renderer.renderer_bucket_masked]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.gpu_culling_clear_counters_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.gpu_culling_cull_instances_descriptor_set);
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
