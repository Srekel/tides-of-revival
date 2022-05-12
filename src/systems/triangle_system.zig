const std = @import("std");
const math = std.math;
const glfw = @import("glfw");
const zgpu = @import("zgpu");
const gpu = zgpu.gpu;
const c = zgpu.cimgui;
const zm = @import("zmath");

// zig fmt: off
const wgsl_vs =
\\  @group(0) @binding(0) var<uniform> object_to_clip : mat4x4<f32>;
\\  struct VertexOut {
\\      @builtin(position) position_clip : vec4<f32>,
\\      @location(0) color : vec3<f32>,
\\  }
\\  @stage(vertex) fn main(
\\      @location(0) position : vec3<f32>,
\\      @location(1) color : vec3<f32>,
\\  ) -> VertexOut {
\\      var output : VertexOut;
\\      output.position_clip = vec4(position, 1.0) * object_to_clip;
\\      output.color = color;
\\      return output;
\\ }
;
const wgsl_fs =
\\  @stage(fragment) fn main(
\\      @location(0) color : vec3<f32>,
\\  ) -> @location(0) vec4<f32> {
\\      return vec4(color, 1.0);
\\  }
// zig fmt: on
;

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
};

const SystemState = struct {
    allocator: std.mem.Allocator,

    gfx_ctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
};

pub fn create(allocator: std.mem.Allocator, gfx_ctx: *zgpu.GraphicsContext) !SystemState {

    // Create a bind group layout needed for our render pipeline.
    const bgl = gfx_ctx.createBindGroupLayout(
        gpu.BindGroupLayout.Descriptor{
            .entries = &.{
                gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, true, 0),
            },
        },
    );
    defer gfx_ctx.destroyResource(bgl);

    const pl = gfx_ctx.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor{
        .bind_group_layouts = &.{gfx_ctx.lookupResource(bgl).?},
    });
    defer pl.release();

    const pipeline = pipline: {
        const vs_module = gfx_ctx.device.createShaderModule(&.{ .label = "vs", .code = .{ .wgsl = wgsl_vs } });
        defer vs_module.release();

        const fs_module = gfx_ctx.device.createShaderModule(&.{ .label = "fs", .code = .{ .wgsl = wgsl_fs } });
        defer fs_module.release();

        const color_target = gpu.ColorTargetState{
            .format = zgpu.GraphicsContext.swapchain_format,
            .blend = &.{ .color = .{}, .alpha = .{} },
        };

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @sizeOf([3]f32), .shader_location = 1 },
        };
        const vertex_buffer_layout = gpu.VertexBufferLayout{
            .array_stride = @sizeOf(Vertex),
            .step_mode = .vertex,
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        };

        const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
            .layout = pl,
            .vertex = gpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffers = &.{vertex_buffer_layout},
            },
            .primitive = gpu.PrimitiveState{
                .front_face = .ccw,
                .cull_mode = .none,
                .topology = .triangle_list,
            },
            .depth_stencil = &gpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &gpu.FragmentState{
                .module = fs_module,
                .entry_point = "main",
                .targets = &.{color_target},
            },
        };
        break :pipline gfx_ctx.createRenderPipeline(pipeline_descriptor);
    };

    const bind_group = gfx_ctx.createBindGroup(bgl, &[_]zgpu.BindGroupEntryInfo{
        .{ .binding = 0, .buffer_handle = gfx_ctx.uniforms.buffer, .offset = 0, .size = @sizeOf(zm.Mat) },
    });

    // Create a vertex buffer.
    const vertex_buffer = gfx_ctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = 3 * @sizeOf(Vertex),
    });
    const vertex_data = [_]Vertex{
        .{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [3]f32{ 1.0, 0.0, 0.0 } },
        .{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 1.0, 0.0 } },
        .{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 0.0, 1.0 } },
    };
    gfx_ctx.queue.writeBuffer(gfx_ctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

    // Create an index buffer.
    const index_buffer = gfx_ctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = 3 * @sizeOf(u32),
    });
    const index_data = [_]u32{ 0, 1, 2 };
    gfx_ctx.queue.writeBuffer(gfx_ctx.lookupResource(index_buffer).?, 0, u32, index_data[0..]);

    return SystemState{
        .allocator = allocator,
        .gfx_ctx = gfx_ctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}

pub fn deinit(state: *SystemState) void {
    // zgpu.gui.deinit();
    // state.gfx_ctx.deinit(state.allocator);
}

pub fn update(state: *SystemState) void {
    const gfx_ctx = state.gfx_ctx;
    const fb_width = gfx_ctx.swapchain_descriptor.width;
    const fb_height = gfx_ctx.swapchain_descriptor.height;
    const t = @floatCast(f32, gfx_ctx.stats.time);

    const cam_world_to_view = zm.lookAtLh(
        zm.f32x4(3.0, 3.0, -3.0, 1.0),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * math.pi,
        @intToFloat(f32, fb_width) / @intToFloat(f32, fb_height),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    const back_buffer_view = gfx_ctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands_blk: {
        const encoder = gfx_ctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass_blk: {
            const vb_info = gfx_ctx.lookupResourceInfo(state.vertex_buffer) orelse break :pass;
            const ib_info = gfx_ctx.lookupResourceInfo(state.index_buffer) orelse break :pass;
            const pipeline = gfx_ctx.lookupResource(state.pipeline) orelse break :pass;
            const bind_group = gfx_ctx.lookupResource(state.bind_group) orelse break :pass;

            const color_attachment = gpu.RenderPassColorAttachment{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            };
            const depth_attachment = gpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = gpu.RenderPassEncoder.Descriptor{
                .color_attachments = &.{color_attachment},
                .depth_stencil_attachment = &depth_attachment,
            };
            const pass = encoder.beginRenderPass(&render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
            pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);

            pass.setPipeline(pipeline);

            // Draw triangle 1.
            {
                const object_to_world = zm.mul(zm.rotationY(t), zm.translation(-1.0, 0.0, 0.0));
                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gfx_ctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(3, 1, 0, 0, 0);
            }

            // Draw triangle 2.
            {
                const object_to_world = zm.mul(zm.rotationY(0.75 * t), zm.translation(1.0, 0.0, 0.0));
                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gfx_ctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(3, 1, 0, 0, 0);
            }
        }
        {
            const color_attachment = gpu.RenderPassColorAttachment{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            };
            const render_pass_info = gpu.RenderPassEncoder.Descriptor{
                .color_attachments = &.{color_attachment},
            };
            const pass = encoder.beginRenderPass(&render_pass_info);
            defer {
                pass.end();
                pass.release();
            }
        }

        break :commands_blk encoder.finish(null);
    };
    defer commands.release();
}
