const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const InvalidResourceIndex = std.math.maxInt(u32);

pub const GpuLight = struct {
    position: [3]f32,   // Direction for directional light
    light_type: u32,    // 0 - Directional, 1 - Point
    color: [3]f32,
    intensity: f32,
    cast_shadows: u32 = 0,  // 0 - No, 1 - Yes
    radius: f32 = 0,        // Unused for directional light
    _padding: [2]f32 = [2]f32{ 42, 42 },
};

pub const PointLight = extern struct {
    position: [3]f32,
    radius: f32,
    color: [3]f32,
    intensity: f32,
};

pub const DirectionalLight = extern struct {
    direction: [3]f32,
    shadow_map: i32,
    color: [3]f32,
    intensity: f32,
    shadow_range: f32,
    _pad: [2]f32,
    shadow_map_dimensions: i32,
    view_proj: [16]f32,
};

pub const UpdateDesc = struct {
    sun_light: DirectionalLight = undefined,
    point_lights: *std.ArrayList(PointLight) = undefined,
};

pub const InstanceData = struct {
    object_to_world: [16]f32,
    world_to_object: [16]f32,
    materials_buffer_offset: u32,
    _padding: [3]f32,
};

pub const InstanceDataIndirection = struct {
    instance_index: u32,
    gpu_mesh_index: u32,
    material_index: u32,
    entity_id: u32,
};

pub const InstanceRootConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
    instance_material_buffer_index: u32,
};

pub const TerrainInstanceData = struct {
    object_to_world: [16]f32,
    heightmap_index: u32,
    lod: u32,
    padding1: [2]u32,
};