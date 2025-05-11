const std = @import("std");
// const tides_format = @import("tides_format.zig");
const json5 = @import("json5.zig");

const kind_start = hash("start");
const kind_beaches = hash("beaches");
const kind_cities = hash("cities");
const kind_contours = hash("contours");
const kind_fbm = hash("fbm");
const kind_gradient = hash("gradient");
const kind_landscape_from_image = hash("landscape_from_image");
const kind_points_grid = hash("points_grid");
const kind_poisson = hash("poisson");
const kind_remap = hash("remap");
const kind_square = hash("square");
const kind_terrace = hash("terrace");
const kind_voronoi = hash("voronoi");
const kind_water = hash("water");
const kind_write_heightmap = hash("write_heightmap");
const kind_write_trees = hash("write_trees");

const kind_FbmSettings = hash("FbmSettings");
const kind_ImageF32 = hash("ImageF32");
const kind_PatchDataPts2d = hash("PatchDataPts2d");
const kind_PointList2D = hash("PointList2D");
const kind_PointList3D = hash("PointList3D");
const kind_Size2D = hash("Size2D");
const kind_Voronoi = hash("Voronoi");
const kind_VoronoiSettings = hash("VoronoiSettings");
const kind_WorldSettings = hash("WorldSettings");

// UTIL
fn loadFile(path: []const u8, buf: []u8) []const u8 {
    var buf2: [256]u8 = undefined;
    const path2 = std.fs.cwd().realpath(".", &buf2) catch unreachable;
    std.log.info("LOL {s}", .{path2});
    std.log.info("LOL {s}", .{path});
    const data = std.fs.cwd().readFile(path, buf) catch unreachable;
    return data;
}

fn writeFile(data: anytype, name: []const u8) void {
    var buf: [256]u8 = undefined;
    const filepath = std.fmt.bufPrintZ(&buf, "{s}.zig", .{name}) catch unreachable;
    const file = std.fs.cwd().createFile(
        filepath,
        .{ .read = true },
    ) catch unreachable;
    defer file.close();

    const bytes_written = file.writeAll(data) catch unreachable;
    _ = bytes_written; // autofix
}

fn hash(str: []const u8) u64 {
    return std.hash.Wyhash.hash(0, str);
}

fn print(buf: []u8, comptime fmt: []const u8, args: anytype) []u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch unreachable;
}

fn write(writer: anytype, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024 * 4]u8 = undefined;
    const str = print(&buf, fmt, args);
    writer.writeAll(str) catch unreachable;
}

fn writeLine(writer: anytype, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024 * 4]u8 = undefined;
    const str = print(&buf, fmt, args);
    writer.writeAll(str) catch unreachable;
    writer.writeAll("\n") catch unreachable;
}

fn writePreview(writer: anytype, image_name: []const u8, node_name: []const u8) void {
    writeLine(writer, "    ", .{});
    writeLine(writer, "    types.saveImageF32({s}, \"{s}\", false);", .{ image_name, node_name });

    writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ image_name, node_name });
    writeLine(writer, "    const preview_grid_key = \"{s}.image\";", .{node_name});
    writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_grid_key, .{{ .data = preview_image_{s}.asBytes() }});", .{node_name});
}

