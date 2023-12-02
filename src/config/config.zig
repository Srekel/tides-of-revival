const zm = @import("zmath");
const zphy = @import("zphysics");
const AK = @import("wwise-zig");
const ID = @import("../core/core.zig").ID;

pub const events = @import("events.zig");
pub const input = @import("input.zig");
pub const prefab = @import("prefab.zig");
pub const system = @import("system.zig");
pub const timeline = @import("timeline.zig");

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

//  ██████╗████████╗██╗  ██╗
// ██╔════╝╚══██╔══╝╚██╗██╔╝
// ██║        ██║    ╚███╔╝
// ██║        ██║    ██╔██╗
// ╚██████╗   ██║   ██╔╝ ██╗
//  ╚═════╝   ╚═╝   ╚═╝  ╚═╝

pub const allocator = ID("allocator");
pub const event_manager = ID("event_manager");
pub const ecsu_world = ID("ecsu_world");
pub const input_frame_data = ID("input_frame_data");
pub const physics_world = ID("physics_world");
pub const world_patch_mgr = ID("world_patch_mgr");
pub const prefab_manager = ID("prefab_manager");

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
