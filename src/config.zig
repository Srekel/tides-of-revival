const IdLocal = @import("variant.zig").IdLocal;

// ████████╗███████╗██████╗ ██████╗  █████╗ ██╗███╗   ██╗
// ╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║
//    ██║   █████╗  ██████╔╝██████╔╝███████║██║██╔██╗ ██║
//    ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║
//    ██║   ███████╗██║  ██║██║  ██║██║  ██║██║██║ ╚████║
//    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const largest_patch_width = 512;
pub const patch_width = 512;
pub const noise_scale_xz = 1.0 / 2.0;
pub const noise_scale_y = 200;
pub const noise_offset_y = 0.0;

pub const input_move_left = IdLocal.init("move_left");
pub const input_move_right = IdLocal.init("move_right");
pub const input_move_forward = IdLocal.init("move_forward");
pub const input_move_backward = IdLocal.init("move_backward");
pub const input_move_up = IdLocal.init("move_up");
pub const input_move_down = IdLocal.init("move_down");
pub const input_move_slow = IdLocal.init("move_slow");
pub const input_move_fast = IdLocal.init("move_fast");

pub const input_interact = IdLocal.init("interact");

pub const input_cursor_pos = IdLocal.init("cursor_pos");
pub const input_cursor_movement = IdLocal.init("cursor_movement");
pub const input_cursor_movement_x = IdLocal.init("cursor_movement_x");
pub const input_cursor_movement_y = IdLocal.init("cursor_movement_y");

pub const input_gamepad_look_x = IdLocal.init("input_gamepad_look_x");
pub const input_gamepad_look_y = IdLocal.init("input_gamepad_look_y");
pub const input_gamepad_move_x = IdLocal.init("input_gamepad_move_x");
pub const input_gamepad_move_y = IdLocal.init("input_gamepad_move_y");

pub const input_look_yaw = IdLocal.init("look_yaw");
pub const input_look_pitch = IdLocal.init("look_pitch");

pub const input_camera_switch = IdLocal.init("camera_switch");
pub const input_exit = IdLocal.init("exit");
