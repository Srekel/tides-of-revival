const std = @import("std");

const ecs = @import("zflecs");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const renderer_types = @import("../../renderer/types.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const OpaqueSlice = util.OpaqueSlice;
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
    // range[-8.0, 8.0]
    exposure: f32 = 2.0,
};

// Bloom Constant Buffers
// ======================
const BloomExtractConstantBuffer = struct {
    inverse_output_size: [2]f32,
    bloom_threshold: f32,
    exposure: f32,
    inverse_exposure: f32,
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

// Tonemap Constant Buffer
// =======================
const TonemapConstantBuffer = struct {
    rpc_buffer_dimensions: [2]f32,
    bloom_strength: f32,

    exposure: f32,
};

// Vignette
// ========
const VignetteSettings = struct {
    enabled: bool,
    color: [3]f32,
    radius: f32,
    feather: f32,
};

const VignetteConstantBuffer = struct {
    rpc_buffer_dimensions: [2]f32,
    radius: f32,
    feather: f32,
    color: [3]f32,
    _padding0: f32,
};

pub const PostProcessingPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,

    hdr_tonemap_profile_token: profiler.ProfileToken = undefined,
    bloom_profile_token: profiler.ProfileToken = undefined,

    // Exposure
    // ========
    exposure_settings: ExposureSettings,

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

    // Vignette
    // ========
    vignette_settings: VignetteSettings,
    vignette_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    vignette_descriptor_set: [*c]graphics.DescriptorSet,

    pub fn init(self: *PostProcessingPass, rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;

        self.bloom_settings = BloomSettings{};
        self.exposure_settings = ExposureSettings{ .exposure = 2.0 };

        self.bloom_extract_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(BloomExtractConstantBuffer);
            }

            break :blk buffers;
        };

        self.downsample_bloom_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(DownsampleBloomConstantBuffer);
            }

            break :blk buffers;
        };

        self.upsample_and_blur_constant_buffers = blk: {
            var buffers: [4][renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                for (buffers[buffer_index], 0..) |_, frame_index| {
                    buffers[buffer_index][frame_index] = rctx.createUniformBuffer(UpsampleAndBlurConstantBuffer);
                }
            }

            break :blk buffers;
        };

        self.tonemap_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(TonemapConstantBuffer);
            }

            break :blk buffers;
        };

        self.vignette_settings = .{
            .enabled = true,
            .radius = 0.0,
            .feather = 0.0,
            .color = .{ 0.0, 0.0, 0.0 },
        };
        self.vignette_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(VignetteConstantBuffer);
            }

            break :blk buffers;
        };
    }

    pub fn destroy(_: *PostProcessingPass) void {}

    pub fn render(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Bloom", 0x00_ff_ff_00);
        defer trazy_zone.End();

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
                    constant_buffer_data.exposure = self.exposure_settings.exposure;
                    constant_buffer_data.exposure = 1.0 / self.exposure_settings.exposure;

                    const data = OpaqueSlice{
                        .data = @ptrCast(&constant_buffer_data),
                        .size = @sizeOf(BloomExtractConstantBuffer),
                    };
                    self.renderer.updateBuffer(data, 0, BloomExtractConstantBuffer, self.bloom_extract_constant_buffers[frame_index]);
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

                    const data = OpaqueSlice{
                        .data = @ptrCast(&constant_buffer_data),
                        .size = @sizeOf(DownsampleBloomConstantBuffer),
                    };
                    self.renderer.updateBuffer(data, 0, DownsampleBloomConstantBuffer, self.downsample_bloom_constant_buffers[frame_index]);
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

                const pipeline_id = IdLocal.init("blur_gaussian");
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
            const scene_color_src_state: graphics.ResourceState = if (self.bloom_settings.enabled) .RESOURCE_STATE_SHADER_RESOURCE else .RESOURCE_STATE_RENDER_TARGET;
            var rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, scene_color_src_state, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
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
                constant_buffer_data.rpc_buffer_dimensions[0] = 1.0 / render_view.viewport[0];
                constant_buffer_data.rpc_buffer_dimensions[1] = 1.0 / render_view.viewport[1];
                constant_buffer_data.bloom_strength = self.bloom_settings.bloom_strength;
                constant_buffer_data.exposure = self.exposure_settings.exposure;

                const data = OpaqueSlice{
                    .data = @ptrCast(&constant_buffer_data),
                    .size = @sizeOf(TonemapConstantBuffer),
                };
                self.renderer.updateBuffer(data, 0, TonemapConstantBuffer, self.tonemap_constant_buffers[frame_index]);
            }

            const pipeline_id = IdLocal.init("tonemap");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.tonemap_descriptor_set);
            graphics.cmdDispatch(cmd_list, (@as(u32, @intFromFloat(render_view.viewport[0])) + 8 - 1) / 8, (@as(u32, @intFromFloat(render_view.viewport[1])) + 8 - 1) / 8, 1);

            t_barriers = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(luminance, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };

            if (!self.vignette_settings.enabled) {
                rt_barriers = [_]graphics.RenderTargetBarrier{
                    graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), rt_barriers.len, @ptrCast(&rt_barriers));
            } else {
                graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);
            }
        }

        // Vignette
        if (self.vignette_settings.enabled) {
            // Update constant buffer
            {
                var constant_buffer_data = std.mem.zeroes(VignetteConstantBuffer);
                constant_buffer_data.rpc_buffer_dimensions[0] = 1.0 / render_view.viewport[0];
                constant_buffer_data.rpc_buffer_dimensions[1] = 1.0 / render_view.viewport[1];
                constant_buffer_data.color = self.vignette_settings.color;
                constant_buffer_data.radius = self.vignette_settings.radius;
                constant_buffer_data.feather = self.vignette_settings.feather;
                constant_buffer_data._padding0 = 42;

                const data = OpaqueSlice{
                    .data = @ptrCast(&constant_buffer_data),
                    .size = @sizeOf(VignetteConstantBuffer),
                };
                self.renderer.updateBuffer(data, 0, VignetteConstantBuffer, self.vignette_constant_buffers[frame_index]);
            }

            const pipeline_id = IdLocal.init("vignette");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.vignette_descriptor_set);
            graphics.cmdDispatch(cmd_list, (@as(u32, @intFromFloat(render_view.viewport[0])) + 8 - 1) / 8, (@as(u32, @intFromFloat(render_view.viewport[1])) + 8 - 1) / 8, 1);

            const rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @constCast(&rt_barriers));
        }
    }

    fn upsampleAndBlur(
        self: *@This(),
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

            const data = OpaqueSlice{
                .data = @ptrCast(&constant_buffer_data),
                .size = @sizeOf(UpsampleAndBlurConstantBuffer),
            };
            self.renderer.updateBuffer(data, 0, UpsampleAndBlurConstantBuffer, self.upsample_and_blur_constant_buffers[buffer_index][frame_index]);
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

    pub fn renderImGui(self: *@This()) void {
        if (zgui.collapsingHeader("Post Processing", .{})) {
            if (zgui.collapsingHeader("Bloom", .{ .frame_padding = true })) {
                _ = zgui.checkbox("Bloom Enabled", .{ .v = &self.bloom_settings.enabled });
                _ = zgui.dragFloat("Threshold", .{ .v = &self.bloom_settings.bloom_threshold, .cfmt = "%.2f", .min = 0.05, .max = 1.0, .speed = 0.01 });
                _ = zgui.dragFloat("Strength", .{ .v = &self.bloom_settings.bloom_strength, .cfmt = "%.2f", .min = 0.0, .max = 10.0, .speed = 0.01 });
            }

            if (zgui.collapsingHeader("Exposure Settings", .{ .frame_padding = true })) {
                _ = zgui.dragFloat("Exposure", .{ .v = &self.exposure_settings.exposure, .cfmt = "%.2f", .min = 0.01, .max = 8.0, .speed = 0.01 });
            }

            if (zgui.collapsingHeader("Vignette Settings", .{ .frame_padding = true })) {
                _ = zgui.checkbox("Vignette Enabled", .{ .v = &self.vignette_settings.enabled });
                _ = zgui.colorEdit3("Vignette Color", .{ .col = &self.vignette_settings.color });
                _ = zgui.dragFloat("Radius", .{ .v = &self.vignette_settings.radius, .cfmt = "%.2f", .min = 0.0, .max = 1.0, .speed = 0.01 });
                _ = zgui.dragFloat("Feather", .{ .v = &self.vignette_settings.feather, .cfmt = "%.2f", .min = 0.0, .max = 10.0, .speed = 0.01 });
            }
        }
    }

    pub fn createDescriptorSets(self: *@This()) void {
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;

        var root_signature = self.renderer.getRootSignature(IdLocal.init("bloom_extract"));
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.bloom_extract_descriptor_set));

        root_signature = self.renderer.getRootSignature(IdLocal.init("downsample_bloom_all"));
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.downsample_bloom_descriptor_set));

        root_signature = self.renderer.getRootSignature(IdLocal.init("blur_gaussian"));
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

        root_signature = self.renderer.getRootSignature(IdLocal.init("vignette"));
        desc.pRootSignature = root_signature;
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.vignette_descriptor_set));
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        // Bloom Extract
        for (0..renderer.Renderer.data_buffer_count) |i| {
            var bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
            var params: [3]graphics.DescriptorData = undefined;
            var bloom_extract_constant_buffer = self.renderer.getBuffer(self.bloom_extract_constant_buffers[i]);

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cb0";
            params[0].__union_field3.ppBuffers = @ptrCast(&bloom_extract_constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "SourceTex";
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "BloomResult";
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
            var params: [4]graphics.DescriptorData = undefined;
            var tonemap_constant_buffer = self.renderer.getBuffer(self.tonemap_constant_buffers[frame_index]);
            var bloom_uav1b = self.renderer.getTexture(self.renderer.bloom_uav1[1]);
            var luminance = self.renderer.getTexture(self.renderer.luminance);

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "CB0";
            params[0].__union_field3.ppBuffers = @ptrCast(&tonemap_constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "Bloom";
            params[1].__union_field3.ppTextures = @ptrCast(&bloom_uav1b);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "ColorRW";
            params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "OutLuma";
            params[3].__union_field3.ppTextures = @ptrCast(&luminance);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.tonemap_descriptor_set, params.len, @ptrCast(&params));
        }

        // Vignette
        for (0..renderer.Renderer.data_buffer_count) |frame_index| {
            var vignette_constant_buffer = self.renderer.getBuffer(self.vignette_constant_buffers[frame_index]);

            var params: [2]graphics.DescriptorData = undefined;
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "CB0";
            params[0].__union_field3.ppBuffers = @ptrCast(&vignette_constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "ColorRW";
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.vignette_descriptor_set, params.len, @ptrCast(&params));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.bloom_extract_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.downsample_bloom_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.bloom_blur_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_1_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_2_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_3_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.upsample_and_blur_4_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.tonemap_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.vignette_descriptor_set);
    }
};
