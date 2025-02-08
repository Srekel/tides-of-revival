const std = @import("std");

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
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

// Bloom Settings
// ==============
const BloomSettings = struct {
    enabled: bool = false,
    bloom_threshold: f32 = 0.15,
    bloom_strength: f32 = 1.0,
};

// Bloom Constant Buffers
// ======================
const BloomExtractConstantBuffer = struct {
    inverse_output_size: [2]f32,
    bloom_threshold: f32,
};

const DownsampleBloomConstantBuffer = struct {
    inverse_dimensions: [2]f32,
};

const UpsampleAndBlurConstantBuffer = struct {
    inverse_dimensions: [2]f32,
    upsample_blend_factor: f32,
};

const ApplyBloomConstantBuffer = struct {
    rpc_buffer_dimensions: [2]f32,
    bloom_strength: f32,
};

const ColorGradingSettings = struct {
    enabled: bool = false,
    post_exposure: f32 = 0.5,
    contrast: f32 = 2.0,
    color_filter: [3]f32 = .{ 1.0, 1.0, 1.0 },
    hue_shift: f32 = 0.0,
    saturation: f32 = 45.0,
};

const TonemapSettings = struct {
    gamma_correction: bool = false,
    enabled: bool = true,
};

// Tonemap Constant Buffer
// =======================
const TonemapConstantBuffer = struct {
    gamma_correction: f32 = 0,
    tonemapping: f32 = 0,
    tony_mc_mapface_lut_texture_index: u32 = renderer_types.InvalidResourceIndex,
    color_grading: f32 = 0,
    color_filter: [3]f32,
    post_exposure: f32,
    contrast: f32,
    hue_shift: f32,
    saturation: f32,
};

