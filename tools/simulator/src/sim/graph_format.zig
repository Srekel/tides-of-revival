const std = @import("std");
const builtin = @import("builtin");
// const tides_format = @import("tides_format.zig");
const json5 = @import("json5.zig");

const io = @import("io.zig");
const loadFile = io.loadFile;
const writeFile = io.writeFile;
const hash = io.hash;
const print = io.print;
const write = io.write;
const writeLine = io.writeLine;

const is_debug = builtin.mode == .Debug;

const kind_start = hash("start");
const kind_beaches = hash("beaches");
const kind_blur = hash("blur");
const kind_cities = hash("cities");
const kind_contours = hash("contours");
const kind_downsample = hash("downsample");
const kind_fbm = hash("fbm");
const kind_gather_points = hash("gather_points");
const kind_gradient = hash("gradient");
const kind_image_from_voronoi = hash("image_from_voronoi");
const kind_landscape_from_image = hash("landscape_from_image");
const kind_math = hash("math");
const kind_points_filter_proximity = hash("points_filter_proximity");
const kind_points_grid = hash("points_grid");
const kind_poisson = hash("poisson");
const kind_remap = hash("remap");
const kind_remap_curve = hash("remap_curve");
const kind_sequence = hash("sequence");
const kind_square = hash("square");
const kind_terrace = hash("terrace");
const kind_upsample = hash("upsample");
const kind_voronoi = hash("voronoi");
const kind_water = hash("water");
const kind_write_heightmap = hash("write_heightmap");
const kind_write_trees = hash("write_trees");

const kind_FbmSettings = hash("FbmSettings");
const kind_ImageF32 = hash("ImageF32");
const kind_ImageU32 = hash("ImageU32");
const kind_ImageVec2 = hash("ImageVec2");
const kind_PatchDataPts2d = hash("PatchDataPts2d");
const kind_PointList2D = hash("PointList2D");
const kind_PointList3D = hash("PointList3D");
const kind_PointListU32 = hash("PointListU32");
const kind_Size2D = hash("Size2D");
const kind_Voronoi = hash("Voronoi");
const kind_VoronoiSettings = hash("VoronoiSettings");
const kind_WorldSettings = hash("WorldSettings");

fn writePreview(writer: anytype, image_name: []const u8, node_name: []const u8) void {
    writeLine(writer, "", .{});
    writeLine(writer, "    types.saveImageF32({s}, \"{s}\", false);", .{ image_name, node_name });

    writeLine(writer, "    types.image_preview_f32({s}, &preview_image_{s});", .{ image_name, node_name });
    writeLine(writer, "    const preview_key_{s} = \"{s}.image\";", .{ node_name, node_name });
    writeLine(writer, "    ctx.previews.putAssumeCapacity(preview_key_{s}, .{{ .data = preview_image_{s}.asBytes() }});", .{ node_name, node_name });
}

