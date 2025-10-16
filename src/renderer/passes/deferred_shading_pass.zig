const std = @import("std");

const fd = @import("../../config/flecs_data.zig");
const graphics = zforge.graphics;
const IdLocal = @import("../../core/core.zig").IdLocal;
const OpaqueSlice = util.OpaqueSlice;
const renderer = @import("../../renderer/renderer.zig");
const renderer_types = @import("../../renderer/types.zig");
const util = @import("../../util.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const zm = @import("zmath");
const ztracy = @import("ztracy");

const UniformFrameData = struct {
    projection: [16]f32,
    projection_inverted: [16]f32,
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
    near_plane: f32,
    far_plane: f32,
    shadow_resolution_inverse: [2]f32,
    cascade_splits: [renderer.Renderer.cascades_max_count]f32,
    lights_buffer_index: u32,
    lights_count: u32,
    light_matrix_buffer_index: u32,
    _padding1: u32,
    fog_color: [3]f32,
    fog_density: f32,
};

pub const DeferredShadingPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,

    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    deferred_descriptor_sets: [2][*c]graphics.DescriptorSet,

    pub fn init(self: *@This(), rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        self.allocator = allocator;
        self.renderer = rctx;
    }

    pub fn destroy(self: *@This()) void {
        _ = self;
    }

    pub fn renderImGui(self: *@This()) void {
        _ = self;
        if (zgui.collapsingHeader("Deferred Shading", .{})) {}
    }

    pub fn render(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Deferred Shading Render Pass", 0x00_ff_ff_00);
        defer trazy_zone.End();

        const frame_index = self.renderer.frame_index;
        const camera_position = render_view.position;

        var frame_data = std.mem.zeroes(UniformFrameData);
        zm.storeMat(&frame_data.projection, zm.transpose(render_view.projection));
        zm.storeMat(&frame_data.projection_inverted, zm.transpose(render_view.projection_inverse));
        zm.storeMat(&frame_data.projection_view, zm.transpose(render_view.view_projection));
        zm.storeMat(&frame_data.projection_view_inverted, zm.transpose(render_view.view_projection_inverse));
        frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
        frame_data.cascade_splits = self.renderer.shadow_cascade_depths;
        frame_data.lights_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.light_buffer.buffer);
        frame_data.light_matrix_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.light_matrix_buffer.buffer);
        frame_data.lights_count = self.renderer.light_buffer.element_count;
        frame_data.fog_color = self.renderer.height_fog_settings.color;
        frame_data.fog_density = self.renderer.height_fog_settings.density;
        frame_data.near_plane = render_view.far_plane;
        frame_data.far_plane = render_view.near_plane;
        frame_data.shadow_resolution_inverse = [2]f32{ 1.0 / 2048.0, 1.0 / 2048.0 };

        const data = OpaqueSlice{
            .data = @ptrCast(&frame_data),
            .size = @sizeOf(UniformFrameData),
        };
        self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers[frame_index]);

        // Deferred Shading commands
        {
            const pipeline_id = IdLocal.init("deferred");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.deferred_descriptor_sets[0]);
            graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.deferred_descriptor_sets[1]);
            graphics.cmdDraw(cmd_list, 3, 0);
        }
    }

    pub fn createDescriptorSets(self: *@This()) void {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("deferred"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.deferred_descriptor_sets[0]));

        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.deferred_descriptor_sets[1]));
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        var params: [8]graphics.DescriptorData = undefined;

        for (0..renderer.Renderer.data_buffer_count) |i| {
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "gBuffer0";
            params[0].__union_field3.ppTextures = @ptrCast(&self.renderer.gbuffer_0.*.pTexture);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "gBuffer1";
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.gbuffer_1.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "gBuffer2";
            params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.gbuffer_2.*.pTexture);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "depthBuffer";
            params[3].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer.*.pTexture);
            params[4] = std.mem.zeroes(graphics.DescriptorData);
            params[4].pName = "shadowDepth0";
            params[4].__union_field3.ppTextures = @ptrCast(&self.renderer.shadow_depth_buffers[0].*.pTexture);
            params[5] = std.mem.zeroes(graphics.DescriptorData);
            params[5].pName = "shadowDepth1";
            params[5].__union_field3.ppTextures = @ptrCast(&self.renderer.shadow_depth_buffers[1].*.pTexture);
            params[6] = std.mem.zeroes(graphics.DescriptorData);
            params[6].pName = "shadowDepth2";
            params[6].__union_field3.ppTextures = @ptrCast(&self.renderer.shadow_depth_buffers[2].*.pTexture);
            params[7] = std.mem.zeroes(graphics.DescriptorData);
            params[7].pName = "shadowDepth3";
            params[7].__union_field3.ppTextures = @ptrCast(&self.renderer.shadow_depth_buffers[3].*.pTexture);
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.deferred_descriptor_sets[0], 8, @ptrCast(&params));

            var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbFrame";
            params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.deferred_descriptor_sets[1], 1, @ptrCast(&params));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.deferred_descriptor_sets[0]);
        graphics.removeDescriptorSet(self.renderer.renderer, self.deferred_descriptor_sets[1]);
    }
};
