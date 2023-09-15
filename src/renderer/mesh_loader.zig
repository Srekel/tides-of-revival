const std = @import("std");
const zmesh = @import("zmesh");
const zm = @import("zmath");

const rt = @import("renderer_types.zig");

const assert = std.debug.assert;
const zcgltf = zmesh.io.zcgltf;

pub fn parseMeshPrimitive(
    primitive: *zcgltf.Primitive,
    meshes_indices: *std.ArrayList(rt.IndexType),
    meshes_vertices: *std.ArrayList(rt.Vertex),
    arena: std.mem.Allocator,
) !rt.SubMesh {
    const num_vertices: u32 = @intCast(primitive.attributes[0].data.count);
    const num_indices: u32 = @intCast(primitive.indices.?.count);

    var indices = std.ArrayList(rt.IndexType).init(arena);
    var positions = std.ArrayList([3]f32).init(arena);
    var normals = std.ArrayList([3]f32).init(arena);
    var tangents = std.ArrayList([4]f32).init(arena);
    var uvs = std.ArrayList([2]f32).init(arena);
    defer indices.deinit();
    defer positions.deinit();
    defer normals.deinit();
    defer tangents.deinit();
    defer uvs.deinit();

    // Indices.
    {
        try indices.ensureTotalCapacity(indices.items.len + num_indices);

        const accessor = primitive.indices.?;
        const buffer_view = accessor.buffer_view.?;

        assert(accessor.stride == buffer_view.stride or buffer_view.stride == 0);
        assert(accessor.stride * accessor.count == buffer_view.size);
        assert(buffer_view.buffer.data != null);

        const data_addr = @as([*]const u8, @ptrCast(buffer_view.buffer.data)) +
            accessor.offset + buffer_view.offset;

        if (accessor.stride == 1) {
            assert(accessor.component_type == .r_8u);
            const src = @as([*]const u8, @ptrCast(data_addr));
            for (0..num_indices) |i| {
                indices.appendAssumeCapacity(src[i]);
            }
        } else if (accessor.stride == 2) {
            assert(accessor.component_type == .r_16u);
            const src = @as([*]const u16, @ptrCast(@alignCast(data_addr)));
            for (0..num_indices) |i| {
                indices.appendAssumeCapacity(src[i]);
            }
        } else if (accessor.stride == 4) {
            assert(accessor.component_type == .r_32u);
            const src = @as([*]const u32, @ptrCast(@alignCast(data_addr)));
            for (0..num_indices) |i| {
                indices.appendAssumeCapacity(src[i]);
            }
        } else {
            unreachable;
        }
    }

    // Attributes.
    {
        const attributes = primitive.attributes[0..primitive.attributes_count];
        for (attributes) |attrib| {
            const accessor = attrib.data;

            const buffer_view = accessor.buffer_view.?;
            assert(buffer_view.buffer.data != null);

            assert(accessor.stride == buffer_view.stride or buffer_view.stride == 0);
            assert(accessor.stride * accessor.count == buffer_view.size);

            const data_addr = @as([*]const u8, @ptrCast(buffer_view.buffer.data)) +
                accessor.offset + buffer_view.offset;

            if (attrib.type == .position) {
                assert(accessor.type == .vec3);
                assert(accessor.component_type == .r_32f);
                const array: [*]const [3]f32 = @ptrCast(@alignCast(data_addr));
                const slice = array[0..num_vertices];
                try positions.appendSlice(slice);
            } else if (attrib.type == .normal) {
                assert(accessor.type == .vec3);
                assert(accessor.component_type == .r_32f);
                const array: [*]const [3]f32 = @ptrCast(@alignCast(data_addr));
                const slice = array[0..num_vertices];
                try normals.appendSlice(slice);
            } else if (attrib.type == .texcoord) {
                assert(accessor.type == .vec2);
                assert(accessor.component_type == .r_32f);
                const array: [*]const [2]f32 = @ptrCast(@alignCast(data_addr));
                const slice = array[0..num_vertices];
                try uvs.appendSlice(slice);
            } else if (attrib.type == .tangent) {
                assert(accessor.type == .vec4);
                assert(accessor.component_type == .r_32f);
                const array: [*]const [4]f32 = @ptrCast(@alignCast(data_addr));
                const slice = array[0..num_vertices];
                try tangents.appendSlice(slice);
            }
        }
    }

    // TODO(gmodarelli): glTF 2.0 files can specify a min/max pair for their attributes, so we could check there first
    // instead of calculating the bounding box
    // Calculate bounding box
    var min = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var max = [3]f32{ std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32) };

    for (positions.items) |position| {
        min[0] = @min(min[0], position[0]);
        min[1] = @min(min[1], position[1]);
        min[2] = @min(min[2], position[2]);

        max[0] = @max(max[0], position[0]);
        max[1] = @max(max[1], position[1]);
        max[2] = @max(max[2], position[2]);
    }

    var sub_mesh = rt.SubMesh{
        .lod_count = 1,
        .lods = undefined,
        .bounding_box = .{
            .min = min,
            .max = max,
        },
    };

    sub_mesh.lods[0] = .{
        .index_offset = @intCast(meshes_indices.items.len),
        .index_count = @intCast(indices.items.len),
        .vertex_offset = @intCast(meshes_vertices.items.len),
        .vertex_count = @intCast(positions.items.len),
    };

    try meshes_vertices.ensureTotalCapacity(meshes_vertices.items.len + positions.items.len);
    const has_tangents = if (tangents.items.len == positions.items.len) true else false;
    for (positions.items, 0..) |_, index| {
        meshes_vertices.appendAssumeCapacity(.{
            .position = positions.items[index],
            .normal = normals.items[index],
            .uv = uvs.items[index],
            .tangent = if (has_tangents) tangents.items[index] else [4]f32{ 0.0, 0.0, 1.0, 0.0 },
            .color = [3]f32{ 1.0, 1.0, 1.0 },
        });
    }

    meshes_indices.appendSlice(indices.items) catch unreachable;
    return sub_mesh;
}

