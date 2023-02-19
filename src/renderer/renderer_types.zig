const std = @import("std");

pub const IndexType = u32;

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [4]f32,
    color: [3]f32,
};