pub const PostProcessingRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,

    // Bloom
    // =====
    bloom_settings: BloomSettings,
    bloom_extract_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    downsample_bloom_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Find a way to use a single buffer (with offsets?)
    upsample_and_blur_constant_buffers: [4][renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    apply_bloom_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    bloom_extract_descriptor_set: [*c]graphics.DescriptorSet,
    downsample_bloom_descriptor_set: [*c]graphics.DescriptorSet,
    bloom_blur_descriptor_set: [*c]graphics.DescriptorSet,
    // TODO(gmodarelli): Find a way to use a single descriptor set (with offsets or more sets?)
    upsample_and_blur_1_descriptor_set: [*c]graphics.DescriptorSet,
    upsample_and_blur_2_descriptor_set: [*c]graphics.DescriptorSet,
    upsample_and_blur_3_descriptor_set: [*c]graphics.DescriptorSet,
    upsample_and_blur_4_descriptor_set: [*c]graphics.DescriptorSet,
    apply_bloom_descriptor_set: [*c]graphics.DescriptorSet,

    // Tonemap
    // =======
    tonemap_settings: TonemapSettings,
    color_grading_settings: ColorGradingSettings,
    tonemap_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    tonemap_descriptor_set: [*c]graphics.DescriptorSet,
    tony_mc_mapface_lut: renderer.TextureHandle,

    pub fn init(self: *PostProcessingRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
        const bloom_extract_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(BloomExtractConstantBuffer);
            }

            break :blk buffers;
        };

        const downsample_bloom_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(DownsampleBloomConstantBuffer);
            }

            break :blk buffers;
        };

        const upsample_and_blur_constant_buffers = blk: {
            var buffers: [4][renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                for (buffers[buffer_index], 0..) |_, frame_index| {
                    buffers[buffer_index][frame_index] = rctx.createUniformBuffer(UpsampleAndBlurConstantBuffer);
                }
            }

            break :blk buffers;
        };

        const apply_bloom_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ApplyBloomConstantBuffer);
            }

            break :blk buffers;
        };

        const tonemap_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(TonemapConstantBuffer);
            }

            break :blk buffers;
        };

        const tony_mc_mapface_lut = rctx.loadTexture("textures/lut/tony_mc_mapface.dds");

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .bloom_settings = .{},
            .bloom_extract_constant_buffers = bloom_extract_constant_buffers,
            .downsample_bloom_constant_buffers = downsample_bloom_constant_buffers,
            .upsample_and_blur_constant_buffers = upsample_and_blur_constant_buffers,
            .apply_bloom_constant_buffers = apply_bloom_constant_buffers,
            .bloom_extract_descriptor_set = undefined,
            .downsample_bloom_descriptor_set = undefined,
            .bloom_blur_descriptor_set = undefined,
            .upsample_and_blur_1_descriptor_set = undefined,
            .upsample_and_blur_2_descriptor_set = undefined,
            .upsample_and_blur_3_descriptor_set = undefined,
            .upsample_and_blur_4_descriptor_set = undefined,
            .apply_bloom_descriptor_set = undefined,
            .color_grading_settings = .{},
            .tonemap_settings = .{},
            .tonemap_constant_buffers = tonemap_constant_buffers,
            .tonemap_descriptor_set = undefined,
            .tony_mc_mapface_lut = tony_mc_mapface_lut,
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_imgui_fn = renderImGui,
            .render_post_processing_pass_fn = render,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *PostProcessingRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);

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
    const trazy_zone = ztracy.ZoneNC(@src(), "Bloom", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    // Bloom
    if (self.bloom_settings.enabled) {
        var rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

        // Bloom Extract
        {
            const bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
            var t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav1a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);

            // Update constant buffer
            {
                var constant_buffer_data = std.mem.zeroes(BloomExtractConstantBuffer);
                constant_buffer_data.bloom_threshold = self.bloom_settings.bloom_threshold;
                constant_buffer_data.inverse_output_size[0] = 1.0 / @as(f32, @floatFromInt(self.renderer.bloom_width));
                constant_buffer_data.inverse_output_size[1] = 1.0 / @as(f32, @floatFromInt(self.renderer.bloom_height));

                const data = renderer.Slice{
                    .data = @ptrCast(&constant_buffer_data),
                    .size = @sizeOf(BloomExtractConstantBuffer),
                };
                self.renderer.updateBuffer(data, BloomExtractConstantBuffer, self.bloom_extract_constant_buffers[frame_index]);
            }

            const pipeline_id = IdLocal.init("bloom_extract");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.bloom_extract_descriptor_set);
            graphics.cmdDispatch(cmd_list, (self.renderer.bloom_width + 8 - 1) / 8, (self.renderer.bloom_height + 8 - 1) / 8, 1);

            var output_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav1a, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, output_barriers.len, @constCast(&output_barriers), 0, null);
        }

        // Downsample Bloom
        {
            // var bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
            const bloom_uav2a = self.renderer.getTexture(self.renderer.bloom_uav2[0]);
            const bloom_uav3a = self.renderer.getTexture(self.renderer.bloom_uav3[0]);
            const bloom_uav4a = self.renderer.getTexture(self.renderer.bloom_uav4[0]);
            const bloom_uav5a = self.renderer.getTexture(self.renderer.bloom_uav5[0]);

            var t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav2a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                graphics.TextureBarrier.init(bloom_uav3a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                graphics.TextureBarrier.init(bloom_uav4a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                graphics.TextureBarrier.init(bloom_uav5a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);

            // Update constant buffer
            {
                var constant_buffer_data = std.mem.zeroes(DownsampleBloomConstantBuffer);
                constant_buffer_data.inverse_dimensions[0] = 1.0 / @as(f32, @floatFromInt(self.renderer.bloom_width));
                constant_buffer_data.inverse_dimensions[1] = 1.0 / @as(f32, @floatFromInt(self.renderer.bloom_height));

                const data = renderer.Slice{
                    .data = @ptrCast(&constant_buffer_data),
                    .size = @sizeOf(DownsampleBloomConstantBuffer),
                };
                self.renderer.updateBuffer(data, DownsampleBloomConstantBuffer, self.downsample_bloom_constant_buffers[frame_index]);
            }

            const pipeline_id = IdLocal.init("downsample_bloom_all");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.downsample_bloom_descriptor_set);
            graphics.cmdDispatch(cmd_list, ((self.renderer.bloom_width / 2) + 8 - 1) / 8, ((self.renderer.bloom_height / 2) + 8 - 1) / 8, 1);

            t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav2a, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.TextureBarrier.init(bloom_uav3a, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.TextureBarrier.init(bloom_uav4a, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.TextureBarrier.init(bloom_uav5a, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);
        }

        // Blur
        {
            const bloom_uav5a = self.renderer.getTexture(self.renderer.bloom_uav5[0]);
            const bloom_uav5b = self.renderer.getTexture(self.renderer.bloom_uav5[1]);

            var t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav5b, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);

            const pipeline_id = IdLocal.init("blur");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.bloom_blur_descriptor_set);
            const width = @as(u32, bloom_uav5a[0].bitfield_1.mWidth);
            const height = @as(u32, bloom_uav5a[0].bitfield_1.mHeight);
            graphics.cmdDispatch(cmd_list, (width + 8 - 1) / 8, (height + 8 - 1) / 8, 1);

            t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav5b, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);
        }

        // Upsample and Blur
        {
            upsampleAndBlur(self, cmd_list, self.renderer.bloom_uav4[0], self.renderer.bloom_uav4[1], 0, self.upsample_and_blur_1_descriptor_set);
            upsampleAndBlur(self, cmd_list, self.renderer.bloom_uav3[0], self.renderer.bloom_uav3[1], 1, self.upsample_and_blur_2_descriptor_set);
            upsampleAndBlur(self, cmd_list, self.renderer.bloom_uav2[0], self.renderer.bloom_uav2[1], 2, self.upsample_and_blur_3_descriptor_set);
            upsampleAndBlur(self, cmd_list, self.renderer.bloom_uav1[0], self.renderer.bloom_uav1[1], 3, self.upsample_and_blur_4_descriptor_set);
        }

        // Apply Bloom
        {
            rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

            // Update constant buffer
            {
                var constant_buffer_data = std.mem.zeroes(ApplyBloomConstantBuffer);
                constant_buffer_data.bloom_strength = self.bloom_settings.bloom_strength;
                constant_buffer_data.rpc_buffer_dimensions[0] = 1.0 / @as(f32, @floatFromInt(self.renderer.window_width));
                constant_buffer_data.rpc_buffer_dimensions[1] = 1.0 / @as(f32, @floatFromInt(self.renderer.window_height));

                const data = renderer.Slice{
                    .data = @ptrCast(&constant_buffer_data),
                    .size = @sizeOf(ApplyBloomConstantBuffer),
                };
                self.renderer.updateBuffer(data, ApplyBloomConstantBuffer, self.apply_bloom_constant_buffers[frame_index]);
            }

            const pipeline_id = IdLocal.init("apply_bloom");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.apply_bloom_descriptor_set);
            graphics.cmdDispatch(cmd_list, (@as(u32, @intCast(self.renderer.window_width)) + 8 - 1) / 8, (@as(u32, @intCast(self.renderer.window_height)) + 8 - 1) / 8, 1);

            rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));
        }
    }

    // Tonemap
    {
        var num_input_barriers: u32 = 1;
        var input_barriers: [2]graphics.RenderTargetBarrier = undefined;
        input_barriers[0] = graphics.RenderTargetBarrier.init(self.renderer.swap_chain.*.ppRenderTargets[self.renderer.swap_chain_image_index], graphics.ResourceState.RESOURCE_STATE_PRESENT, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET);
        if (!self.bloom_settings.enabled) {
            num_input_barriers = 2;
            input_barriers[1] = graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE);
        }

        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, num_input_barriers, @ptrCast(&input_barriers));

        var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
        bind_render_targets_desc.mRenderTargetCount = 1;
        bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.renderer.swap_chain.*.ppRenderTargets[self.renderer.swap_chain_image_index];
        bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

        graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

        graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.renderer.window.frame_buffer_size[0]), @floatFromInt(self.renderer.window.frame_buffer_size[1]), 0.0, 1.0);
        graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]));

        // Update constant buffer
        {
            var constant_buffer_data = std.mem.zeroes(TonemapConstantBuffer);
            constant_buffer_data.gamma_correction = if (self.tonemap_settings.gamma_correction) 1 else 0;
            constant_buffer_data.tonemapping = if (self.tonemap_settings.enabled) 1 else 0;
            constant_buffer_data.color_grading = if (self.color_grading_settings.enabled) 1 else 0;
            constant_buffer_data.tony_mc_mapface_lut_texture_index = self.renderer.getTextureBindlessIndex(self.tony_mc_mapface_lut);
            // Exposure is measured in stops, so we need raise 2 to the power of the configured value
            constant_buffer_data.post_exposure = std.math.pow(f32, 2.0, self.color_grading_settings.post_exposure);
            // Contrast and saturation need to be remaped from [-100, 100] to [0, 2]
            constant_buffer_data.contrast = self.color_grading_settings.contrast * 0.01 + 1.0;
            constant_buffer_data.saturation = self.color_grading_settings.saturation * 0.01 + 1.0;
            // HueShift needs to be remapped from [-180, 180] to [-1, 1]
            constant_buffer_data.hue_shift = self.color_grading_settings.hue_shift / 360.0;
            @memcpy(&constant_buffer_data.color_filter, &self.color_grading_settings.color_filter);

            const data = renderer.Slice{
                .data = @ptrCast(&constant_buffer_data),
                .size = @sizeOf(TonemapConstantBuffer),
            };
            self.renderer.updateBuffer(data, TonemapConstantBuffer, self.tonemap_constant_buffers[frame_index]);
        }

        const pipeline_id = IdLocal.init("tonemap");
        const pipeline = self.renderer.getPSO(pipeline_id);

        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, 0, self.tonemap_descriptor_set);
        graphics.cmdDraw(cmd_list, 3, 0);
    }
}

