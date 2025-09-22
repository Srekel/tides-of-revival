const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const InvalidResourceIndex = std.math.maxInt(u32);

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