// GEN
pub fn generateFile(simgraph_path: []const u8, zig_path: []const u8) void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var out = std.ArrayList(u8).init(gpa);
    defer out.deinit();
    const writer = out.writer();
    // var buf: [1024 * 4]u8 = undefined;
    // _ = buf; // autofix

    var json_string = std.ArrayList(u8).init(gpa);
    defer json_string.deinit();

    var parser = json5.Parser.init(gpa, false);
    defer parser.deinit();

    var json_buf: [1024 * 32]u8 = undefined;
    const graph_json = loadFile(simgraph_path, &json_buf);
    std.debug.assert(json_buf.len > graph_json.len);

    var tree = parser.parse(graph_json) catch unreachable;
    defer tree.deinit();

    const j_root = tree.root;
    const j_nodes = j_root.Object.get("nodes").?;
    const j_vars = j_root.Object.get("variables").?;
    const j_settings = j_root.Object.get("settings").?;

    // imports
    writeLine(writer, "const  std = @import(\"std\");", .{});
    writeLine(writer, "const graph = @import(\"graph.zig\");", .{});
    writeLine(writer, "const Context = graph.Context;", .{});
    writeLine(writer, "const cpp_nodes = @import(\"../sim_cpp/cpp_nodes.zig\");", .{});
    writeLine(writer, "const nodes = @import(\"nodes/nodes.zig\");", .{});
    writeLine(writer, "const types = @import(\"types.zig\");", .{});
    writeLine(writer, "const compute = @import(\"compute.zig\");", .{});
    writeLine(writer, "", .{});
    writeLine(writer, "const c_cpp_nodes = @cImport({{", .{});
    writeLine(writer, "    @cInclude(\"world_generator.h\");", .{});
    writeLine(writer, "}});", .{});

    // constants
    writeLine(writer, "", .{});
    writeLine(writer, "// ============ CONSTANTS ============", .{});
    writeLine(writer, "const DRY_RUN = {};", .{j_settings.Object.get("dry_run").?.Bool});
    writeLine(writer, "const kilometers = if (DRY_RUN) 2 else 16;", .{});
    writeLine(writer, "const preview_size = 512;", .{});
    writeLine(writer, "const preview_size_big = preview_size * 2;", .{});
    writeLine(writer, "pub const node_count = {any};", .{j_nodes.Array.items.len});

    // vars
    writeLine(writer, "", .{});
    writeLine(writer, "// ============ VARS ============", .{});
    for (j_vars.Array.items) |j_var| {
        const name = j_var.Object.get("name").?.String;
        const kind = j_var.Object.get("kind").?.String;
        const is_const = blk: {
            if (j_var.Object.get("is_const")) |is_const| {
                break :blk is_const.Bool;
            }
            break :blk false;
        };

        const kind_type: []const u8 = switch (hash(kind)) {
            kind_FbmSettings => "nodes.fbm.FbmSettings",
            kind_ImageF32 => "types.ImageF32",
            kind_PatchDataPts2d => "types.PatchDataPts2d",
            kind_PointList2D => "std.ArrayList(types.Vec2)",
            kind_PointList3D => "std.ArrayList(types.Vec3)",
            kind_Size2D => "types.Size2D",
            kind_Voronoi => "*nodes.voronoi.Voronoi",
            kind_VoronoiSettings => "nodes.voronoi.VoronoiSettings",
            kind_WorldSettings => "types.WorldSettings",
            // kind_WorldSettings => "types.WorldSettings",
            // kind_WorldSettings => "types.WorldSettings",
            // kind_WorldSettings => "types.WorldSettings",
            // kind_WorldSettings => "types.WorldSettings",
            // kind_WorldSettings => "types.WorldSettings",
            else => unreachable,
        };

        write(writer, "{s} {s} : {s} = ", .{ if (is_const) "const" else "var", name, kind_type });

        switch (hash(kind)) {
            kind_FbmSettings => {
                const seed = j_var.Object.get("seed").?.Integer;
                const frequency = j_var.Object.get("frequency").?.Float;
                const octaves = j_var.Object.get("octaves").?.Integer;
                const rect = j_var.Object.get("rect").?.String;
                const scale = j_var.Object.get("scale").?.Float;
                writeLine(writer,
                    \\ nodes.fbm.FbmSettings{{
                    \\    .seed = {any},
                    \\    .frequency = {d},
                    \\    .octaves = {any},
                    \\    .rect = types.Rect.createOriginSquare({s}.width),
                    \\    .scale = {d},
                    \\}};
                , .{ seed, frequency, octaves, rect, scale });
            },
            kind_ImageF32 => {
                const size = j_var.Object.get("size").?.String;
                writeLine(writer, "types.ImageF32.square({s}.width);", .{size});
            },
            kind_Size2D => {
                const j_width = j_var.Object.get("width").?;
                const j_height = j_var.Object.get("height").?;
                switch (j_width) {
                    .Integer => {
                        writeLine(writer, ".{{ .width = {any} * 1024, .height = {any} * 1024 }};", .{ j_width.Integer, j_height.Integer });
                    },
                    .String => {
                        writeLine(writer, ".{{ .width = {str} * 1024, .height = {str} * 1024 }};", .{ j_width.String, j_height.String });
                    },
                    else => unreachable,
                }
            },
            kind_VoronoiSettings => {
                const seed = j_var.Object.get("seed").?.Integer;
                const size = j_var.Object.get("size").?.String;
                const radius = j_var.Object.get("radius").?.Integer;
                const num_relaxations = j_var.Object.get("num_relaxations").?.Integer;
                writeLine(writer,
                    \\ {s}{{
                    \\    .seed = {any},
                    \\    .size = {s}.width,
                    \\    .radius = {any},
                    \\    .num_relaxations = {any},
                    \\}};
                , .{ kind_type, seed, size, radius, num_relaxations });
            },
            kind_WorldSettings => {
                const size = j_var.Object.get("size").?.String;
                writeLine(writer, ".{{ .size = {str} }};", .{size});
            },
            else => {
                writeLine(writer, "undefined;", .{});
            },
        }
    }

    // nodes

    // nodes: preview images
    writeLine(writer, "", .{});
    writeLine(writer, "// ============ PREVIEW IMAGES ============", .{});
    for (j_nodes.Array.items) |j_node| {
        const name = j_node.Object.get("name").?.String;
        writeLine(writer, "var preview_image_{s} = types.ImageRGBA.square(preview_size);", .{name});
    }

    // nodes: functions
    writeLine(writer, "", .{});
    writeLine(writer, "// ============ NODES ============", .{});
    for (j_nodes.Array.items) |j_node| {
        const name = j_node.Object.get("name").?.String;
        const kind = j_node.Object.get("kind").?.String;

        // writeLine(writer, "// node kind: {s}", .{kind});
        writeLine(writer, "pub fn {s}(ctx: *Context) void {{", .{name});
        const node_start_index = out.items.len;
        // var needs_ctx = true;

        switch (hash(kind)) {
            kind_start => {
                writeLine(writer, "    // Initialize vars", .{});
                for (j_vars.Array.items) |j_var| {
                    const var_name = j_var.Object.get("name").?.String;
                    const var_kind = j_var.Object.get("kind").?.String;

                    switch (hash(var_kind)) {
                        kind_ImageF32 => {
                            const size = j_var.Object.get("size").?.String;
                            writeLine(writer, "    {s}.pixels = std.heap.c_allocator.alloc(f32, {s}.width * {s}.height) catch unreachable;", .{ var_name, size, size });
                        },
                        kind_PointList2D => {
                            writeLine(writer, "    {s} = @TypeOf({s}).init(std.heap.c_allocator);", .{ var_name, var_name });
                        },
                        kind_PointList3D => {
                            const capacity = j_var.Object.get("capacity").?.Integer;
                            writeLine(writer, "    {s} = @TypeOf({s}).initCapacity(std.heap.c_allocator, {d}) catch unreachable;", .{ var_name, var_name, capacity });
                        },
                        kind_Voronoi => {
                            writeLine(writer, "    {s} = std.heap.c_allocator.create(nodes.voronoi.Voronoi) catch unreachable;", .{var_name});
                        },
                        else => {},
                    }
                }

                writeLine(writer, "", .{});
                writeLine(writer, "    // Initialize preview images", .{});
                for (j_nodes.Array.items) |j_node2| {
                    const name2 = j_node2.Object.get("name").?.String;
                    writeLine(writer, "    preview_image_{s}.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;", .{name2});
                }
            },
            kind_beaches => {
                const voronoi = j_node.Object.get("voronoi").?.String;
                const downsamples = j_node.Object.get("downsamples").?.Integer;

                writeLine(writer, "    var c_voronoi = c_cpp_nodes.Voronoi{{", .{});
                writeLine(writer, "        .voronoi_grid = {s}.diagram,", .{voronoi});
                writeLine(writer, "        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    const downsamples = {any};", .{downsamples});
                writeLine(writer, "    const downsample_divistor = std.math.pow(u32, 2, downsamples);", .{});
                writeLine(writer, "    const preview_grid = cpp_nodes.generate_landscape_preview(", .{});
                writeLine(writer, "        &c_voronoi,", .{});
                writeLine(writer, "        preview_size / downsample_divistor,", .{});
                writeLine(writer, "        preview_size / downsample_divistor,", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    );", .{});
                writeLine(writer, "    scratch_image.size.width = preview_size / downsample_divistor;", .{});
                writeLine(writer, "    scratch_image.size.height = preview_size / downsample_divistor;", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    nodes.experiments.voronoi_to_water(preview_grid[0 .. preview_size * preview_size], &scratch_image);", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "", .{});

                writeLine(writer, "    types.saveImageF32(scratch_image, \"water\", false);", .{});
                writeLine(writer, "    const upsamples = std.math.log2(world_size.width / scratch_image.size.width);", .{});
                writeLine(writer, "    for (0..upsamples) |i| {{", .{});
                writeLine(writer, "        _ = i; // autofix", .{});
                writeLine(writer, "        scratch_image2.size.width = scratch_image.size.width * 2;", .{});
                writeLine(writer, "        scratch_image2.size.height = scratch_image.size.height * 2;", .{});
                writeLine(writer, "        scratch_image2.zeroClear();", .{});
                writeLine(writer, "        compute.upsample_blur(&scratch_image, &scratch_image2);", .{});
                writeLine(writer, "        scratch_image.size.width = scratch_image2.size.width;", .{});
                writeLine(writer, "        scratch_image.size.height = scratch_image2.size.height;", .{});
                writeLine(writer, "        scratch_image.swap(&scratch_image2);", .{});
                writeLine(writer, "        types.saveImageF32(scratch_image, \"upblur\", false);", .{});
                writeLine(writer, "    }}", .{});

                writeLine(writer, "    water_image.copy(scratch_image);", .{});
                writeLine(writer, "    types.saveImageF32(scratch_image, \"water\", false);", .{});

                writePreview(writer, "scratch_image", name);
            },
            kind_cities => {
                const gradient = j_node.Object.get("gradient").?.String;
                const heightmap = j_node.Object.get("heightmap").?.String;
                writeLine(writer, "    if (!DRY_RUN) {{", .{});
                writeLine(writer, "        nodes.experiments.cities(world_settings, {s}, {s}, &cities);", .{ heightmap, gradient });
                writeLine(writer, "    }}", .{});
            },
            kind_contours => {
                const voronoi = j_node.Object.get("voronoi").?.String;
                writeLine(writer, "    nodes.voronoi.contours({s});", .{voronoi});
            },
            kind_fbm => {
                const output = j_node.Object.get("output").?.String;

                writeLine(writer, "    const generate_fbm_settings = compute.GenerateFBMSettings{{", .{});
                writeLine(writer, "        .width = @intCast({s}.size.width),", .{output});
                writeLine(writer, "        .height = @intCast({s}.size.height),", .{output});
                writeLine(writer, "        .seed = fbm_settings.seed,", .{});
                writeLine(writer, "        .frequency = fbm_settings.frequency,", .{});
                writeLine(writer, "        .octaves = fbm_settings.octaves,", .{});
                writeLine(writer, "        .scale = fbm_settings.scale,", .{});
                writeLine(writer, "        ._padding = .{{ 0, 0 }},", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "    ", .{});
                writeLine(writer, "    compute.fbm(&{s}, generate_fbm_settings);", .{output});
                writeLine(writer, "    compute.min(&{s}, &scratch_image);", .{output});
                writeLine(writer, "    compute.max(&{s}, &scratch_image);", .{output});
                writeLine(writer, "    nodes.math.rerangify(&{s});", .{output});
                writeLine(writer, "    ", .{});
                writeLine(writer, "    compute.remap(&{s}, &scratch_image, 0, 1);", .{output});
                writeLine(writer, "    ", .{});
                // writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ output, name });
                // writeLine(writer, "    const preview_grid_key = \"{s}.image\";", .{name});
                // writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_grid_key, .{{ .data = preview_image_{s}.asBytes() }});", .{name});
                writePreview(writer, output, name);
            },
            kind_gradient => {
                const input = j_node.Object.get("input").?.String;
                const output = j_node.Object.get("output").?.String;
                writeLine(writer, "    nodes.gradient.gradient({s}, 1 / world_settings.terrain_height_max, &{s});", .{ input, output });
                // writeLine(writer, "    ", .{});
                // writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ output, name });
                // writeLine(writer, "    const preview_grid_key = \"{s}.image\";", .{name});
                // writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_grid_key, .{{ .data = preview_image_{s}.asBytes() }});", .{name});
                writePreview(writer, output, name);
            },
            kind_landscape_from_image => {
                const voronoi = j_node.Object.get("voronoi").?.String;
                const image = j_node.Object.get("image").?.String;
                writeLine(writer, "    var c_voronoi = c_cpp_nodes.Voronoi{{", .{});
                writeLine(writer, "        .voronoi_grid = {s}.diagram,", .{voronoi});
                writeLine(writer, "        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "    cpp_nodes.generate_landscape_from_image(&c_voronoi, \"{s}\");", .{image});
                // preview
                writeLine(writer, "", .{});
                writeLine(writer, "    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);", .{});
                writeLine(writer, "    const preview_grid_key = \"{s}.image\";", .{name});
                writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_grid_key, .{{ .data = preview_grid[0 .. preview_size * preview_size] }});", .{});
            },
            kind_points_grid => {
                const points = j_node.Object.get("points").?.String;
                const cell_size = j_node.Object.get("cell_size").?.Integer;
                const score_min = j_node.Object.get("score_min").?.Float;
                const image = j_node.Object.get("image").?.String;
                writeLine(writer, "   {s} = types.PatchDataPts2d.create(1, {s}.size.width / 128, 100, std.heap.c_allocator);", .{ points, image });
                writeLine(writer, "   nodes.experiments.points_distribution_grid({s}, {d}, .{{ .cell_size = {d}, .size = {s}.size }}, &{s});", .{ image, score_min, cell_size, image, points });
            },
            kind_poisson => {
                const points = j_node.Object.get("points").?.String;
                writeLine(writer, "    nodes.poisson.generate_points(world_size, 50, 1, &{s});", .{points});
            },
            kind_remap => {
                const input = j_node.Object.get("input").?.String;
                const output = j_node.Object.get("output").?.String;

                writeLine(writer, "    {s}.copy({s});", .{ output, input });
                writeLine(writer, "    {s}.remap(0, world_settings.terrain_height_max);", .{output});
                // writeLine(writer, "    ", .{});
                // writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ output, name });
                // writeLine(writer, "    const preview_key = \"{s}.image\";", .{name});
                // writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_key, .{{ .data = preview_image_{s}.asBytes() }});", .{name});
                writePreview(writer, output, name);
            },
            kind_square => {
                const input = j_node.Object.get("input").?.String;
                const scratch = j_node.Object.get("scratch").?.String;

                writeLine(writer, "    compute.square(&{s}, &{s});", .{ input, scratch });
                // writeLine(writer, "    ", .{});
                // writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ input, name });
                // writeLine(writer, "    const preview_key = \"{s}.image\";", .{name});
                // writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_key, .{{ .data = preview_image_{s}.asBytes() }});", .{name});
                writePreview(writer, input, name);
            },
            kind_terrace => {
                const heightmap = j_node.Object.get("heightmap").?.String;
                const gradient = j_node.Object.get("gradient").?.String;

                writeLine(writer, "    heightmap2.copy({s});", .{heightmap});
                writeLine(writer, "    types.saveImageF32({s}, \"{s}_b4terrace\", false);", .{ gradient, gradient });
                writeLine(writer, "    types.saveImageF32(heightmap, \"{s}_b4terrace\", false);", .{heightmap});
                writeLine(writer, "    for (0..1) |_| {{", .{});
                writeLine(writer, "        for (0..1) |_| {{", .{});
                writeLine(writer, "            compute.terrace(&{s}, &{s}, &scratch_image);", .{ gradient, heightmap });
                writeLine(writer, "            nodes.math.rerangify(&{s});", .{heightmap});
                writeLine(writer, "            types.saveImageF32({s}, \"{s}\", false);", .{ heightmap, heightmap });
                writeLine(writer, "        }}", .{});
                writeLine(writer, "    }}", .{});
                // writeLine(writer, "    ", .{});
                // writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ heightmap, name });
                // writeLine(writer, "    const preview_key = \"{s}.image\";", .{name});
                // writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_key, .{{ .data = preview_image_{s}.asBytes() }});", .{name});
                writePreview(writer, heightmap, name);
            },
            kind_voronoi => {
                const settings = j_node.Object.get("settings").?.String;
                const points = j_node.Object.get("points").?.String;
                const voronoi = j_node.Object.get("voronoi").?.String;
                // needs_ctx = true;

                writeLine(writer, "    {s}.* = .{{", .{voronoi});
                writeLine(writer, "        .diagram = .{{}},", .{});
                writeLine(writer, "        .cells = std.ArrayList(nodes.voronoi.VoronoiCell).init(std.heap.c_allocator),", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    nodes.voronoi.generate_voronoi_map({s}, {s}.items, {s});", .{ settings, points, voronoi });
                // preview
                writeLine(writer, "", .{});
                writeLine(writer, "    var c_voronoi = c_cpp_nodes.Voronoi{{", .{});
                writeLine(writer, "        .voronoi_grid = {s}.diagram,", .{voronoi});
                writeLine(writer, "        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);", .{});
                writeLine(writer, "    const preview_grid_key = \"{s}.image\";", .{name});
                writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_grid_key, .{{ .data = preview_grid[0 .. preview_size * preview_size] }});", .{});
            },
            kind_water => {
                const water = j_node.Object.get("water").?.String;
                const heightmap = j_node.Object.get("heightmap").?.String;
                writeLine(writer, "    nodes.experiments.water({s}, &{s});", .{ water, heightmap });
                // writeLine(writer, "    ", .{});
                // writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ heightmap, name });
                // writeLine(writer, "    const preview_grid_key = \"{s}.image\";", .{name});
                // writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_grid_key, .{{ .data = preview_image_{s}.asBytes() }});", .{name});
                writePreview(writer, heightmap, name);
            },
            kind_write_heightmap => {
                const heightmap = j_node.Object.get("heightmap").?.String;
                writeLine(writer, "    if (!DRY_RUN) {{", .{});
                writeLine(writer, "        nodes.heightmap_format.heightmap_format(world_settings, {s});", .{heightmap});
                writeLine(writer, "    }}", .{});
            },
            kind_write_trees => {
                const heightmap = j_node.Object.get("heightmap").?.String;
                const points = j_node.Object.get("points").?.String;
                writeLine(writer, "    if (!DRY_RUN) {{", .{});
                writeLine(writer, "        nodes.experiments.write_trees({s}, {s});", .{ heightmap, points });
                writeLine(writer, "    }}", .{});
            },
            else => {
                writeLine(writer, "    // Unhandled node type: {s}", .{kind});
            },
        }

        // next
        const next_opt = j_node.Object.get("next");
        if (next_opt) |next| {
            writeLine(writer, "", .{});
            switch (next) {
                .String => {
                    writeLine(writer, "    ctx.next_nodes.insert(0, {s}) catch unreachable;", .{next.String});
                },
                .Array => {
                    for (next.Array.items, 0..) |item, item_i| {
                        writeLine(writer, "    ctx.next_nodes.insert({any}, {s}) catch unreachable;", .{ item_i, item.String });
                    }
                },
                else => {},
            }
        } else {
            // needs_ctx = false;
            writeLine(writer, "", .{});
            writeLine(writer, "    // Leaf node", .{});
        }

        if (!std.mem.containsAtLeast(u8, out.items[node_start_index..], 1, "ctx")) {
            writeLine(writer, "    _ = ctx; // autofix", .{});
        }
        writeLine(writer, "}}", .{});
        writeLine(writer, "", .{});
    }

    // writer.writeByte(0) catch unreachable;

    // std.zig.render.

    // const src = out.items[0 .. out.items.len - 1 :0];
    // const zig_tree = std.zig.Ast.parse(gpa, src, .zig) catch unreachable;
    // const zig_formatted = zig_tree.render(gpa) catch unreachable;

    // writeFile(zig_formatted, zig_path);
    writeFile(out.items, zig_path);
}