fn upsampleAndBlur(
    self: *PostProcessingRenderPass,
    cmd_list: [*c]graphics.Cmd,
    higher_res_handle: renderer.TextureHandle,
    result_handle: renderer.TextureHandle,
    buffer_index: u32,
    descriptor_set: [*c]graphics.DescriptorSet,
) void {
    const frame_index = self.renderer.frame_index;

    const higher_res_buffer = self.renderer.getTexture(higher_res_handle);
    const result = self.renderer.getTexture(result_handle);

    var t_barriers = [_]graphics.TextureBarrier{
        graphics.TextureBarrier.init(result, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
    };
    graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);

    const higher_res_width = @as(u32, higher_res_buffer[0].bitfield_1.mWidth);
    const higher_res_height = @as(u32, higher_res_buffer[0].bitfield_1.mHeight);

    // Update constant buffer
    {
        var constant_buffer_data = std.mem.zeroes(UpsampleAndBlurConstantBuffer);
        constant_buffer_data.inverse_dimensions[0] = 1.0 / @as(f32, @floatFromInt(higher_res_width));
        constant_buffer_data.inverse_dimensions[1] = 1.0 / @as(f32, @floatFromInt(higher_res_height));
        constant_buffer_data.upsample_blend_factor = 0.65;

        const data = renderer.Slice{
            .data = @ptrCast(&constant_buffer_data),
            .size = @sizeOf(UpsampleAndBlurConstantBuffer),
        };
        self.renderer.updateBuffer(data, UpsampleAndBlurConstantBuffer, self.upsample_and_blur_constant_buffers[buffer_index][frame_index]);
    }

    const pipeline_id = IdLocal.init("upsample_and_blur");
    const pipeline = self.renderer.getPSO(pipeline_id);
    graphics.cmdBindPipeline(cmd_list, pipeline);
    graphics.cmdBindDescriptorSet(cmd_list, 0, descriptor_set);
    graphics.cmdDispatch(cmd_list, (higher_res_width + 8 - 1) / 8, (higher_res_height + 8 - 1) / 8, 1);

    t_barriers = [_]graphics.TextureBarrier{
        graphics.TextureBarrier.init(result, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
    };
    graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);
}

