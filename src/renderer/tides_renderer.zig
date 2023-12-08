// Tides Renderer Zig Bindings
// ===========================
const std = @import("std");

pub fn initRenderer(width: i32, height: i32, nativeWindowHandle: *anyopaque) i32 {
    return TR_initRenderer(width, height, nativeWindowHandle);
}
extern fn TR_initRenderer(
    width: i32,
    height: i32,
    nativeWindowHandle: *anyopaque,
) i32;

pub fn exitRenderer() void {
    TR_exitRenderer();
}
extern fn TR_exitRenderer() void;

pub const Camera = extern struct {
    view_matrix: [16]f32,
};

pub fn draw(camera: Camera) void {
    TR_draw(camera);
}
extern fn TR_draw(camera: Camera) void;
