const std = @import("std");
const zglfw = @import("zglfw");

const window_title = "Tides of Revival";

var windows: std.ArrayList(Window) = undefined;

pub const Window = struct {
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

pub fn createWindow(title: [:0]const u8) !*Window {
    // const shareWindow = if (windows.items.len > 0) windows.items[0] else null;
    // const shareWindow = if (windows.items.len > 10000) windows.items[0] else null;
    zglfw.windowHint(.client_api, .no_api);
    const glfw_window = try zglfw.Window.create(1920, 1080, title, null);

    try windows.append(.{
        .window = glfw_window,
        .frame_buffer_size = glfw_window.getFramebufferSize(),
    });

    return &windows.items[windows.items.len - 1];
}

pub fn destroyWindow(window_to_destroy: *Window) void {
    for (windows.items, 0..) |window, i| {
        if (window.window == window_to_destroy.window) {
            _ = windows.swapRemove(i);
            break;
        }
    } else {
        std.debug.assert(false); //error
    }

    window_to_destroy.window.destroy();
}

pub fn update() !enum { no_windows, has_windows } {
    var check_windows = true;
    while (check_windows) {
        check_windows = false;
        for (windows.items) |*window| {
            if (window.window.shouldClose()) {
                destroyWindow(window);
                check_windows = true;
                break;
            }

            const frame_buffer_size = window.window.getFramebufferSize();
            if (!std.meta.eql(window.frame_buffer_size, frame_buffer_size)) {
                window.frame_buffer_size = frame_buffer_size;
                std.log.info(
                    "Window resized to {d}x{d}",
                    .{ window.frame_buffer_size[0], window.frame_buffer_size[1] },
                );
            }
        }
    }

    if (windows.items.len == 0) {
        return .no_windows;
    }

    zglfw.pollEvents();
    return .has_windows;
}
