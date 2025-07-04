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
const profiler = zforge.profiler;
const resource_loader = zforge.resource_loader;

const k_initial_min_log: f32 = -12.0;
const k_initial_max_log: f32 = 4.0;

// Bloom Settings
// ==============
const BloomSettings = struct {
    enabled: bool = true,
    // range[0.0, 8.0]
    bloom_threshold: f32 = 4.0,
    // range[0.0, 2.0]
    bloom_strength: f32 = 0.1,
    // range[0.0, 1.0]
    bloom_scatter: f32 = 0.65,
};

// Exposure Settings
// =================
const ExposureSettings = struct {
    enable_adaptation: bool = false,
    // range[-8.0, 0.0]
    min_exposure: f32 = 1.0 / 64.0,
    // range[-8.0, 0.0]
    max_exposure: f32 = 64.0,
    // range[0.01, 0.99]
    target_luminance: f32 = 0.08,
    // range[0.01, 1.0]
    adapation_rate: f32 = 0.05,
    // range[-8.0, 8.0]
    exposure: f32 = 2.0,
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

const TonemapSettings = struct {
    gamma_correction: bool = false,
    enabled: bool = true,
};

// Histogram
// =========
const GenerateHistogramConstantBuffer = struct {
    buffer_height: u32,
};

const AdaptExposureConstantBuffer = struct {
    target_luminance: f32,
    adaptation_rate: f32,
    min_exposure: f32,
    max_exposure: f32,
    pixel_count: u32,
};

// Tonemap Constant Buffer
// =======================
const TonemapConstantBuffer = struct {
    rpc_buffer_dimensions: [2]f32,
    bloom_strength: f32,
    paper_white_ratio: f32,
    max_brightness: f32,
};

pub const PostProcessingRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,

    hdr_tonemap_profile_token: profiler.ProfileToken = undefined,
    bloom_profile_token: profiler.ProfileToken = undefined,
    update_exposure_profile_token: profiler.ProfileToken = undefined,

    // Exposure
    // ========
    clear_uav_descriptor_set: [*c]graphics.DescriptorSet,
    exposure_settings: ExposureSettings,
    exposure_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    histogram_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    generate_histogram_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    generate_histogram_descriptor_set: [*c]graphics.DescriptorSet,
    draw_debug_histogram_descriptor_set: [*c]graphics.DescriptorSet,
    adapt_exposure_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    adapt_exposure_descriptor_set: [*c]graphics.DescriptorSet,

    // Bloom
    // =====
    bloom_settings: BloomSettings,
    bloom_extract_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    downsample_bloom_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): Find a way to use a single buffer (with offsets?)
    upsample_and_blur_constant_buffers: [4][renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    bloom_extract_descriptor_set: [*c]graphics.DescriptorSet,
    downsample_bloom_descriptor_set: [*c]graphics.DescriptorSet,
    bloom_blur_descriptor_set: [*c]graphics.DescriptorSet,
    // TODO(gmodarelli): Find a way to use a single descriptor set (with offsets or more sets?)
    upsample_and_blur_1_descriptor_set: [*c]graphics.DescriptorSet,
    upsample_and_blur_2_descriptor_set: [*c]graphics.DescriptorSet,
    upsample_and_blur_3_descriptor_set: [*c]graphics.DescriptorSet,
    upsample_and_blur_4_descriptor_set: [*c]graphics.DescriptorSet,

    // Tonemap
    // =======
    tonemap_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    tonemap_descriptor_set: [*c]graphics.DescriptorSet,

    pub fn init(self: *PostProcessingRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
        const exposure_settings = ExposureSettings{};

        const exposure_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;

            const exposure_initial_data = [_]f32 {
                exposure_settings.exposure,
                1.0 / exposure_settings.exposure,
                exposure_settings.exposure,
                0.0,
                k_initial_min_log,
                k_initial_max_log,
                k_initial_max_log - k_initial_min_log,
                1.0 / (k_initial_max_log - k_initial_min_log),
            };

            const exposure_data = renderer.Slice{
                .data = @ptrCast(&exposure_initial_data),
                .size = exposure_initial_data.len * @sizeOf(f32),
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createStructuredBuffer(exposure_data, "Exposure");
            }
            break :blk buffers;
        };

        const histogram_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;

            const histogram_data = renderer.Slice{
                .data = null,
                .size = 256 * @sizeOf(u32),
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createStructuredBuffer(histogram_data, "Hisogram");
            }
            break :blk buffers;
        };

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

        const tonemap_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(TonemapConstantBuffer);
            }

            break :blk buffers;
        };

        const generate_histogram_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(GenerateHistogramConstantBuffer);
            }

            break :blk buffers;
        };

        const adapt_exposure_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(AdaptExposureConstantBuffer);
            }

            break :blk buffers;
        };

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .bloom_settings = .{},
            .exposure_settings = exposure_settings,
            .exposure_buffers = exposure_buffers,
            .histogram_buffers = histogram_buffers,
            .generate_histogram_buffers = generate_histogram_buffers,
            .adapt_exposure_buffers = adapt_exposure_buffers,
            .clear_uav_descriptor_set = undefined,
            .generate_histogram_descriptor_set = undefined,
            .draw_debug_histogram_descriptor_set = undefined,
            .adapt_exposure_descriptor_set = undefined,
            .bloom_extract_constant_buffers = bloom_extract_constant_buffers,
            .downsample_bloom_constant_buffers = downsample_bloom_constant_buffers,
            .upsample_and_blur_constant_buffers = upsample_and_blur_constant_buffers,
            .bloom_extract_descriptor_set = undefined,
            .downsample_bloom_descriptor_set = undefined,
            .bloom_blur_descriptor_set = undefined,
            .upsample_and_blur_1_descriptor_set = undefined,
            .upsample_and_blur_2_descriptor_set = undefined,
            .upsample_and_blur_3_descriptor_set = undefined,
            .upsample_and_blur_4_descriptor_set = undefined,
            .tonemap_constant_buffers = tonemap_constant_buffers,
            .tonemap_descriptor_set = undefined,
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

    // self.hdr_tonemap_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.renderer.gpu_profile_token, "HDR Tone Mapping", .{ .bUseMarker = true});
    // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.hdr_tonemap_profile_token);

    // Bloom
    if (self.bloom_settings.enabled) {
        // self.bloom_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.renderer.gpu_profile_token, "Generate Bloom", .{ .bUseMarker = true});
        // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.bloom_profile_token);

        var rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

        // Bloom Extract
        {
            const bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
            const luma = self.renderer.getTexture(self.renderer.luma_lr);
            const exposure_buffer = self.renderer.getBuffer(self.exposure_buffers[frame_index]);

            var t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(bloom_uav1a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                graphics.TextureBarrier.init(luma, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
            };
            var buffer_barriers = [_]graphics.BufferBarrier{
                graphics.BufferBarrier.init(exposure_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), t_barriers.len, @constCast(&t_barriers), 0, null);

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
    }

    // Tonemap
    {
        var rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

        const luminance = self.renderer.getTexture(self.renderer.luminance);
        var t_barriers = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(luminance, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);

        // Update constant buffer
        {
            var constant_buffer_data = std.mem.zeroes(TonemapConstantBuffer);
            constant_buffer_data.rpc_buffer_dimensions[0] = 1.0 / @as(f32, @floatFromInt(self.renderer.window_width));
            constant_buffer_data.rpc_buffer_dimensions[1] = 1.0 / @as(f32, @floatFromInt(self.renderer.window_height));
            constant_buffer_data.bloom_strength = self.bloom_settings.bloom_strength;
            constant_buffer_data.paper_white_ratio = 0.2;
            constant_buffer_data.max_brightness = 1000.0;

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
        graphics.cmdDispatch(cmd_list, (@as(u32, @intCast(self.renderer.window_width)) + 8 - 1) / 8, (@as(u32, @intCast(self.renderer.window_height)) + 8 - 1) / 8, 1);

        rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

        t_barriers = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(luminance, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);
    }

    // Adapt exposure
    {
        // self.update_exposure_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.renderer.gpu_profile_token, "Update Exposure", .{ .bUseMarker = true});
        // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.update_exposure_profile_token);

        const luma = self.renderer.getTexture(self.renderer.luma_lr);
        const luma_width: u32 = @intCast(luma[0].bitfield_1.mWidth);
        const luma_height: u32 = @intCast(luma[0].bitfield_1.mHeight);
        const histogram_buffer = self.renderer.getBuffer(self.histogram_buffers[frame_index]);
        const exposure_buffer = self.renderer.getBuffer(self.exposure_buffers[frame_index]);
        var texture_barriers = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(luma, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        var input_buffer_barriers = [_]graphics.BufferBarrier{
            graphics.BufferBarrier.init(histogram_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
        };
        graphics.cmdResourceBarrier(cmd_list, input_buffer_barriers.len, @constCast(&input_buffer_barriers), texture_barriers.len, @constCast(&texture_barriers), 0, null);

        // Update constant buffer
        {
            var constant_buffer_data = std.mem.zeroes(GenerateHistogramConstantBuffer);
            constant_buffer_data.buffer_height = luma_height;

            const data = renderer.Slice{
                .data = @ptrCast(&constant_buffer_data),
                .size = @sizeOf(GenerateHistogramConstantBuffer),
            };
            self.renderer.updateBuffer(data, GenerateHistogramConstantBuffer, self.generate_histogram_buffers[frame_index]);
        }

        // Clear histogram
        {
            const pipeline_id = IdLocal.init("clear_uav");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.clear_uav_descriptor_set);
            graphics.cmdDispatch(cmd_list, 256 / 32, 1, 1);
        }

        // Generate histogram
        {
            const pipeline_id = IdLocal.init("generate_histogram");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.generate_histogram_descriptor_set);
            graphics.cmdDispatch(cmd_list, (luma_width + 16 - 1) / 16, 1, 1);
        }

        const draw_histogram = false;

        // Debug Draw histogram
        if (draw_histogram) {
            var debug_draw_histogram_barriers = [_]graphics.BufferBarrier{
                graphics.BufferBarrier.init(histogram_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };

            var debug_draw_histogram_rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
            };
            graphics.cmdResourceBarrier(cmd_list, debug_draw_histogram_barriers.len, @constCast(&debug_draw_histogram_barriers), 0, null, debug_draw_histogram_rt_barriers.len, @ptrCast(&debug_draw_histogram_rt_barriers));

            const pipeline_id = IdLocal.init("debug_draw_histogram");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.draw_debug_histogram_descriptor_set);
            graphics.cmdDispatch(cmd_list, 1, 32, 1);

            debug_draw_histogram_rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, debug_draw_histogram_rt_barriers.len, @ptrCast(&debug_draw_histogram_rt_barriers));
        }

        var num_output_buffer_barriers: u32 = 1;
        var output_buffer_barriers: [2]graphics.BufferBarrier = undefined;
        output_buffer_barriers[0] = graphics.BufferBarrier.init(exposure_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS);

        if (!draw_histogram) {
            num_output_buffer_barriers = 2;
            output_buffer_barriers[1] = graphics.BufferBarrier.init(histogram_buffer, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE);
        }

        graphics.cmdResourceBarrier(cmd_list, num_output_buffer_barriers, @constCast(&output_buffer_barriers), 0, null, 0, null);

        // Adapt Exposure
        if (self.exposure_settings.enable_adaptation) {

            // Update constant buffer
            {
                var constant_buffer_data = std.mem.zeroes(AdaptExposureConstantBuffer);
                constant_buffer_data.target_luminance = self.exposure_settings.target_luminance;
                constant_buffer_data.adaptation_rate = self.exposure_settings.adapation_rate;
                constant_buffer_data.min_exposure = self.exposure_settings.min_exposure;
                constant_buffer_data.max_exposure = self.exposure_settings.max_exposure;
                constant_buffer_data.pixel_count = luma_width * luma_height;

                const data = renderer.Slice{
                    .data = @ptrCast(&constant_buffer_data),
                    .size = @sizeOf(AdaptExposureConstantBuffer),
                };
                self.renderer.updateBuffer(data, AdaptExposureConstantBuffer, self.adapt_exposure_buffers[frame_index]);
            }

            const pipeline_id = IdLocal.init("adapt_exposure");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.adapt_exposure_descriptor_set);
            graphics.cmdDispatch(cmd_list, 1, 1, 1);
        }
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
        // _ = zgui.checkbox("Bloom Enabled", .{ .v = &self.bloom_settings.enabled });
        _ = zgui.dragFloat("Threshold", .{ .v = &self.bloom_settings.bloom_threshold, .cfmt = "%.2f", .min = 0.05, .max = 1.0, .speed = 0.01 });
        _ = zgui.dragFloat("Strength", .{ .v = &self.bloom_settings.bloom_strength, .cfmt = "%.2f", .min = 0.0, .max = 10.0, .speed = 0.01 });
    }

    if (zgui.collapsingHeader("Exposure", .{})) {
        _ = zgui.checkbox("Adaptive Exposure", .{ .v = &self.exposure_settings.enable_adaptation });
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

    root_signature = self.renderer.getRootSignature(IdLocal.init("upsample_and_blur"));
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_DRAW;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_1_descriptor_set));
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_2_descriptor_set));
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_3_descriptor_set));
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.upsample_and_blur_4_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("tonemap"));
    desc.pRootSignature = root_signature;
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.tonemap_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("generate_histogram"));
    desc.pRootSignature = root_signature;
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.generate_histogram_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("debug_draw_histogram"));
    desc.pRootSignature = root_signature;
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.draw_debug_histogram_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("adapt_exposure"));
    desc.pRootSignature = root_signature;
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.adapt_exposure_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("clear_uav"));
    desc.pRootSignature = root_signature;
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.clear_uav_descriptor_set));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

    // Bloom Extract
    for (0..renderer.Renderer.data_buffer_count) |i| {
        var bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
        var luma = self.renderer.getTexture(self.renderer.luma_lr);
        var params: [5]graphics.DescriptorData = undefined;
        var exposure_buffer = self.renderer.getBuffer(self.exposure_buffers[i]);
        var bloom_extract_constant_buffer = self.renderer.getBuffer(self.bloom_extract_constant_buffers[i]);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cb0";
        params[0].__union_field3.ppBuffers = @ptrCast(&bloom_extract_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "SourceTex";
        params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "Exposure";
        params[2].__union_field3.ppBuffers = @ptrCast(&exposure_buffer);
        params[3] = std.mem.zeroes(graphics.DescriptorData);
        params[3].pName = "BloomResult";
        params[3].__union_field3.ppTextures = @ptrCast(&bloom_uav1a);
        params[4] = std.mem.zeroes(graphics.DescriptorData);
        params[4].pName = "LumaResult";
        params[4].__union_field3.ppTextures = @ptrCast(&luma);

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
        params[1].pName = "BloomBuf";
        params[1].__union_field3.ppTextures = @ptrCast(&bloom_uav1a);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "Result1";
        params[2].__union_field3.ppTextures = @ptrCast(&bloom_uav2a);
        params[3] = std.mem.zeroes(graphics.DescriptorData);
        params[3].pName = "Result2";
        params[3].__union_field3.ppTextures = @ptrCast(&bloom_uav3a);
        params[4] = std.mem.zeroes(graphics.DescriptorData);
        params[4].pName = "Result3";
        params[4].__union_field3.ppTextures = @ptrCast(&bloom_uav4a);
        params[5] = std.mem.zeroes(graphics.DescriptorData);
        params[5].pName = "Result4";
        params[5].__union_field3.ppTextures = @ptrCast(&bloom_uav5a);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.downsample_bloom_descriptor_set, params.len, @ptrCast(&params));
    }

    // Bloom Blur
    for (0..renderer.Renderer.data_buffer_count) |i| {
        var params: [2]graphics.DescriptorData = undefined;
        var bloom_uav5a = self.renderer.getTexture(self.renderer.bloom_uav5[0]);
        var bloom_uav5b = self.renderer.getTexture(self.renderer.bloom_uav5[1]);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "InputBuf";
        params[0].__union_field3.ppTextures = @ptrCast(&bloom_uav5a);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "Result";
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
            params[1].pName = "HigherResBuf";
            params[1].__union_field3.ppTextures = @ptrCast(&higher_res_buffer);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "LowerResBuf";
            params[2].__union_field3.ppTextures = @ptrCast(&lower_res_buffer);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "Result";
            params[3].__union_field3.ppTextures = @ptrCast(&result_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), descriptor_set, params.len, @ptrCast(&params));
        }
    }

    // Tonemap
    for (0..renderer.Renderer.data_buffer_count) |frame_index| {
        var params: [5]graphics.DescriptorData = undefined;
        var tonemap_constant_buffer = self.renderer.getBuffer(self.tonemap_constant_buffers[frame_index]);
        var bloom_uav1b = self.renderer.getTexture(self.renderer.bloom_uav1[1]);
        var exposure_buffer = self.renderer.getBuffer(self.exposure_buffers[frame_index]);
        var luminance = self.renderer.getTexture(self.renderer.luminance);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "CB0";
        params[0].__union_field3.ppBuffers = @ptrCast(&tonemap_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "Exposure";
        params[1].__union_field3.ppBuffers = @ptrCast(&exposure_buffer);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "Bloom";
        params[2].__union_field3.ppTextures = @ptrCast(&bloom_uav1b);
        params[3] = std.mem.zeroes(graphics.DescriptorData);
        params[3].pName = "ColorRW";
        params[3].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
        params[4] = std.mem.zeroes(graphics.DescriptorData);
        params[4].pName = "OutLuma";
        params[4].__union_field3.ppTextures = @ptrCast(&luminance);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.tonemap_descriptor_set, params.len, @ptrCast(&params));
    }

    // Exposure
    for (0..renderer.Renderer.data_buffer_count) |frame_index| {
        var params: [3]graphics.DescriptorData = undefined;
        var generate_histogram_constant_buffer = self.renderer.getBuffer(self.generate_histogram_buffers[frame_index]);
        var adapt_exposure_constant_buffer = self.renderer.getBuffer(self.adapt_exposure_buffers[frame_index]);
        var histogram_buffer = self.renderer.getBuffer(self.histogram_buffers[frame_index]);
        var exposure_buffer = self.renderer.getBuffer(self.exposure_buffers[frame_index]);
        var luma = self.renderer.getTexture(self.renderer.luma_lr);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "CB0";
        params[0].__union_field3.ppBuffers = @ptrCast(&generate_histogram_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "LumaBuf";
        params[1].__union_field3.ppTextures = @ptrCast(&luma);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "Histogram";
        params[2].__union_field3.ppBuffers = @ptrCast(&histogram_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.generate_histogram_descriptor_set, params.len, @ptrCast(&params));

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cb0";
        params[0].__union_field3.ppBuffers = @ptrCast(&adapt_exposure_constant_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "Histogram";
        params[1].__union_field3.ppBuffers = @ptrCast(&histogram_buffer);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "Exposure";
        params[2].__union_field3.ppBuffers = @ptrCast(&exposure_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.adapt_exposure_descriptor_set, params.len, @ptrCast(&params));

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "OutputBuffer";
        params[0].__union_field3.ppBuffers = @ptrCast(&histogram_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.clear_uav_descriptor_set, 1, @ptrCast(&params));

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "Histogram";
        params[0].__union_field3.ppBuffers = @ptrCast(&histogram_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "Exposure";
        params[1].__union_field3.ppBuffers = @ptrCast(&exposure_buffer);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "ColorBuffer";
        params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.draw_debug_histogram_descriptor_set, params.len, @ptrCast(&params));
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
    graphics.removeDescriptorSet(self.renderer.renderer, self.tonemap_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.generate_histogram_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.draw_debug_histogram_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.adapt_exposure_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.clear_uav_descriptor_set);
}
