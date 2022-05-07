const std = @import("std");
const math = std.math;
const glfw = @import("glfw");
const zgpu = @import("zgpu");
const gpu = zgpu.gpu;
const c = zgpu.cimgui;
const zm = @import("zmath");

// const imgui_font = @import("build_options").imgui_font;
const window_title = "The Elvengroin Legacy";

var windows: std.ArrayList(glfw.Window) = undefined;

// pub fn run() !void {
//     defer window.destroy();

//     // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     // defer _ = gpa.deinit();

//     // const allocator = gpa.allocator();

//     // var demo = try init(allocator, window);
//     // defer deinit(allocator, &demo);

//     zgpu.gui.init(window, demo.gctx.device, "content/Roboto-Medium.ttf", 25.0);
//     defer zgpu.gui.deinit();

//     while (!window.shouldClose()) {
//         try glfw.pollEvents();
//         // update(&demo);
//         // draw(&demo);
//     }
// }

pub fn init(allocator: std.mem.Allocator) !void {
    try glfw.init(.{});
    windows = std.ArrayList(glfw.Window).init(allocator);
}

pub fn deinit() void {
    windows.deinit();
    glfw.terminate();
}

pub fn createWindow(title: [*:0]const u8) !glfw.Window {
    // const shareWindow = if (windows.items.len > 0) windows.items[0] else null;
    const shareWindow = if (windows.items.len > 10000) windows.items[0] else null;
    const window = try glfw.Window.create(1280, 720, title, null, shareWindow, .{ .client_api = .no_api });
    try windows.append(window);
    return window;
}

pub fn destroyWindow(window_to_destroy: glfw.Window) void {
    for (windows.items) |window, i| {
        if (window.handle == window_to_destroy.handle) {
            _ = windows.swapRemove(i);
            break;
        }
    } else {
        std.debug.assert(false); //error
    }

    window_to_destroy.destroy();
}

pub fn update() !enum { no_windows, has_windows } {
    var check_windows = true;
    while (check_windows) {
        check_windows = false;
        for (windows.items) |window| {
            if (window.shouldClose()) {
                destroyWindow(window);
                check_windows = true;
                break;
            }
        }
    }

    if (windows.items.len == 0) {
        return .no_windows;
    }

    try glfw.pollEvents();
    return .has_windows;
}
