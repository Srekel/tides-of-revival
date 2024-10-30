const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const BloomConstantBuffer = struct {
    inverse_output_size: [2]f32,
    bloom_threshold: f32,
};

const BloomSettings = struct {
    bloom_threshold: f32 = 4.0,
};

pub const PostProcessingRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,

    // Bloom
    bloom_settings: BloomSettings,
    bloom_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    bloom_descriptor_set: [*c]graphics.DescriptorSet,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *PostProcessingRenderPass {
        const bloom_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(BloomConstantBuffer);
            }

            break :blk buffers;
        };

        const pass = allocator.create(PostProcessingRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .bloom_settings = .{},
            .bloom_constant_buffers = bloom_constant_buffers,
            .bloom_descriptor_set = undefined,
        };

        createDescriptorSets(@ptrCast(pass));
        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *PostProcessingRenderPass) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.bloom_descriptor_set);
        self.allocator.destroy(self);
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

pub const renderFn: renderer.renderPassRenderFn = render;
pub const renderImGuiFn: renderer.renderPassImGuiFn = renderImGui;
pub const createDescriptorSetsFn: renderer.renderPassCreateDescriptorSetsFn = createDescriptorSets;
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Bloom", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    // Bloom
    {
        var rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

        var bloom_uav1a = self.renderer.getTexture(self.renderer.bloom_uav1[0]);
        var t_barriers = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(bloom_uav1a, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, t_barriers.len, @constCast(&t_barriers), 0, null);

        // Update constant buffer
        {
            var constant_buffer_data = std.mem.zeroes(BloomConstantBuffer);
            constant_buffer_data.bloom_threshold = self.bloom_settings.bloom_threshold;
            constant_buffer_data.inverse_output_size[0] = 1.0 / @as(f32, @floatFromInt(self.renderer.bloom_width));
            constant_buffer_data.inverse_output_size[1] = 1.0 / @as(f32, @floatFromInt(self.renderer.bloom_height));

            const data = renderer.Slice{
                .data = @ptrCast(&constant_buffer_data),
                .size = @sizeOf(BloomConstantBuffer),
            };
            self.renderer.updateBuffer(data, BloomConstantBuffer, self.bloom_constant_buffers[frame_index]);
        }

        // Update descriptors
        {
            var params: [3]graphics.DescriptorData = undefined;
            var constant_buffer = self.renderer.getBuffer(self.bloom_constant_buffers[frame_index]);

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cb0";
            params[0].__union_field3.ppBuffers = @ptrCast(&constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "source_tex";
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "bloom_result";
            params[2].__union_field3.ppTextures = @ptrCast(&bloom_uav1a);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.bloom_descriptor_set, 3, @ptrCast(&params));
        }

        const pipeline_id = IdLocal.init("bloom");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, 0, self.bloom_descriptor_set);
        graphics.cmdDispatch(cmd_list, (self.renderer.bloom_width + 8 - 1) / 8, (self.renderer.bloom_height + 8 - 1) / 8, 1);

        var output_barriers = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(bloom_uav1a, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, output_barriers.len, @constCast(&output_barriers), 0, null);
    }
}

fn renderImGui(user_data: *anyopaque) void {
    if (zgui.collapsingHeader("Bloom", .{})) {
        const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

        _ = zgui.dragFloat("Bloom Threshold", .{ .v = &self.bloom_settings.bloom_threshold, .cfmt = "%.2f", .min = 0.1, .max = 10.0, .speed = 0.1 });
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

    const root_signature = self.renderer.getRootSignature(IdLocal.init("bloom"));
    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.bloom_descriptor_set));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    _ = user_data;
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *PostProcessingRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.bloom_descriptor_set);
}

