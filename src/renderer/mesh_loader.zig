const std = @import("std");
const assert = std.debug.assert;
const zmesh = @import("zmesh");
const zm = @import("zmath");

const IndexType = @import("renderer_types.zig").IndexType;
const Vertex = @import("renderer_types.zig").Vertex;
const Mesh = @import("renderer_types.zig").Mesh;

pub fn loadObjMeshFromFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) !Mesh {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.warn("Unable to open file: {s}", .{@errorName(err)});
        return err;
    };
    defer file.close();

    var buffer_reader = std.io.bufferedReader(file.reader());
    var in_stream = buffer_reader.reader();

    var indices = std.ArrayList(IndexType).init(arena);
    var vertices = std.ArrayList(Vertex).init(arena);

    var positions = std.ArrayList([3]f32).init(arena);
    var colors = std.ArrayList([3]f32).init(arena);
    var normals = std.ArrayList([3]f32).init(arena);
    var uvs = std.ArrayList([2]f32).init(arena);

    var buf: [1024]u8 = undefined;
    var inside_object: bool = false;
    var previous_obj_positions_count: u32 = 0;
    var previous_obj_uvs_count: u32 = 0;
    var previous_obj_normals_count: u32 = 0;

    var mesh = Mesh{
        .num_lods = 0,
        .lods = undefined,
    };

    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = std.mem.split(u8, line, " ");

        var first = it.first();
        if (std.mem.eql(u8, first, "o")) {
            if (inside_object) {
                try storeMeshLod(
                    arena,
                    &indices,
                    &vertices,
                    meshes_indices,
                    meshes_vertices,
                    &mesh,
                );

                indices.clearRetainingCapacity();
                vertices.clearRetainingCapacity();

                previous_obj_positions_count += @intCast(u32, positions.items.len);
                previous_obj_uvs_count += @intCast(u32, uvs.items.len);
                previous_obj_normals_count += @intCast(u32, normals.items.len);

                positions.clearRetainingCapacity();
                colors.clearRetainingCapacity();
                normals.clearRetainingCapacity();
                uvs.clearRetainingCapacity();

                inside_object = false;
            }
        } else if (std.mem.eql(u8, first, "v")) {
            if (!inside_object) {
                inside_object = true;
                indices.clearRetainingCapacity();
                vertices.clearRetainingCapacity();

                previous_obj_positions_count += @intCast(u32, positions.items.len);
                previous_obj_uvs_count += @intCast(u32, uvs.items.len);
                previous_obj_normals_count += @intCast(u32, normals.items.len);

                positions.clearRetainingCapacity();
                colors.clearRetainingCapacity();
                normals.clearRetainingCapacity();
                uvs.clearRetainingCapacity();
            }

            var position: [3]f32 = undefined;
            position[0] = try std.fmt.parseFloat(f32, it.next().?);
            position[1] = try std.fmt.parseFloat(f32, it.next().?);
            position[2] = try std.fmt.parseFloat(f32, it.next().?);
            try positions.append(position);
            var color: [3]f32 = undefined;
            color[0] = try std.fmt.parseFloat(f32, it.next().?);
            color[1] = try std.fmt.parseFloat(f32, it.next().?);
            color[2] = try std.fmt.parseFloat(f32, it.next().?);
            try colors.append(color);
        } else if (std.mem.eql(u8, first, "vn")) {
            var normal: [3]f32 = undefined;
            normal[0] = try std.fmt.parseFloat(f32, it.next().?);
            normal[1] = try std.fmt.parseFloat(f32, it.next().?);
            normal[2] = try std.fmt.parseFloat(f32, it.next().?);
            try normals.append(normal);
        } else if (std.mem.eql(u8, first, "vt")) {
            var uv: [2]f32 = undefined;
            uv[0] = try std.fmt.parseFloat(f32, it.next().?);
            uv[1] = try std.fmt.parseFloat(f32, it.next().?);
            // NOTE(gmodarelli): Figure out if we always need to do this
            uv[1] = 1.0 - uv[1];
            try uvs.append(uv);
        } else if (std.mem.eql(u8, first, "f")) {
            var triangle_index: u32 = 0;
            while (triangle_index < 3) : (triangle_index += 1) {
                var vertex_components = it.next().?;
                var triangles_iterator = std.mem.split(u8, vertex_components, "/");

                // NOTE(gmodarelli): We're assuming Positions, UV's and Normals are exported with the OBJ file.
                // TODO(gmodarelli): Parse the OBJ in 2 passes. First collect all attributes and then generate
                // vertices and indices. Positions and UV's must be present, Normals can be calculated.
                var position_index = try std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10);
                position_index -= previous_obj_positions_count;
                position_index -= 1;
                var uv_index = try std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10);
                uv_index -= previous_obj_uvs_count;
                uv_index -= 1;
                var normal_index = try std.fmt.parseInt(IndexType, triangles_iterator.next().?, 10);
                normal_index -= previous_obj_normals_count;
                normal_index -= 1;

                const unique_vertex_index = @intCast(u32, vertices.items.len);
                try indices.append(unique_vertex_index);
                try vertices.append(.{
                    .position = positions.items[position_index],
                    .normal = normals.items[normal_index],
                    .uv = uvs.items[uv_index],
                    .tangent = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
                    .color = colors.items[position_index],
                });
            }
        }
    }

    if (inside_object) {
        try storeMeshLod(
            arena,
            &indices,
            &vertices,
            meshes_indices,
            meshes_vertices,
            &mesh,
        );

        inside_object = false;
    }

    return mesh;
}

