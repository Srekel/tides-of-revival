const ID = @import("../core/core.zig").ID;

pub const move_left = ID("move_left");
pub const move_right = ID("move_right");
pub const move_forward = ID("move_forward");
pub const move_backward = ID("move_backward");
pub const move_up = ID("move_up");
pub const move_down = ID("move_down");
pub const move_slow = ID("move_slow");
pub const move_fast = ID("move_fast");

pub const interact = ID("interact");
pub const wielded_use_primary = ID("wielded_use_primary");
pub const wielded_use_secondary = ID("wielded_use_secondary");

pub const cursor_pos = ID("cursor_pos");
pub const cursor_movement = ID("cursor_movement");
pub const cursor_movement_x = ID("cursor_movement_x");
pub const cursor_movement_y = ID("cursor_movement_y");

pub const gamepad_look_x = ID("gamepad_look_x");
pub const gamepad_look_y = ID("gamepad_look_y");
pub const gamepad_move_x = ID("gamepad_move_x");
pub const gamepad_move_y = ID("gamepad_move_y");

pub const look_yaw = ID("look_yaw");
pub const look_pitch = ID("look_pitch");

pub const draw_bounding_spheres = ID("draw_bounding_spheres");
pub const camera_switch = ID("camera_switch");
pub const camera_freeze_rendering = ID("camera_freeze_rendering");
pub const exit = ID("exit");

pub const view_mode_lit = ID("view_mode_lit");
pub const view_mode_albedo = ID("view_mode_albedo");
pub const view_mode_world_normal = ID("view_mode_world_normal");
pub const view_mode_metallic = ID("view_mode_metallic");
pub const view_mode_roughness = ID("view_mode_roughness");
pub const view_mode_ao = ID("view_mode_ao");
pub const view_mode_depth = ID("view_mode_depth");
