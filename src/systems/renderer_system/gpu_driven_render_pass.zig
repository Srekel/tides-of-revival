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

const graphics = zforge.graphics;
const DescriptorSet = graphics.DescriptorSet;
const Renderer = renderer.Renderer;
const frames_count = Renderer.data_buffer_count;
const BufferHandle = renderer.BufferHandle;
const RenderPass = renderer.RenderPass;
const InstanceData = renderer_types.InstanceData;
const InstanceDataIndirection = renderer_types.InstanceDataIndirection;

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

const renderer_buckets: u32 = 2;
const renderer_bucket_opaque: u32 = 1;
const renderer_bucket_masked: u32 = 0;

pub const GpuDrivenRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *Renderer,
    render_pass: RenderPass,
    prefab_mgr: *PrefabManager,
    // query_gpu_driven_mesh: *ecs.query_t,

    gbuffer_frame_data: GBufferFrameData,
    gbuffer_frame_data_buffers: [frames_count]BufferHandle,
    gbuffer_descriptor_sets: [renderer_buckets][*c]DescriptorSet,

    // TODO: Do we need to double-buffer these as well?
    instance_buffer: BufferHandle,
    instance_indirection_buffer: BufferHandle,

    temporary_mesh: renderer.MeshHandle,
    first_update: bool,

    pub fn init(self: *GpuDrivenRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, prefab_mgr: *PrefabManager, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.ecsu_world = ecsu_world;
        self.renderer = rctx;
        self.prefab_mgr = prefab_mgr;

        self.gbuffer_frame_data = std.mem.zeroes(GBufferFrameData);
        self.gbuffer_frame_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(GBufferFrameData);
            }

            break :blk buffers;
        };

        self.instance_buffer = blk: {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = 1024 * @sizeOf(InstanceData),
            };
            break :blk rctx.createBindlessBuffer(buffer_data, "GPU Instances");
        };

        self.instance_indirection_buffer = blk: {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = 1024 * geometry.sub_mesh_max_count * @sizeOf(InstanceDataIndirection),
            };
            break :blk rctx.createBindlessBuffer(buffer_data, "GPU Instances");
        };

        // TESTING NEW MESH LOADING
        self.temporary_mesh = self.renderer.loadMesh("content/prefabs/environment/beech/beech_tree_04_LOD0.mesh") catch unreachable;
        self.first_update = true;


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

        unloadDescriptorSets(@ptrCast(self));
    }
};