fn storeMeshLod(
    arena: std.mem.Allocator,
    indices: *std.ArrayList(IndexType),
    vertices: *std.ArrayList(Vertex),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
    mesh: *Mesh,
) !void {
    // Calculate tangents for every vertex
    {
        var tangents = std.ArrayList([3]f32).init(arena);
        try tangents.resize(vertices.items.len);
        var bitangents = std.ArrayList([3]f32).init(arena);
        try bitangents.resize(vertices.items.len);

        var i: u32 = 0;
        while (i < tangents.items.len) : (i += 1) {
            var t = &tangents.items[i];
            t[0] = 0.0;
            t[1] = 0.0;
            t[2] = 0.0;

            var b = &bitangents.items[i];
            b[0] = 0.0;
            b[1] = 0.0;
            b[2] = 0.0;
        }

        var index: u32 = 0;
        while (index < indices.items.len) : (index += 3) {
            const vertex_0 = vertices.items[indices.items[index + 0]];
            const vertex_1 = vertices.items[indices.items[index + 1]];
            const vertex_2 = vertices.items[indices.items[index + 2]];

            var p0 = zm.loadArr3(vertex_0.position);
            var p1 = zm.loadArr3(vertex_1.position);
            var p2 = zm.loadArr3(vertex_2.position);

            var e1 = p1 - p0;
            var e2 = p2 - p0;
            const x1 = vertex_1.uv[0] - vertex_0.uv[0];
            const x2 = vertex_2.uv[0] - vertex_0.uv[0];
            const y1 = vertex_1.uv[1] - vertex_0.uv[1];
            const y2 = vertex_2.uv[1] - vertex_0.uv[1];
            const vec_x1 = zm.Vec{ x1, x1, x1, 0.0 };
            const vec_x2 = zm.Vec{ x2, x2, x2, 0.0 };
            const vec_y1 = zm.Vec{ y1, y1, y1, 0.0 };
            const vec_y2 = zm.Vec{ y2, y2, y2, 0.0 };

            const r = 1.0 / (x1 * y2 - x2 * y1);
            const vec_r = zm.Vec{ r, r, r, 0.0 };
            var tangent = [3]f32{ 0.0, 0.0, 0.0 };
            zm.storeArr3(&tangent, (e1 * vec_y2 - e2 * vec_y1) * vec_r);
            var bitangent = [3]f32{ 0.0, 0.0, 0.0 };
            zm.storeArr3(&bitangent, (e2 * vec_x1 - e1 * vec_x2) * vec_r);

            tangents.items[indices.items[index + 0]][0] += tangent[0];
            tangents.items[indices.items[index + 0]][1] += tangent[1];
            tangents.items[indices.items[index + 0]][2] += tangent[2];

            tangents.items[indices.items[index + 1]][0] += tangent[0];
            tangents.items[indices.items[index + 1]][1] += tangent[1];
            tangents.items[indices.items[index + 1]][2] += tangent[2];

            tangents.items[indices.items[index + 2]][0] += tangent[0];
            tangents.items[indices.items[index + 2]][1] += tangent[1];
            tangents.items[indices.items[index + 2]][2] += tangent[2];

            bitangents.items[indices.items[index + 0]][0] += bitangent[0];
            bitangents.items[indices.items[index + 0]][1] += bitangent[1];
            bitangents.items[indices.items[index + 0]][2] += bitangent[2];

            bitangents.items[indices.items[index + 1]][0] += bitangent[0];
            bitangents.items[indices.items[index + 1]][1] += bitangent[1];
            bitangents.items[indices.items[index + 1]][2] += bitangent[2];

            bitangents.items[indices.items[index + 2]][0] += bitangent[0];
            bitangents.items[indices.items[index + 2]][1] += bitangent[1];
            bitangents.items[indices.items[index + 2]][2] += bitangent[2];
        }

        var vi: u32 = 0;
        while (vi < vertices.items.len) : (vi += 1) {
            var vertex = &vertices.items[vi];

            const tangent = zm.loadArr3(tangents.items[vi]);
            const binormal = zm.loadArr3(tangents.items[vi]);
            const normal = zm.normalize3(zm.loadArr3(vertex.normal));

            const reject = tangent - zm.dot3(tangent, normal) * normal;
            var new_tangent = [3]f32{ 0.0, 0.0, 0.0 };
            zm.storeArr3(&new_tangent, zm.normalize3(reject));
            var result = [3]f32{ 0.0, 0.0, 0.0 };
            zm.storeArr3(&result, zm.dot3(zm.cross3(tangent, binormal), normal));
            var handedness: f32 = if (result[0] > 0.0) 1.0 else -1.0;

            vertex.tangent[0] = new_tangent[0];
            vertex.tangent[1] = new_tangent[1];
            vertex.tangent[2] = new_tangent[2];
            vertex.tangent[3] = handedness;
        }
    }

    var remapped_indices = std.ArrayList(u32).init(arena);
    remapped_indices.resize(indices.items.len) catch unreachable;

    const num_unique_vertices = zmesh.opt.generateVertexRemap(
        remapped_indices.items,
        indices.items,
        Vertex,
        vertices.items,
    );

    var optimized_vertices = std.ArrayList(Vertex).init(arena);
    optimized_vertices.resize(num_unique_vertices) catch unreachable;

    zmesh.opt.remapVertexBuffer(
        Vertex,
        optimized_vertices.items,
        vertices.items,
        remapped_indices.items,
    );

    mesh.lods[mesh.num_lods] = .{
        .index_offset = @intCast(u32, meshes_indices.items.len),
        .index_count = @intCast(u32, remapped_indices.items.len),
        .vertex_offset = @intCast(u32, meshes_vertices.items.len),
        .vertex_count = @intCast(u32, optimized_vertices.items.len),
    };

    mesh.num_lods += 1;

    meshes_indices.appendSlice(remapped_indices.items) catch unreachable;
    meshes_vertices.appendSlice(optimized_vertices.items) catch unreachable;
}
