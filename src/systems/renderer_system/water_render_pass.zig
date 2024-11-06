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
    time: f32,
};

const InstanceData = struct {
    object_to_world: [16]f32,
    world_to_object: [16]f32,
};

const DrawCallPushConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
};

const max_instances = 1024;

pub const WaterRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    query_water: ecsu.Query,

    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_sets: [*c]graphics.DescriptorSet,

    instance_data: std.ArrayList(InstanceData),
    instance_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    pub fn init(self: *WaterRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
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
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Water Instance Data");
            }

            break :blk buffers;
        };

        var query_builder_water = ecsu.QueryBuilder.init(ecsu_world);
        _ = query_builder_water
            .withReadonly(fd.Transform)
            .withReadonly(fd.Water);
        const query_water = query_builder_water.buildQuery();

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .descriptor_sets = undefined,
            .instance_data = std.ArrayList(InstanceData).init(allocator),
            .instance_data_buffers = instance_data_buffers,
            .query_water = query_water,
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_water_pass_fn =  render,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *WaterRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);
        self.query_water.deinit();

        unloadDescriptorSets(@ptrCast(self));
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Water Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();
    const z_proj_view = zm.loadMat(camera_comps.camera.view_projection[0..]);

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

    self.instance_data.clearRetainingCapacity();
    var entity_iterator = self.query_water.iterator(struct {
        transform: *const fd.Transform,
        water: *const fd.Water,
    });
    var first_iteration = true;
    var mesh: renderer.Mesh = undefined;
    while (entity_iterator.next()) |comps| {
        if (first_iteration) {
            first_iteration = false;

            mesh = self.renderer.getMesh(comps.water.mesh_handle);
        }

        var instance_data = std.mem.zeroes(InstanceData);
        storeMat44(comps.transform.matrix[0..], &instance_data.object_to_world);
        storeMat44(comps.transform.inv_matrix[0..], &instance_data.world_to_object);
        self.instance_data.append(instance_data) catch unreachable;
    }

    if (self.instance_data.items.len > 0) {
        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(self.instance_data.items),
            .size = self.instance_data.items.len * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(instance_data_slice, InstanceData, self.instance_data_buffers[frame_index]);

        const pipeline_id = IdLocal.init("water");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets);

        var input_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_DEPTH_READ),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

        var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
        bind_render_targets_desc.mRenderTargetCount = 1;
        bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.renderer.scene_color;
        bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;
        bind_render_targets_desc.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
        bind_render_targets_desc.mDepthStencil.pDepthStencil = self.renderer.depth_buffer;
        bind_render_targets_desc.mDepthStencil.mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;

        graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

        graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.renderer.window.frame_buffer_size[0]), @floatFromInt(self.renderer.window.frame_buffer_size[1]), 0.0, 1.0);
        graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]));

        const vertex_layout = self.renderer.getVertexLayout(mesh.vertex_layout_id).?;
        const vertex_buffer_count_max = 12; // TODO(gmodarelli): Use MAX_SEMANTICS
        var vertex_buffers: [vertex_buffer_count_max][*c]graphics.Buffer = undefined;

        for (0..vertex_layout.mAttribCount) |attribute_index| {
            const buffer = mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(vertex_layout.mAttribs[attribute_index].mSemantic.bits)]].pBuffer;
            vertex_buffers[attribute_index] = buffer;
        }

        graphics.cmdBindVertexBuffer(cmd_list, vertex_layout.mAttribCount, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
        graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);

        const push_constants = DrawCallPushConstants{
            .start_instance_location = 0,
            .instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[frame_index]),
        };

        graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
        graphics.cmdDrawIndexedInstanced(
            cmd_list,
            mesh.geometry.*.pDrawArgs[0].mIndexCount,
            mesh.geometry.*.pDrawArgs[0].mStartIndex,
            mesh.geometry.*.pDrawArgs[0].mInstanceCount * @as(u32, @intCast(self.instance_data.items.len)),
            mesh.geometry.*.pDrawArgs[0].mVertexOffset,
            mesh.geometry.*.pDrawArgs[0].mStartInstance + 0,
        );

        var output_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_DEPTH_READ, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));
    const root_signature = self.renderer.getRootSignature(IdLocal.init("water"));

    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.descriptor_sets));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));

    var params: [1]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets, params.len, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets);
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
