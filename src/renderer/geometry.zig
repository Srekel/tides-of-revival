const std = @import("std");

pub const sub_mesh_max_count: u32 = 16;
pub const mesh_lod_max_count: u32 = 4;

pub const Meshlet = struct {
    vertex_offset: u32,
    triangle_offset: u32,
    vertex_count: u32,
    triangle_count: u32,
};

pub const MeshletTriangle = packed struct(u32) {
    v0: u10,
    v1: u10,
    v2: u10,
    _padding: u2,
};

pub const MeshletBounds = struct {
    local_center: [3]f32,
    local_extents: [3]f32,
};

pub const BoundingBox = struct {
    center: [3]f32,
    extents: [3]f32,
};

pub const MeshData = struct {
    positions_stream: std.ArrayList([3]f32),
    texcoords_stream: std.ArrayList([2]f32),
    normals_stream: std.ArrayList([3]f32),
    tangents_stream: std.ArrayList([4]f32),
    indices: std.ArrayList(u32),
    bounds: BoundingBox,

    meshlets: std.ArrayList(Meshlet),
    meshlet_vertices: std.ArrayList(u32),
    meshlet_triangles: std.ArrayList(MeshletTriangle),
    meshlet_bounds: std.ArrayList(MeshletBounds),
};

pub const MeshLoadDesc = struct {
    mesh_path: []const u8,
    allocator: std.mem.Allocator,
    mesh_data: *std.ArrayList(MeshData),
};

