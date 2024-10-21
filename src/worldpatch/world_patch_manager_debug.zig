const std = @import("std");

const zgui = @import("zgui");

const world_patch_manager = @import("world_patch_manager.zig");
const renderer = @import("../renderer/renderer.zig");

pub fn render(world_patch_mgr: *world_patch_manager.WorldPatchManager, rctx: *renderer.Renderer) void {
    _ = rctx; // autofix
    _ = world_patch_mgr; // autofix

    // zgui.backend.newFrame(@intCast(rctx.window_width), @intCast(rctx.window_height));

    if (zgui.button("Hello wpm", .{})) {
        std.log.debug("Clicked on the button", .{});
    }
}