pub fn loadObjMeshFromFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    meshes_indices: *std.ArrayList(rt.IndexType),
    meshes_vertices: *std.ArrayList(rt.Vertex),
) !rt.Mesh {
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

    var indices = std.ArrayList(rt.IndexType).init(arena);
    var vertices = std.ArrayList(rt.Vertex).init(arena);

    var positions = std.ArrayList([3]f32).init(arena);
    var colors = std.ArrayList([3]f32).init(arena);
    var normals = std.ArrayList([3]f32).init(arena);
    var uvs = std.ArrayList([2]f32).init(arena);

    var buf: [1024]u8 = undefined;
    var inside_object: bool = false;
    var previous_obj_positions_count: u32 = 0;
    var previous_obj_uvs_count: u32 = 0;
    var previous_obj_normals_count: u32 = 0;

    var mesh = rt.Mesh{
        .vertex_buffer = undefined,
        .index_buffer = undefined,
        .sub_mesh_count = 1,
        .sub_meshes = undefined,
        .bounding_box = undefined,
    };

    var sub_mesh = &mesh.sub_meshes[0];
    sub_mesh.lod_count = 0;
    sub_mesh.lods = undefined;
    sub_mesh.bounding_box = undefined;

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
                    sub_mesh,
                );

                indices.clearRetainingCapacity();
                vertices.clearRetainingCapacity();

                previous_obj_positions_count += @intCast(positions.items.len);
                previous_obj_uvs_count += @intCast(uvs.items.len);
                previous_obj_normals_count += @intCast(normals.items.len);

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

                previous_obj_positions_count += @intCast(positions.items.len);
                previous_obj_uvs_count += @intCast(uvs.items.len);
                previous_obj_normals_count += @intCast(normals.items.len);

                positions.clearRetainingCapacity();
                colors.clearRetainingCapacity();
                normals.clearRetainingCapacity();
                uvs.clearRetainingCapacity();
            }

            var position: [3]f32 = undefined;
            position[0] = try std.fmt.parseFloat(f32, it.next().?);
            position[1] = try std.fmt.parseFloat(f32, it.next().?);
            position[2] = try std.fmt.parseFloat(f32, it.next().?) * -1.0; // NOTE(gmodarelli): Convert to Left Hand coordinate system for DirectX
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
            normal[2] = try std.fmt.parseFloat(f32, it.next().?) * -1.0; // NOTE(gmodarelli): Convert to Left Hand coordinate system for DirectX
            try normals.append(normal);
        } else if (std.mem.eql(u8, first, "vt")) {
            var uv: [2]f32 = undefined;
            uv[0] = try std.fmt.parseFloat(f32, it.next().?);
            uv[1] = try std.fmt.parseFloat(f32, it.next().?);
            // NOTE(gmodarelli): Flip the UV's for DirectX
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
                var position_index = try std.fmt.parseInt(rt.IndexType, triangles_iterator.next().?, 10);
                position_index -= previous_obj_positions_count;
                position_index -= 1;
                var uv_index = try std.fmt.parseInt(rt.IndexType, triangles_iterator.next().?, 10);
                uv_index -= previous_obj_uvs_count;
                uv_index -= 1;
                var normal_index = try std.fmt.parseInt(rt.IndexType, triangles_iterator.next().?, 10);
                normal_index -= previous_obj_normals_count;
                normal_index -= 1;

                const unique_vertex_index: u32 = @intCast(vertices.items.len);
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
            sub_mesh,
        );

        inside_object = false;
    }

    // Update mesh bounding box (encapsulates all sub-meshes bounding boxes)
    var min = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var max = [3]f32{ std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32) };

    for (0..mesh.sub_mesh_count) |i| {
        min[0] = @min(min[0], mesh.sub_meshes[i].bounding_box.min[0]);
        min[1] = @min(min[1], mesh.sub_meshes[i].bounding_box.min[1]);
        min[2] = @min(min[2], mesh.sub_meshes[i].bounding_box.min[2]);

        max[0] = @max(max[0], mesh.sub_meshes[i].bounding_box.max[0]);
        max[1] = @max(max[1], mesh.sub_meshes[i].bounding_box.max[1]);
        max[2] = @max(max[2], mesh.sub_meshes[i].bounding_box.max[2]);
    }

    mesh.bounding_box = .{
        .min = min,
        .max = max,
    };

    return mesh;
}

