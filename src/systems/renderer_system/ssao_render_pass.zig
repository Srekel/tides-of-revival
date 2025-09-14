const std = @import("std");

const config = @import("../../config/config.zig");
const context = @import("../../core/context.zig");
const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const renderer_types = @import("../../renderer/types.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");

const graphics = zforge.graphics;

pub const ConstantBufferData = struct {
    zmagic: f32,
};

pub const SSAORenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_set: [*c]graphics.DescriptorSet,

    pub fn init(self: *SSAORenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.ecsu_world = ecsu_world;
        self.renderer = rctx;

        const constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ConstantBufferData);
            }

            break :blk buffers;
        };

        self.constant_buffers = constant_buffers;

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_ssao_pass_fn = renderSSAO,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *SSAORenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);

        unloadDescriptorSets(@ptrCast(self));
    }
};

fn renderSSAO(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const self: *SSAORenderPass = @ptrCast(@alignCast(user_data));

    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
    });

    const constant_buffer_data = ConstantBufferData{
        .zmagic = (camera_comps.camera.far - camera_comps.camera.near) / camera_comps.camera.near,
    };
    const data = renderer.Slice{
        .data = @ptrCast(&constant_buffer_data),
        .size = @sizeOf(ConstantBufferData),
    };
    self.renderer.updateBuffer(data, 0, ConstantBufferData, self.constant_buffers[frame_index]);

    const linear_depth = self.renderer.getTexture(self.renderer.linear_depth_buffers[frame_index]);
    const linear_depth_width: u32 = @intCast(self.renderer.window_width);
    const linear_depth_height: u32 = @intCast(self.renderer.window_height);
    const thread_group_count: u32 = 16;
    const dispatch_group_count_x: u32 = (linear_depth_width + thread_group_count - 1) / thread_group_count;
    const dispatch_group_count_y: u32 = (linear_depth_height + thread_group_count - 1) / thread_group_count;

    var input_rt_barriers = [_]graphics.RenderTargetBarrier{
        graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_DEPTH_WRITE, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
    };
    graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_rt_barriers.len, @ptrCast(&input_rt_barriers));

    var input_textures_barriers = [_]graphics.TextureBarrier{
        graphics.TextureBarrier.init(linear_depth, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
    };
    graphics.cmdResourceBarrier(cmd_list, 0, null, input_textures_barriers.len, @constCast(&input_textures_barriers), 0, null);

    const pipeline_id = IdLocal.init("linearize_depth");
    const pipeline = self.renderer.getPSO(pipeline_id);
    graphics.cmdBindPipeline(cmd_list, pipeline);
    graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_set);
    graphics.cmdDispatch(cmd_list, dispatch_group_count_x, dispatch_group_count_y, 1);

    var output_textures_barriers = [_]graphics.TextureBarrier{
        graphics.TextureBarrier.init(linear_depth, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE,),
    };
    graphics.cmdResourceBarrier(cmd_list, 0, null, output_textures_barriers.len, @constCast(&output_textures_barriers), 0, null);

}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *SSAORenderPass = @ptrCast(@alignCast(user_data));

    const root_signature = self.renderer.getRootSignature(IdLocal.init("linearize_depth"));
    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.descriptor_set));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *SSAORenderPass = @ptrCast(@alignCast(user_data));

    var params: [3]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var constant_buffer = self.renderer.getBuffer(self.constant_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "CB0";
        params[0].__union_field3.ppBuffers = @ptrCast(&constant_buffer);

        var linear_depth = self.renderer.getTexture(self.renderer.linear_depth_buffers[i]);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "LinearZ";
        params[1].__union_field3.ppTextures = @ptrCast(&linear_depth);

        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "Depth";
        params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer.*.pTexture);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_set, @intCast(params.len), @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *SSAORenderPass = @ptrCast(@alignCast(user_data));
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
}