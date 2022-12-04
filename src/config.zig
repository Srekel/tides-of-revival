const IdLocal = @import("variant.zig").IdLocal;

// ████████╗███████╗██████╗ ██████╗  █████╗ ██╗███╗   ██╗
// ╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║
//    ██║   █████╗  ██████╔╝██████╔╝███████║██║██╔██╗ ██║
//    ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║
//    ██║   ███████╗██║  ██║██║  ██║██║  ██║██║██║ ╚████║
//    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const patch_width = 512;
pub const noise_scale_xz = 5.0;
pub const noise_scale_y = 200;
pub const noise_offset_y = 0.6;

// pub fn heightAtXZ(noise:)

pub const input_move_left = IdLocal.init("move_left");
pub const input_move_right = IdLocal.init("move_right");
pub const input_move_forward = IdLocal.init("move_forward");
pub const input_move_backward = IdLocal.init("move_backward");
pub const input_move_slow = IdLocal.init("move_slow");
pub const input_move_fast = IdLocal.init("move_fast");

pub const input_cursor_pos = IdLocal.init("cursor_pos");
pub const input_cursor_movement = IdLocal.init("cursor_movement");
pub const input_cursor_movement_x = IdLocal.init("cursor_movement_x");
pub const input_cursor_movement_y = IdLocal.init("cursor_movement_y");

pub const input_camera_switch = IdLocal.init("camera_switch");
