const std = @import("std");
const zm = @import("zmath");
const zphy = @import("zphysics");
const ID = @import("../core/core.zig").ID;
const audio_manager = @import("../audio/audio_manager_mock.zig");

pub const entity = @import("entity.zig");
pub const events = @import("events.zig");
pub const input = @import("input.zig");
pub const prefab = @import("prefab.zig");
pub const system = @import("system.zig");
pub const timeline = @import("timeline.zig");

pub const UP_Z = zm.f32x4(0, 1, 0, 0);
pub const FORWARD_Z = zm.f32x4(0, 0, 1, 0);
pub const RIGHT_Z = zm.f32x4(1, 0, 0, 0);
pub const PITCH_Z = RIGHT_Z;
pub const YAW_Z = UP_Z;
pub const ROLL_Z = FORWARD_Z;

// ████████╗███████╗██████╗ ██████╗  █████╗ ██╗███╗   ██╗
// ╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║
//    ██║   █████╗  ██████╔╝██████╔╝███████║██║██╔██╗ ██║
//    ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║
//    ██║   ███████╗██║  ██║██║  ██║██║  ██║██║██║ ╚████║
//    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const km_size = 1024;
pub const world_size_x = 16 * km_size;
pub const world_size_z = 16 * km_size;
pub const patch_size = 64; // 2^6 m
pub const patch_size_by_lods = .{
    patch_size * 1, // lod0: 64
    patch_size * 2, // lod1: 128
    patch_size * 4, // lod2: 256
    patch_size * 8, // lod3: 512
};
pub const lowest_lod = 3;
pub const largest_patch_width = patch_size_by_lods[lowest_lod];
pub const patch_resolution = patch_size + 1; // 65
pub const patch_samples = patch_resolution * patch_resolution;
pub const noise_scale_xz = 1.0 / 2.0;
pub const noise_scale_y = terrain_span;
pub const noise_offset_y = 0.0;

pub const ocean_level = 50.0;
pub const terrain_height_ocean_floor = 0;
pub const terrain_height_mountain_top = 1000;
pub const terrain_min = terrain_height_ocean_floor;
pub const terrain_max = terrain_height_mountain_top;
pub const terrain_span = terrain_height_mountain_top - terrain_height_ocean_floor;

pub const patch_type_heightmap = ID("heightmap");
pub const patch_type_splatmap = ID("splatmap");
pub const patch_type_props = ID("props");

pub const HeightmapHeader = packed struct {
    version: u8,
    bitdepth: u8,
    height_min: f32,
    height_max: f32,

    pub fn getEdgeSlices(self_data: []const u8) struct {
        top: []const u32,
        bot: []const u32,
        left: []const u32,
        right: []const u32,
    } {
        const top_start = @sizeOf(HeightmapHeader);
        const top_end = top_start + patch_resolution * @sizeOf(u32);
        const bot_start = top_end;
        const bot_end = bot_start + patch_resolution * @sizeOf(u32);
        const left_start = bot_end;
        const left_end = left_start + patch_resolution * @sizeOf(u32);
        const right_start = left_end;
        const right_end = right_start + patch_resolution * @sizeOf(u32);
        const top: []const u32 = @alignCast(std.mem.bytesAsSlice(u32, self_data[top_start..top_end]));
        const bot: []const u32 = @alignCast(std.mem.bytesAsSlice(u32, self_data[bot_start..bot_end]));
        const left: []const u32 = @alignCast(std.mem.bytesAsSlice(u32, self_data[left_start..left_end]));
        const right: []const u32 = @alignCast(std.mem.bytesAsSlice(u32, self_data[right_start..right_end]));
        return .{
            .top = top,
            .bot = bot,
            .left = left,
            .right = right,
        };
    }

    pub fn getInsides(self_data: []const u8, comptime T: type) []const T {
        const edges_start: usize = @sizeOf(HeightmapHeader);
        const edges_end: usize = edges_start + 4 * patch_resolution * @sizeOf(u32);
        const insides_start: usize = edges_end;
        const insides_end: usize = insides_start + (patch_resolution - 2) * (patch_resolution - 2) * @sizeOf(T);
        const insides: []const T = @alignCast(std.mem.bytesAsSlice(T, self_data[insides_start..insides_end]));
        return insides;
    }
};

//  ██████╗████████╗██╗  ██╗
// ██╔════╝╚══██╔══╝╚██╗██╔╝
// ██║        ██║    ╚███╔╝
// ██║        ██║    ██╔██╗
// ╚██████╗   ██║   ██╔╝ ██╗
//  ╚═════╝   ╚═╝   ╚═╝  ╚═╝

pub const allocator = ID("allocator");
pub const event_mgr = ID("event_mgr");
pub const ecsu_world = ID("ecsu_world");
pub const input_frame_data = ID("input_frame_data");
pub const physics_world = ID("physics_world");
pub const world_patch_mgr = ID("world_patch_mgr");
pub const prefab_mgr = ID("prefab_mgr");

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

pub const audio_player_oid: audio_manager.GameObjectID = 10001;

// ███████╗███████╗███╗   ███╗███████╗
// ██╔════╝██╔════╝████╗ ████║██╔════╝
// █████╗  ███████╗██╔████╔██║███████╗
// ██╔══╝  ╚════██║██║╚██╔╝██║╚════██║
// ██║     ███████║██║ ╚═╝ ██║███████║
// ╚═╝     ╚══════╝╚═╝     ╚═╝╚══════╝

// Player controller
pub const FSM_PC = ID("FSM_PC_Idle");
pub const FSM_PC_Idle = ID("FSM_PC_Idle");

// Camera
pub const FSM_CAM = ID("FSM_CAM");
pub const FSM_CAM_Fps = ID("FSM_CAM_Fps");
pub const FSM_CAM_Freefly = ID("FSM_CAM_Freefly");

// Enemy
pub const FSM_ENEMY = ID("FSM_ENEMY");
pub const FSM_ENEMY_Idle = ID("FSM_ENEMY_Idle");
pub const FSM_ENEMY_Slime = ID("FSM_ENEMY_Slime");
