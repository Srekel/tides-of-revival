const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const gpu = zgpu.gpu;
const c = zgpu.cimgui;
const zm = @import("zmath");
const zwin32 = @import("zwin32");
const w32 = zwin32.w32;
const d3d12 = zwin32.d3d12;
const gfx = @import("gfx_d3d12.zig");

// const imgui_font = @import("build_options").imgui_font;
const window_title = "Tides of Revival";

var windows: std.ArrayList(Window) = undefined;

const Window = struct {
    window: *zglfw.Window,
    frame_buffer_size: [2]i32,
};

pub fn init(allocator: std.mem.Allocator) !void {
    try zglfw.init();
    windows = std.ArrayList(Window).init(allocator);
}

pub fn deinit() void {
    windows.deinit();
    zglfw.terminate();
}

pub fn createWindow(title: [:0]const u8) !*zglfw.Window {
    // const shareWindow = if (windows.items.len > 0) windows.items[0] else null;
    // const shareWindow = if (windows.items.len > 10000) windows.items[0] else null;
    const window = try zglfw.Window.create(1280, 720, title, null);

    try windows.append(.{
        .window = window,
        .frame_buffer_size = window.getFramebufferSize(),
    });

    return window;
}

pub fn destroyWindow(window_to_destroy: *zglfw.Window) void {
    for (windows.items, 0..) |window, i| {
        if (window.window == window_to_destroy) {
            _ = windows.swapRemove(i);
            break;
        }
    } else {
        std.debug.assert(false); //error
    }

    window_to_destroy.destroy();
}

pub fn update(gfx_state: *gfx.D3D12State) !enum { no_windows, has_windows } {
    var check_windows = true;
    while (check_windows) {
        check_windows = false;
        for (windows.items) |*window| {
            if (window.window.shouldClose()) {
                destroyWindow(window.window);
                check_windows = true;
                break;
            }

            var frame_buffer_size = window.window.getFramebufferSize();
            if (!std.meta.eql(window.frame_buffer_size, frame_buffer_size)) {
                frame_buffer_size[0] = std.math.max(1, frame_buffer_size[0]);
                frame_buffer_size[1] = std.math.max(1, frame_buffer_size[1]);
                window.frame_buffer_size = frame_buffer_size;
                std.log.info(
                    "Window resized to {d}x{d}",
                    .{ window.frame_buffer_size[0], window.frame_buffer_size[1] },
                );

                _ = gfx_state;

                // gfx_state.gctx.finishGpuCommands();

                // for (gfx_state.gctx.swapchain_buffers) |texture| _ = texture.Release();

                // zwin32.hrPanicOnFail(gfx_state.gctx.swap_chain.ResizeBuffers(0, 0, 0, .UNKNOWN, .{}));

                // for (&gfx_state.gctx.swapchain_buffers, 0..) |*texture, i| {
                //     zwin32.hrPanicOnFail(gfx_state.gctx.swap_chain.GetBuffer(
                //         @intCast(u32, i),
                //         &d3d12.IID_IResource,
                //         @ptrCast(*?*anyopaque, &texture.*),
                //     ));
                // }

                // for (gfx_state.gctx.swapchain_buffers, 0..) |texture, i| {
                //     gfx_state.gctx.device.CreateRenderTargetView(
                //         texture,
                //         null,
                //         .{ .ptr = gfx_state.gctx.rtv_heap_start.ptr +
                //             i * gfx_state.gctx.device.GetDescriptorHandleIncrementSize(.RTV) },
                //     );
                // }
            }
        }
    }

    if (windows.items.len == 0) {
        return .no_windows;
    }

    zglfw.pollEvents();
    return .has_windows;
}
