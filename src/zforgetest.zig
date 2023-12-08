const std = @import("std");
const window = @import("renderer/window.zig");
const config = @import("config/config.zig");
const input = @import("input.zig");
const zglfw = @import("zglfw");
const renderer = @import("renderer/tides_renderer.zig");

const zm = @import("zmath");

pub fn run() void {
    // GFX
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    main_window.setInputMode(.cursor, .disabled);

    // Initialize Tides Renderer
    const nativeWindowHandle = zglfw.native.getWin32Window(main_window) catch unreachable;
    var success = renderer.initRenderer(1920, 1080, @as(*anyopaque, @constCast(nativeWindowHandle)));
    if (success != 0) {
        std.log.err("Failed to initialize Tides Renderer", .{});
        return;
    }
    defer renderer.exitRenderer();

    // Input
    // Run it once to make sure we don't get huge diff values for cursor etc. the first frame.
    const input_target_defaults = config.input.createDefaultTargetDefaults(std.heap.page_allocator);
    const input_keymap = config.input.createKeyMap(std.heap.page_allocator);
    var input_frame_data = input.FrameData.create(std.heap.page_allocator, input_keymap, input_target_defaults, main_window);
    input.doTheThing(std.heap.page_allocator, &input_frame_data);

    var allocator = std.heap.page_allocator;

    while (true) {
        const done = update(allocator, &input_frame_data);
        if (done) {
            break;
        }
    }
}

pub fn update(allocator: std.mem.Allocator, input_frame_data: *input.FrameData) bool {
    input.doTheThing(allocator, input_frame_data);

    const window_status = window.update(null) catch unreachable;
    if (window_status == .no_windows) {
        return true;
    }
    if (input_frame_data.just_pressed(config.input.exit)) {
        return true;
    }

    const view_mat_z = zm.lookAtLh(.{ 0.0, 0.0, -1.0, 1.0 }, .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 });
    var camera: renderer.Camera = undefined;
    zm.storeMat(&camera.view_matrix, view_mat_z);

    renderer.draw(camera);

    return false;
}
