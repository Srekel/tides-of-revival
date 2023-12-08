// Tides Renderer Zig Bindings
// ===========================
const std = @import("std");

pub const AppSettings = extern struct {
    width: i32,
    height: i32,
    window_native_handle: *anyopaque,
    v_sync_enabled: bool,
};

pub fn initRenderer(app_settings: *AppSettings) i32 {
    return TR_initRenderer(app_settings);
}
extern fn TR_initRenderer(app_settings: *AppSettings) i32;

pub fn exitRenderer() void {
    TR_exitRenderer();
}
extern fn TR_exitRenderer() void;

pub fn onLoad(reload_desc: *ReloadDesc) bool {
    return TR_onLoad(reload_desc);
}
extern fn TR_onLoad(reload_desc: *ReloadDesc) bool;

pub fn onUnload(reload_desc: *ReloadDesc) void {
    TR_onUnload(reload_desc);
}
extern fn TR_onUnload(reload_desc: *ReloadDesc) void;

pub const Camera = extern struct {
    view_matrix: [16]f32,
};

pub fn draw(camera: Camera) void {
    TR_draw(camera);
}
extern fn TR_draw(camera: Camera) void;

pub const ReloadType = packed struct(u32) {
    RESIZE: bool = false, // 0x1
    SHADER: bool = false, // 0x2
    RENDERTARGET: bool = false, // 0x4
    __unused: u29 = 0,

    pub const ALL = ReloadType{
        .RESIZE = true,
        .SHADER = true,
        .RENDERTARGET = true,
    };
};

pub const ReloadDesc = extern struct {
    reload_type: ReloadType,
};
