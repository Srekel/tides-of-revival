const std = @import("std");
const zm = @import("zmath");
const zd3d12 = @import("zd3d12");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;
const BufferHandle = @import("d3d12/buffer.zig").BufferHandle;

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

pub const BoundingBoxCoordinates = struct {
    center: [3]f32,
    radius: f32,
};

pub const Mesh = struct {
    vertex_buffer: BufferHandle,
    index_buffer: BufferHandle,
    num_lods: u32,
    lods: [max_num_lods]MeshLod,
    bounding_box: BoundingBox,

    pub fn calculateBoundingBoxCoordinates(mesh: *const Mesh, z_world: zm.Mat) BoundingBoxCoordinates {
        var z_bb_min = zm.loadArr3(mesh.bounding_box.min);
        z_bb_min[3] = 1.0;
        var z_bb_max = zm.loadArr3(mesh.bounding_box.max);
        z_bb_max[3] = 1.0;
        const z_bb_min_ws = zm.mul(z_bb_min, z_world);
        const z_bb_max_ws = zm.mul(z_bb_max, z_world);
        const z_center = (z_bb_max_ws + z_bb_min_ws) * zm.f32x4(0.5, 0.5, 0.5, 0.5);
        var center = [3]f32{ 0.0, 0.0, 0.0 };
        zm.storeArr3(&center, z_center);
        const z_extents = (z_bb_max_ws - z_bb_min_ws) * zm.f32x4(0.5, 0.5, 0.5, 0.5);
        const radius = @max(z_extents[0], @max(z_extents[1], z_extents[2]));

        return .{ .center = center, .radius = radius };
    }
};

pub const IndexType = u32;

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [4]f32,
    color: [3]f32,
};

pub const TextureDesc = struct {
    state: d3d12.RESOURCE_STATES, // TODO: Replace this with non-d3d12 state enum
    name: [*:0]const u16,
};

pub const Texture = struct {
    resource: ?*d3d12.IResource,
    persistent_descriptor: zd3d12.PersistentDescriptor,
};
