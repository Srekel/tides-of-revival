const std = @import("std");
const window = @import("renderer/window.zig");
const config = @import("config/config.zig");
const input = @import("input.zig");
const zglfw = @import("zglfw");
const renderer = @import("renderer/tides_renderer.zig");

const zm = @import("zmath");

const SystemState = struct {
    allocator: std.mem.Allocator,
    main_window: *window.Window,
    app_settings: renderer.AppSettings,
    input_frame_data: input.FrameData,
};

pub fn run() void {
    var system_state: SystemState = undefined;
    system_state.allocator = std.heap.page_allocator;

    // GFX
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    system_state.main_window = window.createWindow("Tides of Revival: Z-Forge Wasn't Built In A Day") catch unreachable;
    // system_state.main_window.window.setInputMode(.cursor, .disabled);

    // Initialize Tides Renderer
    const nativeWindowHandle = zglfw.native.getWin32Window(system_state.main_window.window) catch unreachable;
    system_state.app_settings = renderer.AppSettings{
        .width = 1920,
        .height = 1080,
        .window_native_handle = @as(*anyopaque, @constCast(nativeWindowHandle)),
        .v_sync_enabled = true,
    };
    var success = renderer.initRenderer(&system_state.app_settings);
    if (success != 0) {
        std.log.err("Failed to initialize Tides Renderer", .{});
        return;
    }
    var reload_desc = renderer.ReloadDesc{
        .reload_type = renderer.ReloadType.ALL,
    };
    defer renderer.exitRenderer();

    if (!renderer.onLoad(&reload_desc)) {
        unreachable;
    }
    defer renderer.onUnload(&reload_desc);

    // Input
    // Run it once to make sure we don't get huge diff values for cursor etc. the first frame.
    const input_target_defaults = config.input.createDefaultTargetDefaults(std.heap.page_allocator);
    const input_keymap = config.input.createKeyMap(std.heap.page_allocator);
    system_state.input_frame_data = input.FrameData.create(std.heap.page_allocator, input_keymap, input_target_defaults, system_state.main_window.window);
    input.doTheThing(system_state.allocator, &system_state.input_frame_data);

    while (true) {
        const done = update(&system_state);
        if (done) {
            break;
        }
    }
}

pub fn update(state: *SystemState) bool {
    input.doTheThing(state.allocator, &state.input_frame_data);

    const window_status = window.update() catch unreachable;
    if (window_status == .no_windows) {
        return true;
    }

    if (state.main_window.frame_buffer_size[0] != state.app_settings.width or state.main_window.frame_buffer_size[1] != state.app_settings.height) {
        state.app_settings.width = state.main_window.frame_buffer_size[0];
        state.app_settings.height = state.main_window.frame_buffer_size[1];

        var reload_desc = renderer.ReloadDesc{
            .reload_type = .{ .RESIZE = true },
        };
        renderer.onUnload(&reload_desc);
        if (!renderer.onLoad(&reload_desc)) {
            unreachable;
        }
    }

    if (state.input_frame_data.just_pressed(config.input.exit)) {
        return true;
    }

    const view_mat_z = zm.lookAtLh(.{ 0.0, 0.0, -1.0, 1.0 }, .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 });
    var camera: renderer.Camera = undefined;
    zm.storeMat(&camera.view_matrix, view_mat_z);

    renderer.draw(camera);

    return false;
}
