const std = @import("std");
const math = std.math;
const glfw = @import("glfw");
const zgpu = @import("zgpu");
const gpu = zgpu.gpu;
const c = zgpu.cimgui;
const zm = @import("zmath");

const font = "content/fonts/Roboto-Medium.ttf";

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

const GfxState = struct {
    allocator: std.mem.Allocator,

    gfx_ctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,
};

pub fn init(allocator: std.mem.Allocator, window: glfw.Window) !GfxState {
    const gfx_ctx = try zgpu.GraphicsContext.init(allocator, window);

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

    // Create a depth texture and it's 'view'.
    const depth = createDepthTexture(gfx_ctx);

    zgpu.gui.init(window, gfx_ctx.device, font, 12.0);

    return GfxState{
        .allocator = allocator,
        .gfx_ctx = gfx_ctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
    };
}

pub fn deinit(state: *GfxState) void {
    zgpu.gui.deinit();
    state.gfx_ctx.deinit(state.allocator);
}

// pub fn createWindow(title: [*:0]const u8) !glfw.Window {
//     // const shareWindow = if (windows.items.len > 0) windows.items[0] else null;
//     const shareWindow = if (windows.items.len > 10000) windows.items[0] else null;
//     const window = try glfw.Window.create(1280, 720, title, null, shareWindow, .{ .client_api = .no_api });
//     try windows.append(window);
//     return window;
// }

// pub fn destroyWindow(window_to_destroy: glfw.Window) void {
//     for (windows.items) |window, i| {
//         if (window.handle == window_to_destroy.handle) {
//             _ = windows.swapRemove(i);
//             break;
//         }
//     } else {
//         std.debug.assert(false); //error
//     }

//     window_to_destroy.destroy();
// }

pub fn update(state: *GfxState) void {
    _ = state;
    zgpu.gui.newFrame(
        state.gfx_ctx.swapchain_descriptor.width,
        state.gfx_ctx.swapchain_descriptor.height,
    );
    c.igShowDemoWindow(null);
}

pub fn draw(state: *GfxState) void {
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

    const commands = commands: {
        const encoder = gfx_ctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const vb_info = gfx_ctx.lookupResourceInfo(state.vertex_buffer) orelse break :pass;
            const ib_info = gfx_ctx.lookupResourceInfo(state.index_buffer) orelse break :pass;
            const pipeline = gfx_ctx.lookupResource(state.pipeline) orelse break :pass;
            const bind_group = gfx_ctx.lookupResource(state.bind_group) orelse break :pass;
            const depth_view = gfx_ctx.lookupResource(state.depth_texture_view) orelse break :pass;

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
                const object_to_world = zm.mul(zm.rotationY(t), zm.translation(-0.5, 0.0, 0.0));
                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gfx_ctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(3, 1, 0, 0, 0);
            }

            // Draw triangle 2.
            {
                const object_to_world = zm.mul(zm.rotationY(0.75 * t), zm.translation(0.0, 0.0, 0.0));
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

            zgpu.gui.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    if (gfx_ctx.submitAndPresent(&.{commands}) == .swap_chain_resized) {
        // Release old depth texture.
        gfx_ctx.destroyResource(state.depth_texture_view);
        gfx_ctx.destroyResource(state.depth_texture);

        // Create a new depth texture to match the new window size.
        const depth = createDepthTexture(gfx_ctx);
        state.depth_texture = depth.texture;
        state.depth_texture_view = depth.view;
    }
}

fn createDepthTexture(gfx_ctx: *zgpu.GraphicsContext) struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
} {
    const texture = gfx_ctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .dimension_2d,
        .size = .{
            .width = gfx_ctx.swapchain_descriptor.width,
            .height = gfx_ctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const view = gfx_ctx.createTextureView(texture, .{
        .format = .depth32_float,
        .dimension = .dimension_2d,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .aspect = .depth_only,
    });
    return .{ .texture = texture, .view = view };
}
