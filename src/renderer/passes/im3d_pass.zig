const std = @import("std");

const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const OpaqueSlice = util.OpaqueSlice;
const zm = @import("zmath");
const im3d = @import("im3d");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;
const max_vertices: u32 = 4 * 4096;
const im3d_vertex_size: u64 = @sizeOf(im3d.Im3d.VertexData);

const UniformFrameData = struct {
    projection_view: [16]f32,
    viewport: [2]f32,
};

pub const Im3dPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,
    lines_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    triangles_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    points_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    lines_descriptor_set: [*c]graphics.DescriptorSet,
    triangles_descriptor_set: [*c]graphics.DescriptorSet,
    points_descriptor_set: [*c]graphics.DescriptorSet,

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

        self.lines_vertex_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            const buffer_data = OpaqueSlice{
                .data = undefined,
                .size = max_vertices * im3d_vertex_size,
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, im3d_vertex_size, true, "Im3d Line Vertex Buffer");
            }

            break :blk buffers;
        };

        self.triangles_vertex_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            const buffer_data = OpaqueSlice{
                .data = undefined,
                .size = max_vertices * im3d_vertex_size,
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, im3d_vertex_size, true, "Im3d Triangles Vertex Buffer");
            }

            break :blk buffers;
        };

        self.points_vertex_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            const buffer_data = OpaqueSlice{
                .data = undefined,
                .size = max_vertices * im3d_vertex_size,
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, im3d_vertex_size, true, "Im3d points Vertex Buffer");
            }

            break :blk buffers;
        };
    }

    pub fn destroy(_: *@This()) void {}

    pub fn render(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Im3D", 0x00_ff_ff_00);
        defer trazy_zone.End();

        const frame_index = self.renderer.frame_index;

        // Im3d samples
        // ============
        // // Lines example
        // {
        //     const camera_position = camera_comps.transform.getPos00();

        //     im3d.Im3d.DrawLine(
        //         &.{ .x = camera_position[0] - 10, .y = camera_position[1] - 10, .z = camera_position[2] + 10 },
        //         &.{ .x = camera_position[0] + 10, .y = camera_position[1] + 10, .z = camera_position[2] + 10 },
        //         3.0,
        //         im3d.Im3d.Color.init5b(1, 0, 1, 1),
        //     );

        //     im3d.Im3d.DrawLine(
        //         &.{ .x = camera_position[0] - 10, .y = camera_position[1] + 10, .z = camera_position[2] + 10 },
        //         &.{ .x = camera_position[0] + 10, .y = camera_position[1] - 10, .z = camera_position[2] + 10 },
        //         3.0,
        //         im3d.Im3d.Color.init5b(1, 0, 1, 1),
        //     );
        // }

        // // Triangles example
        // {
        //     const camera_position = camera_comps.transform.getPos00();

        //     im3d.Im3d.PushDrawState();
        //     im3d.Im3d.SetAlpha(0.7);
        //     im3d.Im3d.PushMatrix();
        //     var world_matrix = std.mem.zeroes(im3d.Im3d.Mat4);
        //     world_matrix.m[0] = 1.0;
        //     world_matrix.m[5] = 1.0;
        //     world_matrix.m[10] = 1.0;
        //     world_matrix.m[15] = 1.0;
        //     world_matrix.setTranslation(&.{ .x = camera_position[0], .y = camera_position[1], .z = camera_position[2] + 5 });
        //     im3d.Im3d.MulMatrix(&world_matrix);
        //     im3d.Im3d.BeginTriangles();
        //     im3d.Im3d.Vertex__Overload6(-1.0, 0.0, -1.0, im3d.Im3d.Color.init5b(1, 0, 0, 1));
        //     im3d.Im3d.Vertex__Overload6(0.0, 1.0, -1.0, im3d.Im3d.Color.init5b(0, 1, 0, 1));
        //     im3d.Im3d.Vertex__Overload6(1.0, 0.0, -1.0, im3d.Im3d.Color.init5b(0, 0, 1, 1));
        //     im3d.Im3d.End();
        //     im3d.Im3d.PopMatrix();
        //     im3d.Im3d.PopDrawState();
        // }

        // // Points example
        // {
        //     const camera_position = camera_comps.transform.getPos00();

        //     im3d.Im3d.PushDrawState();
        //     im3d.Im3d.PushMatrix();
        //     var world_matrix = std.mem.zeroes(im3d.Im3d.Mat4);
        //     world_matrix.m[0] = 1.0;
        //     world_matrix.m[5] = 1.0;
        //     world_matrix.m[10] = 1.0;
        //     world_matrix.m[15] = 1.0;
        //     world_matrix.setTranslation(&.{ .x = camera_position[0], .y = camera_position[1] + 1, .z = camera_position[2] + 2 });
        //     im3d.Im3d.SetMatrix(&world_matrix);
        //     im3d.Im3d.BeginPoints();
        //     im3d.Im3d.Vertex__Overload4(&.{ .x = 0.0, .y = 0.0, .z = 0.0 }, 20, im3d.Im3d.Color.init5b(1, 1, 1, 1));
        //     im3d.Im3d.End();
        //     im3d.Im3d.PopMatrix();
        //     im3d.Im3d.PopDrawState();
        // }

        // {
        //     im3d.Im3d.DrawLine(
        //         &.{ .x = 0.0, .y = 0.0, .z = 0.0 },
        //         &.{ .x = 10.0, .y = 0.0, .z = 0.0 },
        //         3.0,
        //         im3d.Im3d.Color.init5b(1, 0, 0, 1),
        //     );
        //     im3d.Im3d.DrawLine(
        //         &.{ .x = 0.0, .y = 0.0, .z = 0.0 },
        //         &.{ .x = 0.0, .y = 10.0, .z = 0.0 },
        //         3.0,
        //         im3d.Im3d.Color.init5b(0, 1, 0, 1),
        //     );
        //     im3d.Im3d.DrawLine(
        //         &.{ .x = 0.0, .y = 0.0, .z = 0.0 },
        //         &.{ .x = 0.0, .y = 0.0, .z = 1.0 },
        //         3.0,
        //         im3d.Im3d.Color.init5b(0, 0, 1, 1),
        //     );
        // }

        im3d.Im3d.EndFrame();
        const draw_list_count = im3d.Im3d.GetDrawListCount();
        const draw_lists = im3d.Im3d.GetDrawLists();

        var uniform_frame_data: UniformFrameData = undefined;
        uniform_frame_data.viewport = render_view.viewport;
        zm.storeMat(&uniform_frame_data.projection_view, render_view.view_projection);

        const data = OpaqueSlice{
            .data = @ptrCast(&uniform_frame_data),
            .size = @sizeOf(UniformFrameData),
        };
        self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers[frame_index]);

        for (0..draw_list_count) |i| {
            const draw_list = draw_lists[i];

            if (draw_list.m_primType.bits == im3d.Im3d.DrawPrimitiveType.DrawPrimitive_Lines.bits) {
                const vertex_data = OpaqueSlice{
                    .data = @ptrCast(draw_list.m_vertexData),
                    .size = draw_list.m_vertexCount * im3d_vertex_size,
                };

                self.renderer.updateBuffer(vertex_data, 0, im3d.Im3d.VertexData, self.lines_vertex_buffers[frame_index]);

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

            if (draw_list.m_primType.bits == im3d.Im3d.DrawPrimitiveType.DrawPrimitive_Triangles.bits) {
                const vertex_data = OpaqueSlice{
                    .data = @ptrCast(draw_list.m_vertexData),
                    .size = draw_list.m_vertexCount * im3d_vertex_size,
                };

                self.renderer.updateBuffer(vertex_data, 0, im3d.Im3d.VertexData, self.triangles_vertex_buffers[frame_index]);

                const pipeline_id = IdLocal.init("im3d_triangles");
                const pipeline = self.renderer.getPSO(pipeline_id);

                const vertex_buffer = self.renderer.getBuffer(self.triangles_vertex_buffers[frame_index]);
                const vertex_buffers = [_][*c]graphics.Buffer{vertex_buffer};
                const vertex_buffer_strides = [_]u32{@intCast(im3d_vertex_size)};

                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, 0, self.triangles_descriptor_set);
                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&vertex_buffer_strides), null);
                graphics.cmdDraw(cmd_list, draw_list.m_vertexCount, 0);
            }

            if (draw_list.m_primType.bits == im3d.Im3d.DrawPrimitiveType.DrawPrimitive_Points.bits) {
                const vertex_data = OpaqueSlice{
                    .data = @ptrCast(draw_list.m_vertexData),
                    .size = draw_list.m_vertexCount * im3d_vertex_size,
                };

                self.renderer.updateBuffer(vertex_data, 0, im3d.Im3d.VertexData, self.points_vertex_buffers[frame_index]);

                const pipeline_id = IdLocal.init("im3d_points");
                const pipeline = self.renderer.getPSO(pipeline_id);

                const vertex_buffer = self.renderer.getBuffer(self.points_vertex_buffers[frame_index]);
                const vertex_buffers = [_][*c]graphics.Buffer{vertex_buffer};
                const vertex_buffer_strides = [_]u32{@intCast(im3d_vertex_size)};

                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, 0, self.points_descriptor_set);
                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&vertex_buffer_strides), null);
                graphics.cmdDraw(cmd_list, draw_list.m_vertexCount, 0);
            }
        }
    }

    pub fn createDescriptorSets(self: *@This()) void {
        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("im3d_lines"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.lines_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("im3d_triangles"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.triangles_descriptor_set));
        }

        {
            const root_signature = self.renderer.getRootSignature(IdLocal.init("im3d_points"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.points_descriptor_set));
        }
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        for (0..renderer.Renderer.data_buffer_count) |i| {
            var params: [1]graphics.DescriptorData = undefined;

            var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbContextData";
            params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.lines_descriptor_set, 1, @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.triangles_descriptor_set, 1, @ptrCast(&params));
            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.points_descriptor_set, 1, @ptrCast(&params));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.lines_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.triangles_descriptor_set);
        graphics.removeDescriptorSet(self.renderer.renderer, self.points_descriptor_set);
    }
};
