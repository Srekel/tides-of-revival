const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = zgpu.zgui;
const zm = @import("zmath");
const gfx = @import("../gfx_wgpu.zig");
const wgpu = zgpu.wgpu;

const font = "fonts/Roboto-Medium.ttf";

pub const SystemState = struct {
    allocator: std.mem.Allocator,

    gfx: *gfx.GfxState,
    gctx: *zgpu.GraphicsContext,
};

pub fn create(allocator: std.mem.Allocator, gfxstate: *gfx.GfxState, window: zglfw.Window) !SystemState {
    const gctx = gfxstate.gctx;
    zgpu.gui.init(window, gctx.device, "content/", font, 20.0);
    return SystemState{
        .allocator = allocator,
        .gfx = gfxstate,
        .gctx = gctx,
    };
}

pub fn destroy(system: *SystemState) void {
    _ = system;
    zgpu.gui.deinit();
}

pub fn preUpdate(system: *SystemState) void {
    zgpu.gui.newFrame(
        system.gctx.swapchain_descriptor.width,
        system.gctx.swapchain_descriptor.height,
    );
    // c.igShowDemoWindow(null);
}

pub fn update(system: *SystemState) void {
    const gctx = system.gctx;
    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            zgpu.gui.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    system.gfx.command_buffers.append(commands) catch unreachable;
}