fn update(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    if (self.first_update) {
        var instance = std.mem.zeroes(InstanceData);
        const z_world = zm.translation(9168.0, 124.4, 8645.0);
        zm.storeMat(&instance.object_to_world, z_world);

        const instance_data = renderer.Slice{
            .data = @ptrCast(&instance),
            .size = @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data, 0, InstanceData, self.instance_buffer);

        var instance_indirections = std.ArrayList(InstanceDataIndirection).init(self.allocator);
        defer instance_indirections.deinit();

        const trunk_material_handle = self.renderer.getMaterialHandle(ID("beech_trunk_04")).?;
        const trunk_material_index = self.renderer.getMaterialBufferOffset(trunk_material_handle);

        const atlas_material_handle = self.renderer.getMaterialHandle(ID("beech_atlas_v2")).?;
        const atlas_material_index = self.renderer.getMaterialBufferOffset(atlas_material_handle);

        const indices = self.renderer.getGpuMeshIndices(self.temporary_mesh);
        for (0..indices.count) |index| {
            std.log.debug("Mesh index: {d}", .{indices.indices[index]});
            var instance_indirection = std.mem.zeroes(InstanceDataIndirection);
            instance_indirection.gpu_mesh_index = indices.indices[index];
            instance_indirection.instance_index = 0;
            instance_indirection.material_index = if (index == 0) trunk_material_index else atlas_material_index;
            instance_indirections.append(instance_indirection) catch unreachable;
        }

        const instance_indirection_data = renderer.Slice{
            .data = @ptrCast(instance_indirections.items),
            .size = instance_indirections.items.len * @sizeOf(InstanceDataIndirection),
        };
        self.renderer.updateBuffer(instance_indirection_data, 0, InstanceDataIndirection, self.instance_indirection_buffer);

        self.first_update = false;
    }
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
    const z_proj_view = zm.loadMat(camera_comps.camera.view_projection[0..]);

    zm.storeMat(&self.gbuffer_frame_data.projection_view, z_proj_view);
    zm.storeMat(&self.gbuffer_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
    self.gbuffer_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
    self.gbuffer_frame_data.time = @floatCast(self.renderer.time); // keep f64?
    self.gbuffer_frame_data.instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffer);
    self.gbuffer_frame_data.instance_indirection_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_indirection_buffer);
    self.gbuffer_frame_data.gpu_mesh_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.gpu_mesh_buffer);
    self.gbuffer_frame_data.vertex_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.vertex_buffer);
    self.gbuffer_frame_data.material_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.materials_buffer);

    // Update Uniform Frame Buffer
    {
        const data = renderer.Slice{
            .data = @ptrCast(&self.gbuffer_frame_data),
            .size = @sizeOf(GBufferFrameData),
        };
        self.renderer.updateBuffer(data, 0, GBufferFrameData, self.gbuffer_frame_data_buffers[frame_index]);
    }

    const index_buffer = self.renderer.getBuffer(self.renderer.index_buffer);
    graphics.cmdBindIndexBuffer(cmd_list, index_buffer, @intCast(graphics.IndexType.INDEX_TYPE_UINT32.bits), 0);

    const mesh = self.renderer.getMesh(self.temporary_mesh);

    {
        const pipeline_id = IdLocal.init("gpu_driven_gbuffer_opaque");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.gbuffer_descriptor_sets[renderer_bucket_opaque]);

        graphics.cmdDrawIndexedInstanced(
            cmd_list,
            mesh.sub_meshes[0].index_count,
            mesh.sub_meshes[0].index_offset,
            1,
            mesh.sub_meshes[0].vertex_offset,
            0,
        );
    }

    {
        const pipeline_id = IdLocal.init("gpu_driven_gbuffer_masked");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.gbuffer_descriptor_sets[renderer_bucket_masked]);

        graphics.cmdDrawIndexedInstanced(
            cmd_list,
            mesh.sub_meshes[1].index_count,
            mesh.sub_meshes[1].index_offset,
            1,
            mesh.sub_meshes[1].vertex_offset,
            1,
        );
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    const gbuffer_descriptor_sets = blk: {
        const root_signature_opaque = self.renderer.getRootSignature(IdLocal.init("gpu_driven_gbuffer_opaque"));
        const root_signature_masked = self.renderer.getRootSignature(IdLocal.init("gpu_driven_gbuffer_masked"));

        var gbuffer_descriptor_sets: [renderer_buckets][*c]graphics.DescriptorSet = undefined;
        for (gbuffer_descriptor_sets, 0..) |_, index| {
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            if (index == renderer_bucket_opaque) {
                desc.pRootSignature = root_signature_opaque;
            } else {
                desc.pRootSignature = root_signature_masked;
            }
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&gbuffer_descriptor_sets[index]));
        }

        break :blk gbuffer_descriptor_sets;
    };
    self.gbuffer_descriptor_sets = gbuffer_descriptor_sets;
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    var params: [2]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.gbuffer_frame_data_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.gbuffer_descriptor_sets[renderer_bucket_opaque], 1, @ptrCast(&params));
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.gbuffer_descriptor_sets[renderer_bucket_masked], 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *GpuDrivenRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.gbuffer_descriptor_sets[renderer_bucket_opaque]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.gbuffer_descriptor_sets[renderer_bucket_masked]);
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