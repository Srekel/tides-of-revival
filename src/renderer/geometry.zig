const std = @import("std");

pub const BoundingBox = struct {
    center: [3]f32,
    extents: [3]f32,
};

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [4]f32,
    uv: [2]f32,
};

pub const SubMesh = struct {
    index_count: u32,
    index_offset: u32,
    vertex_count: u32,
    vertex_offset: u32,
    bounds: BoundingBox,
};

pub const sub_mesh_max_count: u32 = 32;
pub const mesh_lod_max_count: u32 = 4;

pub const Mesh = struct {
    sub_mesh_count: u32,
    sub_meshes: [sub_mesh_max_count]SubMesh,
};

pub const MeshData = struct {
    interlaved: bool,
    meshlets: bool,

    indices: std.ArrayList(u32),
    first_index: u32,
    vertices: std.ArrayList(Vertex),
    first_vertex: u32,

    positions_stream: std.ArrayList([3]f32),
    texcoords_stream: std.ArrayList([2]f32),
    normals_stream: std.ArrayList([3]f32),
    // TODO tangents_stream: ?std.ArrayList([4]f32),
    bounds: BoundingBox,
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

    // Read flags
    const flags = reader.readInt(u32, .little) catch unreachable;
    var interleaved = false;
    var meshlets = false;
    if ((flags & 0x1) == 0x1) interleaved = true;
    if ((flags & 0x2) == 0x2) meshlets = true;
    std.debug.assert(meshlets == false);

    const mesh_count = reader.readInt(usize, .little) catch unreachable;

    for (0..mesh_count) |_| {
        var mesh_data: MeshData = undefined;
        mesh_data.interlaved = interleaved;
        mesh_data.meshlets = meshlets;

        const index_count = reader.readInt(usize, .little) catch unreachable;
        mesh_data.indices = std.ArrayList(u32).init(load_desc.allocator);
        mesh_data.indices.resize(index_count) catch unreachable;

        if (interleaved) {
            mesh_data.first_index = reader.readInt(u32, .little) catch unreachable;

            const vertex_count = reader.readInt(usize, .little) catch unreachable;
            mesh_data.vertices = std.ArrayList(Vertex).init(load_desc.allocator);
            mesh_data.vertices.resize(vertex_count) catch unreachable;

            mesh_data.first_vertex = reader.readInt(u32, .little) catch unreachable;
        } else {
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
            // TODO
            std.debug.assert(tangents_count == 0);
            // if (tangents_count > 0) {
            //     mesh_data.tangents_stream = std.ArrayList([4]f32).init(load_desc.allocator);
            //     mesh_data.tangents_stream.?.resize(normals_count) catch unreachable;
            // } else {
            //     mesh_data.tangents_stream = null;
            // }
        }

        read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.indices.items), mesh_data.indices.items.len * @sizeOf(u32)) catch unreachable;
        std.debug.assert(read_length == mesh_data.indices.items.len * @sizeOf(u32));

        if (interleaved) {
            read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.vertices.items), mesh_data.vertices.items.len * @sizeOf(Vertex)) catch unreachable;
            std.debug.assert(read_length == mesh_data.vertices.items.len * @sizeOf(Vertex));
        } else {
            read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.positions_stream.items), mesh_data.positions_stream.items.len * @sizeOf([3]f32)) catch unreachable;
            std.debug.assert(read_length == mesh_data.positions_stream.items.len * @sizeOf([3]f32));

            read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.texcoords_stream.items), mesh_data.texcoords_stream.items.len * @sizeOf([2]f32)) catch unreachable;
            std.debug.assert(read_length == mesh_data.texcoords_stream.items.len * @sizeOf([2]f32));

            read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.normals_stream.items), mesh_data.normals_stream.items.len * @sizeOf([3]f32)) catch unreachable;
            std.debug.assert(read_length == mesh_data.normals_stream.items.len * @sizeOf([3]f32));

            // TODO
            // if (tangents_count > 0) {
            //     read_length = reader.readAtLeast(std.mem.sliceAsBytes(mesh_data.tangents_stream.?.items), mesh_data.tangents_stream.?.items.len * @sizeOf([4]f32)) catch unreachable;
            //     std.debug.assert(read_length == mesh_data.tangents_stream.?.items.len * @sizeOf([4]f32));
            // }
        }

        var position_min = if (interleaved) mesh_data.vertices.items[0].position else mesh_data.positions_stream.items[0];
        var position_max = if (interleaved) mesh_data.vertices.items[0].position else mesh_data.positions_stream.items[0];

        if (interleaved) {
            for (1..mesh_data.vertices.items.len) |i| {
                if (mesh_data.vertices.items[i].position[0] < position_min[0]) {
                    position_min[0] = mesh_data.vertices.items[i].position[0];
                }

                if (mesh_data.vertices.items[i].position[1] < position_min[1]) {
                    position_min[1] = mesh_data.vertices.items[i].position[1];
                }

                if (mesh_data.vertices.items[i].position[2] < position_min[2]) {
                    position_min[2] = mesh_data.vertices.items[i].position[2];
                }

                if (mesh_data.vertices.items[i].position[0] > position_max[0]) {
                    position_max[0] = mesh_data.vertices.items[i].position[0];
                }

                if (mesh_data.vertices.items[i].position[1] > position_max[1]) {
                    position_max[1] = mesh_data.vertices.items[i].position[1];
                }

                if (mesh_data.vertices.items[i].position[2] > position_max[2]) {
                    position_max[2] = mesh_data.vertices.items[i].position[2];
                }
            }
        } else {
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