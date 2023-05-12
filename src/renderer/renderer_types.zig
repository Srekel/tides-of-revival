const std = @import("std");

pub const max_num_lods: u32 = 8;

pub const MeshLod = struct {
    index_offset: u32,
    index_count: u32,
    vertex_offset: u32,
    vertex_count: u32,
};

pub const BoundingBox = struct {
    min: [3]f32,
    max: [3]f32,
};

pub const Mesh = struct {
    num_lods: u32,
    lods: [max_num_lods]MeshLod,
    bounding_box: BoundingBox,
};

pub const IndexType = u32;

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [4]f32,
    color: [3]f32,
};