pub fn loadMesh(load_desc: *MeshLoadDesc) void {
    var file = std.fs.cwd().openFile(load_desc.mesh_path, .{}) catch unreachable;
    defer file.close();
    const reader = file.reader();

    var magic: [9]u8 = undefined;
    var read_length = reader.readAtLeast(&magic, magic.len) catch unreachable;
    std.debug.assert(read_length == magic.len);
    std.debug.assert(std.mem.eql(u8, &magic, "TidesMesh"));

    const mesh_count = reader.readInt(usize, .little) catch unreachable;

    for (0..mesh_count) |_| {
        var mesh_data: MeshData = undefined;

        const index_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.indices = std.ArrayList(u32).init(load_desc.allocator);
        mesh_data.indices.resize(index_count) catch unreachable;

        const positions_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.positions_stream = std.ArrayList([3]f32).init(load_desc.allocator);
        mesh_data.positions_stream.resize(positions_count) catch unreachable;

        const texcoords_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.texcoords_stream = std.ArrayList([2]f32).init(load_desc.allocator);
        mesh_data.texcoords_stream.resize(texcoords_count) catch unreachable;

        const normals_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.normals_stream = std.ArrayList([3]f32).init(load_desc.allocator);
        mesh_data.normals_stream.resize(normals_count) catch unreachable;

        const tangents_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.tangents_stream = std.ArrayList([4]f32).init(load_desc.allocator);
        mesh_data.tangents_stream.resize(tangents_count) catch unreachable;

        const meshlets_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.meshlets = std.ArrayList(Meshlet).init(load_desc.allocator);
        mesh_data.meshlets.resize(meshlets_count) catch unreachable;

        const meshlet_bounds_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.meshlet_bounds = std.ArrayList(MeshletBounds).init(load_desc.allocator);
        mesh_data.meshlet_bounds.resize(meshlet_bounds_count) catch unreachable;

        const meshlet_triangles_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.meshlet_triangles = std.ArrayList(MeshletTriangle).init(load_desc.allocator);
        mesh_data.meshlet_triangles.resize(meshlet_triangles_count) catch unreachable;

        const meshlet_vertices_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.meshlet_vertices = std.ArrayList(u32).init(load_desc.allocator);
        mesh_data.meshlet_vertices.resize(meshlet_vertices_count) catch unreachable;

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.indices.items), mesh_data.indices.items.len * @sizeOf(u32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.indices.items.len * @sizeOf(u32));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.positions_stream.items), mesh_data.positions_stream.items.len * @sizeOf([3]f32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.positions_stream.items.len * @sizeOf([3]f32));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.texcoords_stream.items), mesh_data.texcoords_stream.items.len * @sizeOf([2]f32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.texcoords_stream.items.len * @sizeOf([2]f32));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.normals_stream.items), mesh_data.normals_stream.items.len * @sizeOf([3]f32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.normals_stream.items.len * @sizeOf([3]f32));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.tangents_stream.items), mesh_data.tangents_stream.items.len * @sizeOf([4]f32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.tangents_stream.items.len * @sizeOf([4]f32));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.meshlets.items), mesh_data.meshlets.items.len * @sizeOf(Meshlet)) catch unreachable;
        std.debug.assert(read_length == mesh_data.meshlets.items.len * @sizeOf(Meshlet));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.meshlet_bounds.items), mesh_data.meshlet_bounds.items.len * @sizeOf(MeshletBounds)) catch unreachable;
        std.debug.assert(read_length == mesh_data.meshlet_bounds.items.len * @sizeOf(MeshletBounds));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.meshlet_triangles.items), mesh_data.meshlet_triangles.items.len * @sizeOf(MeshletTriangle)) catch unreachable;
        std.debug.assert(read_length == mesh_data.meshlet_triangles.items.len * @sizeOf(MeshletTriangle));

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.meshlet_vertices.items), mesh_data.meshlet_vertices.items.len * @sizeOf(u32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.meshlet_vertices.items.len * @sizeOf(u32));

        var position_min = mesh_data.positions_stream.items[0];
        var position_max = mesh_data.positions_stream.items[0];

        for (1..mesh_data.positions_stream.items.len) |i| {
            if (mesh_data.positions_stream.items[i][0] < position_min[0]) {
                position_min[0] = mesh_data.positions_stream.items[i][0];
            }

            if (mesh_data.positions_stream.items[i][1] < position_min[1]) {
                position_min[1] = mesh_data.positions_stream.items[i][1];
            }

            if (mesh_data.positions_stream.items[i][2] < position_min[2]) {
                position_min[2] = mesh_data.positions_stream.items[i][2];
            }

            if (mesh_data.positions_stream.items[i][0] > position_max[0]) {
                position_max[0] = mesh_data.positions_stream.items[i][0];
            }

            if (mesh_data.positions_stream.items[i][1] > position_max[1]) {
                position_max[1] = mesh_data.positions_stream.items[i][1];
            }

            if (mesh_data.positions_stream.items[i][2] > position_max[2]) {
                position_max[2] = mesh_data.positions_stream.items[i][2];
            }
        }

        mesh_data.bounds.center[0] = (position_min[0] + position_max[0]) * 0.5;
        mesh_data.bounds.center[1] = (position_min[1] + position_max[1]) * 0.5;
        mesh_data.bounds.center[2] = (position_min[2] + position_max[2]) * 0.5;

        mesh_data.bounds.extents[0] = (position_max[0] - position_min[0]) * 0.5;
        mesh_data.bounds.extents[1] = (position_max[1] - position_min[1]) * 0.5;
        mesh_data.bounds.extents[2] = (position_max[2] - position_min[2]) * 0.5;

        load_desc.mesh_data.append(mesh_data) catch unreachable;
    }
}

pub fn mergeBoundingBoxes(a: BoundingBox, b: BoundingBox) BoundingBox {
    const a_min = [3]f32{ a.center[0] - a.extents[0], a.center[1] - a.extents[1], a.center[2] - a.extents[2] };
    const a_max = [3]f32{ a.center[0] + a.extents[0], a.center[1] + a.extents[1], a.center[2] + a.extents[2] };
    const b_min = [3]f32{ b.center[0] - b.extents[0], b.center[1] - b.extents[1], b.center[2] - b.extents[2] };
    const b_max = [3]f32{ b.center[0] + b.extents[0], b.center[1] + b.extents[1], b.center[2] + b.extents[2] };

    var result: BoundingBox = undefined;
    const result_min = [3]f32{ @min(a_min[0], b_min[0]), @min(a_min[1], b_min[1]), @min(a_min[2], b_min[2]) };
    const result_max = [3]f32{ @max(a_max[0], b_max[0]), @max(a_max[1], b_max[1]), @max(a_max[2], b_max[2]) };
    result.extents = [3]f32{ (result_max[0] - result_min[0]) * 0.5, (result_max[1] - result_min[1]) * 0.5, (result_max[2] - result_min[2]) * 0.5 };
    result.center = [3]f32{ (result_min[0] + result_max[0]) * 0.5, (result_min[1] + result_max[1]) * 0.5, (result_min[2] + result_max[2]) * 0.5 };
    return result;
}
