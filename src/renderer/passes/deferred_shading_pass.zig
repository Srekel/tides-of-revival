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
    projection_inverted: [16]f32,
    projection_view_inverted: [16]f32,
    screen_params: [4]f32,
    camera_position: [4]f32,
    near_plane: f32,
    far_plane: f32,
    shadow_resolution_inverse: [2]f32,
    cascade_splits: [renderer.Renderer.cascades_max_count]f32,
    visible_lights_buffer_index: u32,
    visible_lights_count_buffer_index: u32,
    light_matrix_buffer_index: u32,
    sh9_buffer_index: u32,
    fog_color: [3]f32,
    fog_density: f32,
    lights_buffer_index: u32,
    _padding: [3]u32,
};

pub const LightCullingParams = struct {
    view_projection: [16]f32,
    lights_count: u32,
    lights_buffer_index: u32,
    visible_lights_count_buffer_index: u32,
    visible_lights_buffer_index: u32,
    camera_position: [3]f32,
    max_distance: f32,
};

pub const DeferredShadingPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,

    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    deferred_descriptor_sets: [2][*c]graphics.DescriptorSet,

    light_culling_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    light_culling_descriptor_sets: [*c]graphics.DescriptorSet,
    visible_lights_count_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    visible_lights_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    pub fn init(self: *@This(), rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;

        self.uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        self.light_culling_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(LightCullingParams);
            }

            break :blk buffers;
        };

        for (0..renderer.Renderer.data_buffer_count) |frame_index| {
            const buffer_creation_desc = renderer.BufferCreationDesc{
                .bindless = true,
                .descriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits },
                .start_state = .RESOURCE_STATE_COMMON,
                .size = @sizeOf(u32) * 16,
                .debug_name = "Visible Lights Counts",
            };

            self.visible_lights_count_buffers[frame_index] = rctx.createBuffer(buffer_creation_desc);
        }

        for (0..renderer.Renderer.data_buffer_count) |frame_index| {
            const buffer_creation_desc = renderer.BufferCreationDesc{
                .bindless = true,
                .descriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits },
                .start_state = .RESOURCE_STATE_COMMON,
                .size = @sizeOf(renderer_types.GpuLight) * 10 * 1024,
                .debug_name = "Visible Lights",
            };

            self.visible_lights_buffers[frame_index] = rctx.createBuffer(buffer_creation_desc);
        }
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

        // Light culling
        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Light Culling", 0x00_ff_ff_00);
            defer trazy_zone2.End();

            var params = std.mem.zeroes(LightCullingParams);
            zm.storeMat(&params.view_projection, zm.transpose(render_view.view_projection));
            params.lights_count = self.renderer.light_buffer.element_count;
            params.lights_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.light_buffer.buffer);
            params.visible_lights_count_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_lights_count_buffers[frame_index]);
            params.visible_lights_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_lights_buffers[frame_index]);
            params.camera_position = [3]f32{ camera_position[0], camera_position[1], camera_position[2] };
            params.max_distance = 1000.0;

            const data = OpaqueSlice{
                .data = @ptrCast(&params),
                .size = @sizeOf(LightCullingParams),
            };
            self.renderer.updateBuffer(data, 0, LightCullingParams, self.light_culling_frame_buffers[frame_index]);

            const visible_lights_count_buffer = self.renderer.getBuffer(self.visible_lights_count_buffers[frame_index]);
            const visible_lights_buffer = self.renderer.getBuffer(self.visible_lights_buffers[frame_index]);
            {
                const buffer_barriers = [_]graphics.BufferBarrier{
                    graphics.BufferBarrier.init(visible_lights_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    graphics.BufferBarrier.init(visible_lights_count_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                };
                graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
            }

            // Clear
            {
                const pipeline_id = IdLocal.init("light_cull_clear");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.light_culling_descriptor_sets);
                graphics.cmdDispatch(cmd_list, 1, 1, 1);
            }

            // Cull
            {
                const pipeline_id = IdLocal.init("light_cull");
                const pipeline = self.renderer.getPSO(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.light_culling_descriptor_sets);
                graphics.cmdDispatch(cmd_list, (self.renderer.light_buffer.element_count / 32) + 1, 1, 1);
            }

            {
                const buffer_barriers = [_]graphics.BufferBarrier{
                    graphics.BufferBarrier.init(visible_lights_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                    graphics.BufferBarrier.init(visible_lights_count_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_COMMON),
                };
                graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
            }
        }

        // Shading
        {
            const trazy_zone2 = ztracy.ZoneNC(@src(), "Shading", 0x00_ff_ff_00);
            defer trazy_zone2.End();

            var frame_data = std.mem.zeroes(UniformFrameData);
            zm.storeMat(&frame_data.projection_inverted, zm.transpose(render_view.projection_inverse));
            zm.storeMat(&frame_data.projection_view_inverted, zm.transpose(render_view.view_projection_inverse));
            frame_data.screen_params = [4]f32{ render_view.viewport[0], render_view.viewport[1], 1.0 / render_view.viewport[0], 1.0 / render_view.viewport[1] };
            frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
            frame_data.cascade_splits = self.renderer.shadow_cascade_depths;
            frame_data.lights_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.light_buffer.buffer);
            frame_data.visible_lights_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_lights_buffers[frame_index]);
            frame_data.visible_lights_count_buffer_index = self.renderer.getBufferBindlessIndex(self.visible_lights_count_buffers[frame_index]);
            frame_data.light_matrix_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.light_matrix_buffer.buffer);
            frame_data.sh9_buffer_index = self.renderer.getSH9BufferIndex();
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
    }

    pub fn createDescriptorSets(self: *@This()) void {
        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("deferred"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.deferred_descriptor_sets[0]));

            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.deferred_descriptor_sets[1]));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("light_cull"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.light_culling_descriptor_sets));
        }
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        {
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

        {
            var params: [2]graphics.DescriptorData = undefined;

            for (0..renderer.Renderer.data_buffer_count) |i| {
                var uniform_buffer = self.renderer.getBuffer(self.light_culling_frame_buffers[i]);
                var debug_uniform_buffer = self.renderer.getBuffer(self.renderer.debug_frame_uniform_buffers[i]);
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "g_Params";
                params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);
                params[1] = std.mem.zeroes(graphics.DescriptorData);
                params[1].pName = "g_DebugFrame";
                params[1].__union_field3.ppBuffers = @ptrCast(&debug_uniform_buffer);

                graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.light_culling_descriptor_sets, params.len, @ptrCast(&params));
            }
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.deferred_descriptor_sets[0]);
        graphics.removeDescriptorSet(self.renderer.renderer, self.deferred_descriptor_sets[1]);
        graphics.removeDescriptorSet(self.renderer.renderer, self.light_culling_descriptor_sets);
    }
};