fn writePreviewIndexed(writer: anytype, image_name: []const u8, node_name: []const u8, index: usize) void {
    writeLine(writer, "", .{});
    writeLine(writer, "    // types.saveImageF32({s}, \"{s}\", false);", .{ image_name, node_name });

    writeLine(writer, "    // types.image_preview_f32({s}, &preview_image_{s});", .{ image_name, node_name });
    writeLine(writer, "    // const preview_key_{s}_{d} = \"{s}.image\";", .{ node_name, index, node_name });
    writeLine(writer, "    // ctx.previews.putAssumeCapacity(preview_key_{s}_{d}, .{{ .data = preview_image_{s}.asBytes() }});", .{ node_name, index, node_name });
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
    _ = j_settings; // autofix

    // imports
    writeLine(writer, "const std = @import(\"std\");", .{});
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
    // writeLine(writer, "const DRY_RUN = {};", .{j_settings.Object.get("dry_run").?.Bool});
    writeLine(writer, "const DRY_RUN = {};", .{is_debug});
    writeLine(writer, "const kilometers = if (DRY_RUN) 2 else 16;", .{});
    writeLine(writer, "const preview_size = 512;", .{});
    writeLine(writer, "const preview_size_big = preview_size * 2;", .{});
    writeLine(writer, "pub const node_count = {any};", .{j_nodes.Array.items.len + 1});

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
            kind_ImageU32 => "types.ImageU32",
            kind_ImageVec2 => "types.ImageVec2",
            kind_PatchDataPts2d => "types.PatchDataPts2d",
            kind_PointList2D => "std.ArrayList(types.Vec2)",
            kind_PointList3D => "std.ArrayList(types.Vec3)",
            kind_PointListU32 => "std.ArrayList(u32)",
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

        write(writer, "{s} {s}: {s} = ", .{ if (is_const) "const" else "var", name, kind_type });

        switch (hash(kind)) {
            kind_FbmSettings => {
                const seed = j_var.Object.get("seed").?.Integer;
                const frequency = j_var.Object.get("frequency").?.Float;
                const octaves = j_var.Object.get("octaves").?.Integer;
                const rect = j_var.Object.get("rect").?.String;
                const scale = j_var.Object.get("scale").?.Float;
                writeLine(writer,
                    \\nodes.fbm.FbmSettings{{
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
            kind_ImageU32 => {
                const size = j_var.Object.get("size").?.String;
                writeLine(writer, "types.ImageU32.square({s}.width);", .{size});
            },
            kind_ImageVec2 => {
                const size = j_var.Object.get("size").?.String;
                writeLine(writer, "types.ImageVec2.square({s}.width);", .{size});
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
                    \\{s}{{
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
        writeLine(writer, "    std.log.info(\"Node: {s} [{s}]\", .{{}});\n", .{ name, kind });

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
                        kind_ImageU32 => {
                            const size = j_var.Object.get("size").?.String;
                            writeLine(writer, "    {s}.pixels = std.heap.c_allocator.alloc(u32, {s}.width * {s}.height) catch unreachable;", .{ var_name, size, size });
                        },
                        kind_ImageVec2 => {
                            const size = j_var.Object.get("size").?.String;
                            writeLine(writer, "    {s}.pixels = std.heap.c_allocator.alloc([2]f32, {s}.width * {s}.height) catch unreachable;", .{ var_name, size, size });
                        },
                        kind_PointList2D => {
                            writeLine(writer, "    {s} = @TypeOf({s}).init(std.heap.c_allocator);", .{ var_name, var_name });
                        },
                        kind_PointList3D => {
                            const capacity = j_var.Object.get("capacity").?.Integer;
                            writeLine(writer, "    {s} = @TypeOf({s}).initCapacity(std.heap.c_allocator, {d}) catch unreachable;", .{ var_name, var_name, capacity });
                        },
                        kind_PointListU32 => {
                            writeLine(writer, "    {s} = @TypeOf({s}).init(std.heap.c_allocator);", .{ var_name, var_name });
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
                writeLine(writer, "    );", .{});
                writeLine(writer, "    scratch_image.size.width = preview_size / downsample_divistor;", .{});
                writeLine(writer, "    scratch_image.size.height = preview_size / downsample_divistor;", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    nodes.experiments.voronoi_to_water(preview_grid[0 .. preview_size * preview_size], &scratch_image);", .{});
                writeLine(writer, "    nodes.math.rerangify(&scratch_image);", .{});
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
            kind_blur => {
                const input = j_node.Object.get("input").?.String;
                const output = j_node.Object.get("output").?.String;
                const j_iterations = j_node.Object.get("itetarations");
                const iterations: usize = @intCast(if (j_iterations) |j| j.Integer else 1);

                // TODO: Fix, this doesn't work
                for (0..iterations) |_| {
                    if (std.mem.eql(u8, input, output)) {
                        writeLine(writer, "    compute.blur(&{s}, &scratch_image, &{s});", .{ input, output });
                    } else {
                        writeLine(writer, "    compute.blur(&{s}, &scratch_image, &{s});", .{ input, output });
                    }
                    writePreview(writer, output, name);
                }
            },
            kind_cities => {
                const in_points = j_node.Object.get("in_points").?.String;
                const in_points_counter = j_node.Object.get("in_points_counter").?.String;
                const heightmap = j_node.Object.get("heightmap").?.String;
                const gradient = j_node.Object.get("gradient").?.String;
                writeLine(writer, "    if (!DRY_RUN) {{", .{});
                writeLine(writer, "        const x = types.BackedListVec2.createFromImageVec2(&{s}, {s}.pixels[0]);", .{ in_points, in_points_counter });
                writeLine(writer, "        nodes.experiments.cities(world_settings, {s},{s}, &{s}, &cities);", .{ heightmap, gradient, "x" });
                writeLine(writer, "    }}", .{});
            },
            kind_contours => {
                const voronoi = j_node.Object.get("voronoi").?.String;
                writeLine(writer, "    nodes.voronoi.contours({s});", .{voronoi});
            },
            kind_downsample => {
                const image_in = j_node.Object.get("image_in").?.String;
                const image_out = j_node.Object.get("image_out").?.String;
                const op = j_node.Object.get("op").?.String;
                const count: u32 = @intCast(j_node.Object.get("count").?.Integer);

                writeLine(writer, "    const orig_scratch_image_size = scratch_image.size;", .{});
                for (0..count) |_| {
                    // TODO: Support *different* ins and outs.
                    writeLine(writer, "    compute.downsample(&{s}, &scratch_image, &{s}, .{s});", .{ image_in, image_out, op });
                }
                writeLine(writer, "    scratch_image.size = orig_scratch_image_size;", .{});
                writePreview(writer, image_out, name);
            },
            kind_fbm => {
                const settings = j_node.Object.get("settings").?.String;
                const output = j_node.Object.get("output").?.String;

                writeLine(writer, "    const generate_fbm_settings = compute.GenerateFBMSettings{{", .{});
                writeLine(writer, "        .width = @intCast({s}.size.width),", .{output});
                writeLine(writer, "        .height = @intCast({s}.size.height),", .{output});
                writeLine(writer, "        .seed = {s}.seed,", .{settings});
                writeLine(writer, "        .frequency = {s}.frequency,", .{settings});
                writeLine(writer, "        .octaves = {s}.octaves,", .{settings});
                writeLine(writer, "        .scale = {s}.scale,", .{settings});
                writeLine(writer, "        ._padding = .{{ 0, 0 }},", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    compute.fbm(&{s}, generate_fbm_settings);", .{output});
                writeLine(writer, "    compute.min(&{s}, &scratch_image);", .{output});
                writeLine(writer, "    compute.max(&{s}, &scratch_image);", .{output});
                writeLine(writer, "    nodes.math.rerangify(&{s});", .{output});
                writeLine(writer, "", .{});
                writeLine(writer, "    compute.remap(&{s}, &scratch_image, 0, 1);", .{output});
                writePreview(writer, output, name);
            },
            kind_gather_points => {
                const image = j_node.Object.get("image").?.String;
                const point_list = j_node.Object.get("point_list").?.String;
                const counter_list = j_node.Object.get("counter_list").?.String;
                const world_size = j_node.Object.get("world_size").?.String;
                const threshold = j_node.Object.get("threshold").?.Float;
                writeLine(writer, "    compute.gatherPoints(&{s}, {s}.width, {s}.height, {d}, &{s}, &{s});", .{ image, world_size, world_size, threshold, point_list, counter_list });
                writeLine(writer, "    std.log.info(\"LOL count:{{d}}\", .{{{s}.pixels[0]}});", .{counter_list});
                writeLine(writer, "    std.log.info(\"LOL pt:{{d}},{{d}}\", .{{ {s}.pixels[0][0], {s}.pixels[0][1] }} );", .{ point_list, point_list });
                writeLine(writer, "    std.log.info(\"LOL pt:{{d:.3}},{{d:.3}}\", .{{ {s}.pixels[0][0], {s}.pixels[0][1] }} );", .{ point_list, point_list });

                // std.log.info("LOL count:{d}", .{counter_list.items[0]});

                // for (0..)
                // writePreview(writer, output, name);
            },
            kind_gradient => {
                const input = j_node.Object.get("input").?.String;
                const output = j_node.Object.get("output").?.String;
                writeLine(writer, "    nodes.gradient.gradient({s}, 1 / world_settings.terrain_height_max, &{s});", .{ input, output });
                writePreview(writer, output, name);
            },
            kind_image_from_voronoi => {
                const voronoi = j_node.Object.get("voronoi").?.String;
                const image = j_node.Object.get("image").?.String;
                writeLine(writer, "    var c_voronoi = c_cpp_nodes.Voronoi{{", .{});
                writeLine(writer, "        .voronoi_grid = {s}.diagram,", .{voronoi});
                writeLine(writer, "        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),", .{});
                writeLine(writer, "    }};", .{});
                writeLine(writer, "", .{});
                writeLine(writer, "    const imagef32_data = cpp_nodes.voronoi_to_imagef32(&c_voronoi, world_settings.size.width, world_settings.size.height);", .{});
                writeLine(writer, "    {s}.copyPixels(imagef32_data);", .{image});
                writeLine(writer, "    nodes.math.rerangify(&{s});", .{image});
                writePreview(writer, image, name);
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
            kind_math => {
                const op = j_node.Object.get("op").?.String;
                const inputs = j_node.Object.get("inputs").?.Array;
                const output = j_node.Object.get("output").?.String;

                // writeLine(writer, "    scratch_image.copy({s});", .{inputs.items[0].String});

                writeLine(writer, "    compute.math_{s}( &{s}, &{s}, &{s}, &{s});", .{
                    op,
                    inputs.items[0].String,
                    inputs.items[1].String,
                    output,
                    "scratch_image",
                });

                for (2..inputs.items.len) |i| {
                    writeLine(writer, "    compute.math_{s}( &{s}, &{s}, &{s}, &{s});", .{
                        op,
                        inputs.items[i].String,
                        output,
                        output,
                        "scratch_image",
                    });
                }

                writePreview(writer, output, name);
            },
            kind_points_filter_proximity => {
                const in_points = j_node.Object.get("in_points").?.String;
                const in_points_counter = j_node.Object.get("in_points_counter").?.String;
                const out_points = j_node.Object.get("out_points").?.String;
                const out_points_counter = j_node.Object.get("out_points_counter").?.String;
                _ = out_points; // autofix
                const min_distance = j_node.Object.get("min_distance").?.Float;
                writeLine(writer, "    var x = types.BackedListVec2.createFromImageVec2(&{s}, {s}.pixels[0]);", .{ in_points, in_points_counter });
                writeLine(writer, "    std.log.info(\"points_filter_proximity count:{{d}}\", .{{{s}.count}} );", .{"x"});
                writeLine(writer, "    nodes.points.points_filter_proximity_vec2(&{s}, &{s}, {d});", .{ "x", "x", min_distance });
                writeLine(writer, "    {s}.pixels[0] = {s}.count;", .{ out_points_counter, "x" });
                writeLine(writer, "    std.log.info(\"points_filter_proximity count:{{d}}\", .{{{s}.count}} );", .{"x"});
            },
            kind_points_grid => {
                const points = j_node.Object.get("points").?.String;
                const cell_size = j_node.Object.get("cell_size").?.Integer;
                const score_min = j_node.Object.get("score_min").?.Float;
                const image = j_node.Object.get("image").?.String;
                writeLine(writer, "    {s} = types.PatchDataPts2d.create(1, {s}.size.width / 128, 100, std.heap.c_allocator);", .{ points, image });
                writeLine(writer, "    nodes.experiments.points_distribution_grid({s}, {d}, .{{ .cell_size = {d}, .size = {s}.size }}, &{s});", .{ image, score_min, cell_size, image, points });
            },
            kind_poisson => {
                const points = j_node.Object.get("points").?.String;
                writeLine(writer, "    nodes.poisson.generate_points(world_size, 50, 1, &{s});", .{points});
            },
            kind_remap => {
                const input = j_node.Object.get("input").?.String;
                const output = j_node.Object.get("output").?.String;
                const new_min = j_node.Object.get("new_min").?.String;
                const new_max = j_node.Object.get("new_max").?.String;

                if (std.mem.eql(u8, input, output)) {
                    writeLine(writer, "    compute.remap(&{s}, &scratch_image, {s}, {s});", .{ input, new_min, new_max });
                } else {
                    writeLine(writer, "    {s}.copy({s});", .{ output, input });

                    writeLine(writer, "    compute.remap(&{s}, &scratch_image, {s}, {s});", .{ output, new_min, new_max });
                }

                writePreview(writer, output, name);
            },
            kind_remap_curve => {
                const image_in = j_node.Object.get("image_in").?.String;
                const image_out = j_node.Object.get("image_out").?.String;
                const curve = j_node.Object.get("curve").?.Array;

                writeLine(writer, "    const curve = [_]types.Vec2{{", .{});
                for (0..curve.items.len / 2) |i_elem| {
                    const i_elem1 = i_elem * 2;
                    const i_elem2 = i_elem * 2 + 1;
                    const v1 = curve.items[i_elem1].Float;
                    const v2 = curve.items[i_elem2].Float;
                    writeLine(writer, "        .{{ .x = {d}, .y = {d}}},", .{ v1, v2 });
                }
                writeLine(writer, "    }};", .{});
                writeLine(writer, "    compute.remapCurve(&{s}, &curve, &{s});", .{ image_in, image_out });

                writePreview(writer, image_out, name);
            },
            kind_sequence => {
                writeLine(writer, "    // Sequence:", .{});
            },
            kind_square => {
                const input = j_node.Object.get("input").?.String;
                const scratch = j_node.Object.get("scratch").?.String;

                writeLine(writer, "    compute.square(&{s}, &{s});", .{ input, scratch });
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
                writePreview(writer, heightmap, name);
            },
            kind_upsample => {
                const image_in = j_node.Object.get("image_in").?.String;
                const image_out = j_node.Object.get("image_out").?.String;
                const op = j_node.Object.get("op").?.String;
                const count: u32 = @intCast(j_node.Object.get("count").?.Integer);

                writeLine(writer, "    const orig_scratch_image_size = scratch_image.size;", .{});
                for (0..count) |_| {
                    // TODO: Support *different* ins and outs.
                    writeLine(writer, "    compute.upsample(&{s}, &scratch_image, &{s}, .{s});", .{ image_in, image_out, op });
                }
                writeLine(writer, "    scratch_image.size = orig_scratch_image_size;", .{});
                writePreview(writer, image_out, name);
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