fn storeMeshLod(
    arena: std.mem.Allocator,
    indices: *std.ArrayList(rt.IndexType),
    vertices: *std.ArrayList(rt.Vertex),
    meshes_indices: *std.ArrayList(rt.IndexType),
    meshes_vertices: *std.ArrayList(rt.Vertex),
    sub_mesh: *rt.SubMesh,
) !void {
    // Calculate tangents for every vertex
    {
        var tangents = std.ArrayList([3]f32).init(arena);
        try tangents.resize(vertices.items.len);
        var bitangents = std.ArrayList([3]f32).init(arena);
        try bitangents.resize(vertices.items.len);

        for (0..tangents.items.len) |i| {
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

        for (0..vertices.items.len) |vi| {
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
        rt.Vertex,
        vertices.items,
    );

    var optimized_vertices = std.ArrayList(rt.Vertex).init(arena);
    optimized_vertices.resize(num_unique_vertices) catch unreachable;

    zmesh.opt.remapVertexBuffer(
        rt.Vertex,
        optimized_vertices.items,
        vertices.items,
        remapped_indices.items,
    );

    sub_mesh.lods[sub_mesh.lod_count] = .{
        .index_offset = @intCast(meshes_indices.items.len),
        .index_count = @intCast(remapped_indices.items.len),
        .vertex_offset = @intCast(meshes_vertices.items.len),
        .vertex_count = @intCast(optimized_vertices.items.len),
    };

    sub_mesh.lod_count += 1;

    // NOTE(gmodarelli): Flipping the triangles winding order so they are clock-wise
    var flipped_indices = std.ArrayList(rt.IndexType).init(arena);
    try flipped_indices.ensureTotalCapacity(remapped_indices.items.len);
    {
        var i: u32 = 0;
        while (i < remapped_indices.items.len) : (i += 3) {
            flipped_indices.appendAssumeCapacity(remapped_indices.items[i + 0]);
            flipped_indices.appendAssumeCapacity(remapped_indices.items[i + 2]);
            flipped_indices.appendAssumeCapacity(remapped_indices.items[i + 1]);
        }
    }

    // Calculate bounding box
    var min = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var max = [3]f32{ std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32) };

    for (optimized_vertices.items) |vertex| {
        min[0] = @min(min[0], vertex.position[0]);
        min[1] = @min(min[1], vertex.position[1]);
        min[2] = @min(min[2], vertex.position[2]);

        max[0] = @max(max[0], vertex.position[0]);
        max[1] = @max(max[1], vertex.position[1]);
        max[2] = @max(max[2], vertex.position[2]);
    }

    sub_mesh.bounding_box = .{
        .min = min,
        .max = max,
    };

    meshes_indices.appendSlice(flipped_indices.items) catch unreachable;
    meshes_vertices.appendSlice(optimized_vertices.items) catch unreachable;
}
