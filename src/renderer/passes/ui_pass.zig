const std = @import("std");

const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../renderer.zig");
const renderer_types = @import("../types.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const OpaqueSlice = util.OpaqueSlice;
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const UniformFrameData = struct {
    screen_to_clip: [16]f32,
    ui_instance_buffer_index: u32,
};

const max_instances = 1000;

pub const UIPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,
    index_buffer: renderer.BufferHandle,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_set: [*c]graphics.DescriptorSet,
    instances: std.ArrayList(renderer_types.UiImage),
    instance_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    pub fn init(self: *@This(), rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;
        self.instances = std.ArrayList(renderer_types.UiImage).init(allocator);

        self.uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        self.index_buffer = blk: {
            const indices = [_]u16{ 0, 1, 2, 0, 3, 1 };

            const buffer_data = OpaqueSlice{
                .data = @constCast(&indices),
                .size = 6 * @sizeOf(u16),
            };

            break :blk rctx.createIndexBuffer(buffer_data, @sizeOf(u16), false, "UI Index Buffer");
        };

        self.instance_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createBindlessBuffer(max_instances * @sizeOf(renderer_types.UiImage), "UI Instance Buffer");
            }

            break :blk buffers;
        };
    }

    pub fn destroy(self: *@This()) void {
        self.instances.deinit();
    }

    pub fn update(self: *@This()) void {
        const frame_index = self.renderer.frame_index;

        self.instances.clearRetainingCapacity();
        self.instances.appendSlice(self.renderer.ui_images.items) catch unreachable;

        if (self.instances.items.len > 0) {
            const instance_data_slice = OpaqueSlice{
                .data = @ptrCast(self.instances.items),
                .size = self.instances.items.len * @sizeOf(renderer_types.UiImage),
            };
            self.renderer.updateBuffer(instance_data_slice, 0, renderer_types.UiImage, self.instance_buffers[frame_index]);
        }
    }

    pub fn render(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "UI Render Pass", 0x00_ff_ff_00);
        defer trazy_zone.End();

        if (self.instances.items.len == 0) {
            return;
        }

        const frame_index = self.renderer.frame_index;

        var uniform_frame_data: UniformFrameData = undefined;
        uniform_frame_data.screen_to_clip = std.mem.zeroes([16]f32);
        uniform_frame_data.screen_to_clip[0] = 2.0 / render_view.viewport[0];
        uniform_frame_data.screen_to_clip[5] = -2.0 / render_view.viewport[1];
        uniform_frame_data.screen_to_clip[10] = 0.5;
        uniform_frame_data.screen_to_clip[12] = -1.0;
        uniform_frame_data.screen_to_clip[13] = 1.0;
        uniform_frame_data.screen_to_clip[14] = 0.5;
        uniform_frame_data.screen_to_clip[15] = 1.0;
        uniform_frame_data.ui_instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_buffers[frame_index]);

        const data = OpaqueSlice{
            .data = @ptrCast(&uniform_frame_data),
            .size = @sizeOf(UniformFrameData),
        };
        self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers[frame_index]);

        const pipeline_id = IdLocal.init("ui");
        const pipeline = self.renderer.getPSO(pipeline_id);

        const index_buffer = self.renderer.getBuffer(self.index_buffer);

        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, 0, self.descriptor_set);
        graphics.cmdBindIndexBuffer(cmd_list, index_buffer, @intCast(graphics.IndexType.INDEX_TYPE_UINT16.bits), 0);
        graphics.cmdDrawIndexedInstanced(cmd_list, 6, 0, @intCast(self.instances.items.len), 0, 0);
    }

    pub fn createDescriptorSets(self: *@This()) void {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("ui"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.descriptor_set));
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        for (0..renderer.Renderer.data_buffer_count) |i| {
            var params: [1]graphics.DescriptorData = undefined;

            var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbFrame";
            params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_set, 1, @ptrCast(&params));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
    }
};
