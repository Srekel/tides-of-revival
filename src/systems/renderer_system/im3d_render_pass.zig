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
const max_vertices: u32 = 4096 * 4096;
const im3d_vertex_size: u64 = @sizeOf(f32) * 8;

// cbContextData
const UniformFrameData = struct {
    view_proj: [16]f32,
    viewport: [2]f32,
};

pub const Im3dRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    lines_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    // TODO(gmodarelli): add point and triangle vertex buffers
    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    lines_descriptor_set: [*c]graphics.DescriptorSet,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *Im3dRenderPass {
        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        var lines_descriptor_set: [*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("im3d_lines"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&lines_descriptor_set));
        }

        const lines_vertex_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            const buffer_data = renderer.Slice{
                .data = undefined,
                .size = max_vertices * im3d_vertex_size,
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, @sizeOf(u32), true, "Im3d Line Vertex Buffer");
            }

            break :blk buffers;
        };

        const pass = allocator.create(Im3dRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .lines_vertex_buffers = lines_vertex_buffers,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .lines_descriptor_set = lines_descriptor_set,
        };

        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *Im3dRenderPass) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.lines_descriptor_set);
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

    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;
    _ = frame_index;

    im3d.Im3d.EndFrame();
    const lol1 = im3d.Im3d.GetDrawListCount();
    _ = lol1; // autofix
    const lol2 = im3d.Im3d.GetDrawLists();
    _ = lol2; // autofix
    // Cool render code goes here

    _ = cmd_list;
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var params: [1]graphics.DescriptorData = undefined;

        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbContextData";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.lines_descriptor_set, 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.lines_descriptor_set);
}
