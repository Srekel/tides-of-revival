const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zm = @import("zmath");
const wgpu = zgpu.wgpu;

pub const GfxState = struct {
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,
    command_buffers: std.ArrayList(wgpu.CommandBuffer),
};

pub fn init(allocator: std.mem.Allocator, window: zglfw.Window) !GfxState {
    const gctx = try zgpu.GraphicsContext.init(allocator, window);

    // Create a depth texture and it's 'view'.
    const depth = createDepthTexture(gctx);

    return GfxState{
        .allocator = allocator,
        .gctx = gctx,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
        .command_buffers = std.ArrayList(wgpu.CommandBuffer).init(allocator),
    };
}

pub fn deinit(state: *GfxState) void {
    state.gctx.deinit(state.allocator);
}

pub fn update(state: *GfxState) void {
    const back_buffer_view = state.gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();
}

pub fn draw(state: *GfxState) void {
    const gctx = state.gctx;
    gctx.submit(state.command_buffers.items);
    for (state.command_buffers.items) |cmd| {
        cmd.release();
    }
    state.command_buffers.clearRetainingCapacity();

    if (gctx.present() == .swap_chain_resized) {
        // Release old depth texture.
        gctx.releaseResource(state.depth_texture_view);
        gctx.destroyResource(state.depth_texture);

        // Create a new depth texture to match the new window size.
        const depth = createDepthTexture(gctx);
        state.depth_texture = depth.texture;
        state.depth_texture_view = depth.view;
    }
}

fn createDepthTexture(gctx: *zgpu.GraphicsContext) struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
} {
    const texture = gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = gctx.swapchain_descriptor.width,
            .height = gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{
        .format = .depth32_float,
        .dimension = .tvdim_2d,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .aspect = .depth_only,
    });
    return .{ .texture = texture, .view = view };
}
