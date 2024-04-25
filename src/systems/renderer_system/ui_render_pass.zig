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
const im3d = @import("im3d");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const UniformFrameData = struct {
    screen_to_clip: [16]f32,
    ui_instance_buffer_index: u32,
};

const max_instances = 1000;

const UIInstanceData = struct {
    rect: [4]f32,
    color: [4]f32,
    texture_index: u32,
    _padding: [3]u32,
};

pub const UIRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    index_buffer: renderer.BufferHandle,
    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_set: [*c]graphics.DescriptorSet,
    instance_data: std.ArrayList(UIInstanceData),
    instance_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    query_ui_images: ecsu.Query,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *UIRenderPass {
        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        var descriptor_set: [*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("ui"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&descriptor_set));
        }

        const index_buffer = blk: {
            const indices = [_]u16{ 0, 1, 2, 0, 3, 1 };

            const buffer_data = renderer.Slice{
                .data = @constCast(&indices),
                .size = 6 * @sizeOf(u16),
            };

            break :blk rctx.createIndexBuffer(buffer_data, @sizeOf(u16), "UI Index Buffer");
        };

        const instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(UIInstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "UI Instance Buffer");
            }

            break :blk buffers;
        };

        const instance_data = std.ArrayList(UIInstanceData).init(allocator);

        var query_builder_ui = ecsu.QueryBuilder.init(ecsu_world);
        _ = query_builder_ui.withReadonly(fd.UIImage);
        const query_ui_images = query_builder_ui.buildQuery();

        const pass = allocator.create(UIRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .index_buffer = index_buffer,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .descriptor_set = descriptor_set,
            .instance_data_buffers = instance_data_buffers,
            .instance_data = instance_data,
            .query_ui_images = query_ui_images,
        };

        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *UIRenderPass) void {
        self.query_ui_images.deinit();
        self.instance_data.deinit();
        graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
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
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Skybox Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *UIRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    self.uniform_frame_data.screen_to_clip = std.mem.zeroes([16]f32);
    self.uniform_frame_data.screen_to_clip[0] = 2.0 / @as(f32, @floatFromInt(self.renderer.window_width));
    self.uniform_frame_data.screen_to_clip[5] = -2.0 / @as(f32, @floatFromInt(self.renderer.window_height));
    self.uniform_frame_data.screen_to_clip[10] = 0.5;
    self.uniform_frame_data.screen_to_clip[12] = -1.0;
    self.uniform_frame_data.screen_to_clip[13] = 1.0;
    self.uniform_frame_data.screen_to_clip[14] = 0.5;
    self.uniform_frame_data.screen_to_clip[15] = 1.0;
    self.uniform_frame_data.ui_instance_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[frame_index]);

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data),
        .size = @sizeOf(UniformFrameData),
    };
    self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);

    var entity_iter_ui = self.query_ui_images.iterator(struct {
        ui_image: *const fd.UIImage,
    });

    self.instance_data.clearRetainingCapacity();

    while (entity_iter_ui.next()) |comps| {
        const ui_image = comps.ui_image;
        const ui_material = ui_image.material;
        self.instance_data.append(.{
            .rect = [4]f32{ ui_image.rect[0], ui_image.rect[1], ui_image.rect[2], ui_image.rect[3] },
            .color = [4]f32{ ui_material.color[0], ui_material.color[1], ui_material.color[2], ui_material.color[3] },
            .texture_index = self.renderer.getTextureBindlessIndex(ui_material.texture),
            ._padding = [3]u32{ 42, 42, 42 },
        }) catch unreachable;
    }

    im3d.Im3d.EndFrame();
    const lol1 = im3d.Im3d.GetDrawListCount();
    _ = lol1; // autofix
    const lol2 = im3d.Im3d.GetDrawLists();
    _ = lol2; // autofix
    // Cool render code goes here

    const instance_data_slice = renderer.Slice{
        .data = @ptrCast(self.instance_data.items),
        .size = self.instance_data.items.len * @sizeOf(UIInstanceData),
    };
    self.renderer.updateBuffer(instance_data_slice, UIInstanceData, self.instance_data_buffers[frame_index]);

    const pipeline_id = IdLocal.init("ui");
    const pipeline = self.renderer.getPSO(pipeline_id);

    const index_buffer = self.renderer.getBuffer(self.index_buffer);

    graphics.cmdBindPipeline(cmd_list, pipeline);
    graphics.cmdBindDescriptorSet(cmd_list, 0, self.descriptor_set);
    graphics.cmdBindIndexBuffer(cmd_list, index_buffer, @intCast(graphics.IndexType.INDEX_TYPE_UINT16.bits), 0);
    graphics.cmdDrawIndexedInstanced(cmd_list, 6, 0, @intCast(self.instance_data.items.len), 0, 0);
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *UIRenderPass = @ptrCast(@alignCast(user_data));

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var params: [1]graphics.DescriptorData = undefined;

        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_set, 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *UIRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
}