fn renderImGui(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));
    if (zgui.collapsingHeader("Bloom", .{})) {
        _ = zgui.checkbox("Bloom Enabled", .{ .v = &self.bloom_settings.enabled });
        _ = zgui.dragFloat("Threshold", .{ .v = &self.bloom_settings.bloom_threshold, .cfmt = "%.2f", .min = 0.05, .max = 1.0, .speed = 0.01 });
        _ = zgui.dragFloat("Strength", .{ .v = &self.bloom_settings.bloom_strength, .cfmt = "%.2f", .min = 0.0, .max = 10.0, .speed = 0.01 });
    }

    if (zgui.collapsingHeader("Tone Mapping", .{})) {
        _ = zgui.checkbox("Gamma Correction", .{ .v = &self.tonemap_settings.gamma_correction });
        _ = zgui.checkbox("Tone Mapping Enabled", .{ .v = &self.tonemap_settings.enabled });
    }

    if (zgui.collapsingHeader("Color Grading", .{})) {
        _ = zgui.checkbox("Color Grading Enabled", .{ .v = &self.color_grading_settings.enabled });
        _ = zgui.inputFloat("Post Exposure", .{ .v = &self.color_grading_settings.post_exposure });
        _ = zgui.dragFloat("Contrast", .{ .v = &self.color_grading_settings.contrast, .cfmt = "%.2f", .min = -100.0, .max = 100.0, .speed = 0.1 });
        _ = zgui.colorEdit3("Color Filter", .{ .col = &self.color_grading_settings.color_filter });
        _ = zgui.dragFloat("Hue Shift", .{ .v = &self.color_grading_settings.hue_shift, .cfmt = "%.2f", .min = -180.0, .max = 180.0, .speed = 0.1 });
        _ = zgui.dragFloat("Saturation", .{ .v = &self.color_grading_settings.saturation, .cfmt = "%.2f", .min = -100.0, .max = 100.0, .speed = 0.1 });
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;

    var root_signature = self.renderer.getRootSignature(IdLocal.init("bloom_extract"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.bloom_extract_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("downsample_bloom_all"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.downsample_bloom_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("blur"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.bloom_blur_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("apply_bloom"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.apply_bloom_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("upsample_and_blur"));
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_DRAW;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_1_descriptor_set));
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_2_descriptor_set));
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_3_descriptor_set));
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_4_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("tonemap"));
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.tonemap_descriptor_set));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

    // Bloom Extract
    for (0..renderer.Renderer.data_buffer_count) |i| {
        var bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
        var params: [3]graphics.DescriptorData = undefined;
        var bloom_extract_constant_buffer = self.renderer.getBuffer(self.bloom_extract_constant_buffers[i]);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cb0";
        params[0].__union_field3.ppBuffers = @ptrCast(&bloom_extract_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "source_tex";
        params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "bloom_result";
        params[2].__union_field3.ppTextures = @ptrCast(&bloom_uav1a);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.bloom_extract_descriptor_set, params.len, @ptrCast(&params));
    }

    // Downsample Bloom
    for (0..renderer.Renderer.data_buffer_count) |i| {
        var params: [6]graphics.DescriptorData = undefined;
        var downsample_bloom_constant_buffer = self.renderer.getBuffer(self.downsample_bloom_constant_buffers[i]);
        var bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
        var bloom_uav2a = self.renderer.getTexture(self.renderer.bloom_uav2[0]);
        var bloom_uav3a = self.renderer.getTexture(self.renderer.bloom_uav3[0]);
        var bloom_uav4a = self.renderer.getTexture(self.renderer.bloom_uav4[0]);
        var bloom_uav5a = self.renderer.getTexture(self.renderer.bloom_uav5[0]);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cb0";
        params[0].__union_field3.ppBuffers = @ptrCast(&downsample_bloom_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "bloom_buffer";
        params[1].__union_field3.ppTextures = @ptrCast(&bloom_uav1a);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "result_1";
        params[2].__union_field3.ppTextures = @ptrCast(&bloom_uav2a);
        params[3] = std.mem.zeroes(graphics.DescriptorData);
        params[3].pName = "result_2";
        params[3].__union_field3.ppTextures = @ptrCast(&bloom_uav3a);
        params[4] = std.mem.zeroes(graphics.DescriptorData);
        params[4].pName = "result_3";
        params[4].__union_field3.ppTextures = @ptrCast(&bloom_uav4a);
        params[5] = std.mem.zeroes(graphics.DescriptorData);
        params[5].pName = "result_4";
        params[5].__union_field3.ppTextures = @ptrCast(&bloom_uav5a);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.downsample_bloom_descriptor_set, params.len, @ptrCast(&params));
    }

    // Bloom Blur
    for (0..renderer.Renderer.data_buffer_count) |i| {
        var params: [2]graphics.DescriptorData = undefined;
        var bloom_uav5a = self.renderer.getTexture(self.renderer.bloom_uav5[0]);
        var bloom_uav5b = self.renderer.getTexture(self.renderer.bloom_uav5[1]);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "input_buffer";
        params[0].__union_field3.ppTextures = @ptrCast(&bloom_uav5a);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "result";
        params[1].__union_field3.ppTextures = @ptrCast(&bloom_uav5b);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.bloom_blur_descriptor_set, params.len, @ptrCast(&params));
    }

    // Upsample and Blur
    for (0..4) |buffer_index| {
        for (0..renderer.Renderer.data_buffer_count) |frame_index| {
            var params: [4]graphics.DescriptorData = undefined;
            var upsample_and_blur_constant_buffer = self.renderer.getBuffer(self.upsample_and_blur_constant_buffers[buffer_index][frame_index]);
            var higher_res_buffer: [*]graphics.Texture = undefined;
            var lower_res_buffer: [*]graphics.Texture = undefined;
            var result_buffer: [*]graphics.Texture = undefined;
            var descriptor_set: [*c]graphics.DescriptorSet = null;

            if (buffer_index == 0) {
                descriptor_set = self.upsample_and_blur_1_descriptor_set;
                higher_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav4[0]);
                lower_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav5[1]);
                result_buffer = self.renderer.getTexture(self.renderer.bloom_uav4[1]);
            } else if (buffer_index == 1) {
                descriptor_set = self.upsample_and_blur_2_descriptor_set;
                higher_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav3[0]);
                lower_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav4[1]);
                result_buffer = self.renderer.getTexture(self.renderer.bloom_uav3[1]);
            } else if (buffer_index == 2) {
                descriptor_set = self.upsample_and_blur_3_descriptor_set;
                higher_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav2[0]);
                lower_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav3[1]);
                result_buffer = self.renderer.getTexture(self.renderer.bloom_uav2[1]);
            } else {
                descriptor_set = self.upsample_and_blur_4_descriptor_set;
                higher_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
                lower_res_buffer = self.renderer.getTexture(self.renderer.bloom_uav2[1]);
                result_buffer = self.renderer.getTexture(self.renderer.bloom_uav1[1]);
            }

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cb0";
            params[0].__union_field3.ppBuffers = @ptrCast(&upsample_and_blur_constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "higher_res_buffer";
            params[1].__union_field3.ppTextures = @ptrCast(&higher_res_buffer);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "lower_res_buffer";
            params[2].__union_field3.ppTextures = @ptrCast(&lower_res_buffer);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "result";
            params[3].__union_field3.ppTextures = @ptrCast(&result_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), descriptor_set, params.len, @ptrCast(&params));
        }
    }

    // Apply Bloom
    for (0..renderer.Renderer.data_buffer_count) |frame_index| {
        var params: [3]graphics.DescriptorData = undefined;
        var bloom_extract_constant_buffer = self.renderer.getBuffer(self.apply_bloom_constant_buffers[frame_index]);
        var bloom_uav1b = self.renderer.getTexture(self.renderer.bloom_uav1[1]);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cb0";
        params[0].__union_field3.ppBuffers = @ptrCast(&bloom_extract_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "bloom_buffer";
        params[1].__union_field3.ppTextures = @ptrCast(&bloom_uav1b);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "scene_color";
        params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.apply_bloom_descriptor_set, params.len, @ptrCast(&params));
    }

    // Tonemapper
    for (0..renderer.Renderer.data_buffer_count) |frame_index| {
        var tonemap_constant_buffer = self.renderer.getBuffer(self.tonemap_constant_buffers[frame_index]);
        var params: [2]graphics.DescriptorData = undefined;

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "g_scene_color";
        params[0].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "ConstantBuffer";
        params[1].__union_field3.ppBuffers = @ptrCast(&tonemap_constant_buffer);
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.tonemap_descriptor_set, params.len, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.bloom_extract_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.downsample_bloom_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.bloom_blur_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_1_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_2_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_3_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_4_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.apply_bloom_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.tonemap_descriptor_set);
}
