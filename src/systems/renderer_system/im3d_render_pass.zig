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
const max_vertices: u32 = 4 * 4096;
const im3d_vertex_size: u64 = @sizeOf(im3d.Im3d.VertexData);

const UniformFrameData = struct {
    projection_view: [16]f32,
    viewport: [2]f32,
};

pub const Im3dRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    lines_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    triangles_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    points_vertex_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    lines_descriptor_set: [*c]graphics.DescriptorSet,
    triangles_descriptor_set: [*c]graphics.DescriptorSet,
    points_descriptor_set: [*c]graphics.DescriptorSet,

    pub fn init(self: *Im3dRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
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
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, im3d_vertex_size, true, "Im3d Line Vertex Buffer");
            }

            break :blk buffers;
        };

        const triangles_vertex_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            const buffer_data = renderer.Slice{
                .data = undefined,
                .size = max_vertices * im3d_vertex_size,
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, im3d_vertex_size, true, "Im3d Triangles Vertex Buffer");
            }

            break :blk buffers;
        };

        const points_vertex_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            const buffer_data = renderer.Slice{
                .data = undefined,
                .size = max_vertices * im3d_vertex_size,
            };

            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createVertexBuffer(buffer_data, im3d_vertex_size, true, "Im3d points Vertex Buffer");
            }

            break :blk buffers;
        };

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .lines_vertex_buffers = lines_vertex_buffers,
            .triangles_vertex_buffers = triangles_vertex_buffers,
            .points_vertex_buffers = points_vertex_buffers,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .lines_descriptor_set = undefined,
            .triangles_descriptor_set = undefined,
            .points_descriptor_set = undefined,
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_ui_pass_fn = render,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *Im3dRenderPass) void {
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
    const trazy_zone = ztracy.ZoneNC(@src(), "Im3D", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });

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

        if (draw_list.m_primType.bits == im3d.Im3d.DrawPrimitiveType.DrawPrimitive_Triangles.bits) {
            const vertex_data = renderer.Slice{
                .data = @ptrCast(draw_list.m_vertexData),
                .size = draw_list.m_vertexCount * im3d_vertex_size,
            };

            self.renderer.updateBuffer(vertex_data, im3d.Im3d.VertexData, self.triangles_vertex_buffers[frame_index]);

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
            const vertex_data = renderer.Slice{
                .data = @ptrCast(draw_list.m_vertexData),
                .size = draw_list.m_vertexCount * im3d_vertex_size,
            };

            self.renderer.updateBuffer(vertex_data, im3d.Im3d.VertexData, self.points_vertex_buffers[frame_index]);

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

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));

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

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));

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

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *Im3dRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.lines_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.triangles_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.points_descriptor_set);
}
