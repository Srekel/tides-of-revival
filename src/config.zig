const zm = @import("zmath");
const zphy = @import("zphysics");
const IdLocal = @import("variant.zig").IdLocal;
const AK = @import("wwise-zig");

pub const events = @import("events.zig");

pub const UP_Z = zm.f32x4(0, 1, 0, 1);
pub const FORWARD_Z = zm.f32x4(0, 0, 1, 1);
pub const RIGHT_Z = zm.f32x4(1, 0, 0, 1);
pub const PITCH_Z = RIGHT_Z;
pub const YAW_Z = UP_Z;
pub const ROLL_Z = FORWARD_Z;

// ████████╗███████╗██████╗ ██████╗  █████╗ ██╗███╗   ██╗
// ╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║
//    ██║   █████╗  ██████╔╝██████╔╝███████║██║██╔██╗ ██║
//    ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║
//    ██║   ███████╗██║  ██║██║  ██║██║  ██║██║██║ ╚████║
//    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const patch_size = 64; // 2^6 m
pub const largest_patch_width = 512;
pub const patch_resolution = 65;
pub const patch_samples = patch_resolution * patch_resolution;
pub const patch_width = 512; // obsolete
pub const noise_scale_xz = 1.0 / 2.0;
pub const noise_scale_y = terrain_span;
pub const noise_offset_y = 0.0;

pub const terrain_height_ocean_floor = 0;
pub const terrain_height_mountain_top = 500;
pub const terrain_min = terrain_height_ocean_floor;
pub const terrain_max = terrain_height_mountain_top;
pub const terrain_span = terrain_height_mountain_top - terrain_height_ocean_floor;

// ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗
// ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝
// ██║██╔██╗ ██║██████╔╝██║   ██║   ██║
// ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║
// ██║██║ ╚████║██║     ╚██████╔╝   ██║
// ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝

pub const input_move_left = IdLocal.init("move_left");
pub const input_move_right = IdLocal.init("move_right");
pub const input_move_forward = IdLocal.init("move_forward");
pub const input_move_backward = IdLocal.init("move_backward");
pub const input_move_up = IdLocal.init("move_up");
pub const input_move_down = IdLocal.init("move_down");
pub const input_move_slow = IdLocal.init("move_slow");
pub const input_move_fast = IdLocal.init("move_fast");

pub const input_interact = IdLocal.init("interact");
pub const input_wielded_use_primary = IdLocal.init("wielded_use_primary");
pub const input_wielded_use_secondary = IdLocal.init("wielded_use_secondary");

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

pub const input_draw_bounding_spheres = IdLocal.init("draw_bounding_spheres");
pub const input_camera_switch = IdLocal.init("camera_switch");
pub const input_camera_freeze_rendering = IdLocal.init("camera_freeze_rendering");
pub const input_exit = IdLocal.init("exit");

//  ██████╗████████╗██╗  ██╗
// ██╔════╝╚══██╔══╝╚██╗██╔╝
// ██║        ██║    ╚███╔╝
// ██║        ██║    ██╔██╗
// ╚██████╗   ██║   ██╔╝ ██╗
//  ╚═════╝   ╚═╝   ╚═╝  ╚═╝

pub const allocator = IdLocal.init("allocator");
pub const event_manager = IdLocal.init("event_manager");
pub const ecsu_world = IdLocal.init("ecsu_world");
pub const input_frame_data = IdLocal.init("input_frame_data");
pub const physics_world = IdLocal.init("physics_world");
pub const world_patch_mgr = IdLocal.init("world_patch_mgr");
pub const prefab_manager = IdLocal.init("prefab_manager");

// ██████╗ ██╗  ██╗██╗   ██╗███████╗██╗ ██████╗███████╗
// ██╔══██╗██║  ██║╚██╗ ██╔╝██╔════╝██║██╔════╝██╔════╝
// ██████╔╝███████║ ╚████╔╝ ███████╗██║██║     ███████╗
// ██╔═══╝ ██╔══██║  ╚██╔╝  ╚════██║██║██║     ╚════██║
// ██║     ██║  ██║   ██║   ███████║██║╚██████╗███████║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝ ╚═════╝╚══════╝

pub const object_layers = struct {
    pub const non_moving: zphy.ObjectLayer = 0;
    pub const moving: zphy.ObjectLayer = 1;
    pub const len: u32 = 2;
};

pub const broad_phase_layers = struct {
    pub const non_moving: zphy.BroadPhaseLayer = 0;
    pub const moving: zphy.BroadPhaseLayer = 1;
    pub const len: u32 = 2;
};

//  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗██╗ ██████╗███████╗
// ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║██║██╔════╝██╔════╝
// ██║  ███╗██████╔╝███████║██████╔╝███████║██║██║     ███████╗
// ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║██║██║     ╚════██║
// ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║██║╚██████╗███████║
//  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝

pub const radiance_texture_path = "content/textures/env/kiara_1_dawn_2k_cube_radiance.dds";
pub const irradiance_texture_path = "content/textures/env/kiara_1_dawn_2k_cube_irradiance.dds";
pub const specular_texture_path = "content/textures/env/kiara_1_dawn_2k_cube_specular.dds";

// ███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗
// ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗
// ███████╗██║   ██║██║   ██║██╔██╗ ██║██║  ██║
// ╚════██║██║   ██║██║   ██║██║╚██╗██║██║  ██║
// ███████║╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝
// ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝

pub const audio_player_oid: AK.AkGameObjectID = 10001;
