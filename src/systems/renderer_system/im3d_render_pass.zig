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
const im3d_vertex_size: u64 = @sizeOf(im3d.Im3d.VertexData);

const UniformFrameData = struct {
    projection_view: [16]f32,
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
            .lines_descriptor_set = undefined,
        };

        createDescriptorSets(@ptrCast(pass));
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
pub const createDescriptorSetsFn: renderer.renderPassCreateDescriptorSetsFn = createDescriptorSets;
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Im3D", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });

    const camera_position = camera_comps.transform.getPos00();

    im3d.Im3d.DrawLine(
        &.{ .x = camera_position[0] - 10, .y = camera_position[1] - 10, .z = camera_position[2] + 10 },
        &.{ .x = camera_position[0] + 10, .y = camera_position[1] + 10, .z = camera_position[2] + 10 },
        3.0,
        im3d.Im3d.Color.init5b(1, 0, 1, 1),
    );

    im3d.Im3d.DrawLine(
        &.{ .x = camera_position[0] - 10, .y = camera_position[1] + 10, .z = camera_position[2] + 10 },
        &.{ .x = camera_position[0] + 10, .y = camera_position[1] - 10, .z = camera_position[2] + 10 },
        3.0,
        im3d.Im3d.Color.init5b(1, 0, 1, 1),
    );

    im3d.Im3d.EndFrame();
    const draw_list_count = im3d.Im3d.GetDrawListCount();
    const draw_lists = im3d.Im3d.GetDrawLists();

    const z_view = zm.loadMat(camera_comps.camera.view[0..]);
    const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
    const z_proj_view = zm.mul(z_view, z_proj);

    self.uniform_frame_data.viewport = [2]f32{ @floatFromInt(self.renderer.window_width), @floatFromInt(self.renderer.window_height) };
    zm.storeMat(&self.uniform_frame_data.projection_view, z_proj_view);

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data),
        .size = @sizeOf(UniformFrameData),
    };
    self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);

    for (0..draw_list_count) |i| {
        const draw_list = draw_lists[i];

        if (draw_list.m_primType.bits == im3d.Im3d.DrawPrimitiveType.DrawPrimitive_Lines.bits) {
            const vertex_data = renderer.Slice{
                .data = @ptrCast(draw_list.m_vertexData),
                .size = draw_list.m_vertexCount * im3d_vertex_size,
            };

            self.renderer.updateBuffer(vertex_data, im3d.Im3d.VertexData, self.lines_vertex_buffers[frame_index]);

            const pipeline_id = IdLocal.init("im3d_lines");
            const pipeline = self.renderer.getPSO(pipeline_id);

            const vertex_buffer = self.renderer.getBuffer(self.lines_vertex_buffers[frame_index]);
            const vertex_buffers = [_][*c]graphics.Buffer{vertex_buffer};
            const vertex_buffer_strides = [_]u32{@intCast(im3d_vertex_size)};

            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.lines_descriptor_set);
            graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&vertex_buffer_strides), null);
            graphics.cmdDraw(cmd_list, draw_list.m_vertexCount, 0);
        }
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));

    const root_signature = self.renderer.getRootSignature(IdLocal.init("im3d_lines"));
    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.lines_descriptor_set));
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
