const std = @import("std");

const io = @import("../io.zig");
const graph = @import("graph.zig");
const Context = graph.Context;

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");
const nodes = @import("nodes/nodes.zig");
const types = @import("types.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

pub const self: graph.Graph = .{
    .nodes = &.{
        .{
            .name = "start",
            .connections_out = &.{1},
        },
        .{
            .name = "GenerateVoronoiMap1",
            .connections_out = &.{2},
        },
        .{
            .name = "generate_landscape_from_image",
            .connections_out = &.{3},
        },
        .{
            .name = "beaches",
            .connections_out = &.{4},
        },
        .{
            .name = "exit",
            .connections_out = &.{},
        },
    },
};

pub fn getGraph() *const graph.Graph {
    return &self;
}

const DRY_RUN = true;
const kilometers = if (DRY_RUN) 16 else 16;
const world_settings: types.WorldSettings = .{
    .size = .{ .width = kilometers * 1024, .height = kilometers * 1024 },
};

// IN
var map_settings: *c_cpp_nodes.MapSettings = undefined;

// OUT
var grid: *c_cpp_nodes.Grid = undefined;
var heightmap: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap2: types.ImageF32 = types.ImageF32.square(world_settings.size.width);

// LOCAL
var voronoi_settings: c_cpp_nodes.VoronoiSettings = undefined;
var fbm_settings = nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.00025,
    .octaves = 8,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 0.5,
};
var fbm_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var gradient_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var scratch_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var cities: std.ArrayList([3]f32) = undefined;

var fbm_trees_settings = nodes.fbm.FbmSettings{
    .seed = 123,
    .frequency = 0.005,
    .octaves = 5,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var fbm_trees_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);

pub fn start(ctx: *Context) void {
    // INITIALIZE IN
    const name_map_settings = "map";
    map_settings = @ptrCast(@alignCast(ctx.resources.get(name_map_settings)));

    // INITIALIZE OUT
    grid = std.heap.c_allocator.create(c_cpp_nodes.Grid) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_trees_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    gradient_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    preview_fbm_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, 512 * 512) catch unreachable;
    preview_fbm_trees_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, 512 * 512) catch unreachable;
    preview_heightmap_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, 512 * 512) catch unreachable;
    preview_heightmap2_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, 512 * 512) catch unreachable;
    preview_gradient_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, 512 * 512) catch unreachable;

    // INITIALIZE LOCAL
    voronoi_settings.radius = 0.05;
    voronoi_settings.num_relaxations = 10;
    cities = @TypeOf(cities).initCapacity(std.heap.c_allocator, 100) catch unreachable;

    points = @TypeOf(points).init(std.heap.c_allocator);
    nodes.poisson.generate_points(1, 1, 1, &points);

    // Start!
    // ctx.next_nodes.appendAssumeCapacity(doNode_GenerateVoronoiMap1);
    ctx.next_nodes.appendAssumeCapacity(doNode_fbm);
}

pub fn exit(ctx: *Context) void {
    _ = ctx; // autofix
    const name_grid = "voronoigrid";
    _ = name_grid; // autofix
    // ctx.resources.put(name_grid, &grid);

    // ctx.next_nodes.appendAssumeCapacity(heightmap_output.start);
}

fn doNode_GenerateVoronoiMap1(ctx: *Context) void {
    cpp_nodes.generate_voronoi_map(map_settings, &voronoi_settings, grid);

    const preview_grid = cpp_nodes.generate_landscape_preview(grid, 512, 512);
    const preview_grid_key = "GenerateVoronoiMap1.grid";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. 512 * 512 * 4] });

    ctx.next_nodes.appendAssumeCapacity(doNode_generate_landscape_from_image);
}

fn doNode_generate_landscape_from_image(ctx: *Context) void {
    cpp_nodes.generate_landscape_from_image(grid, "content/tides_2.0.png");

    const preview_grid = cpp_nodes.generate_landscape_preview(grid, 512, 512);
    const preview_grid_key = "generate_landscape_from_image.grid";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. 512 * 512 * 4] });

    ctx.next_nodes.appendAssumeCapacity(doNode_beaches);
}

var points: std.ArrayList([2]f32) = undefined;
fn doNode_beaches(ctx: *Context) void {
    nodes.voronoi.contours(grid);

    const preview_grid = cpp_nodes.generate_landscape_preview(grid, 512, 512);
    const preview_grid_key = "beaches.grid";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. 512 * 512 * 4] });

    ctx.next_nodes.appendAssumeCapacity(doNode_fbm);
}

const SquareSettings = extern struct {
    width: u32,
    height: u32,
    _padding: [2]f32 = undefined,
};
const RemapSettings = extern struct {
    from_min: f32,
    from_max: f32,
    to_min: f32,
    to_max: f32,
    width: u32,
    height: u32,
    _padding: [2]f32 = undefined,
};
var remap_settings = RemapSettings{
    .from_min = undefined,
    .from_max = undefined,
    .to_min = 0,
    .to_max = 1,
    .width = kilometers * 1024,
    .height = kilometers * 1024,
};

var preview_fbm_image = types.ImageRGBA.square(512);
fn doNode_fbm(ctx: *Context) void {
    nodes.fbm.fbm(&fbm_settings, &fbm_image);

    remap_settings.from_min = fbm_image.height_min;
    remap_settings.from_max = fbm_image.height_max;
    remap_settings.to_min = 0;
    remap_settings.to_max = 1;
    var compute_info = graph.ComputeInfo{
        .compute_id = .remap,
        .buffer_width = @intCast(fbm_image.size.width),
        .buffer_height = @intCast(fbm_image.size.height),
        .in = fbm_image.pixels.ptr,
        .out = scratch_image.pixels.ptr,
        .data_size = @sizeOf(RemapSettings),
        .data = std.mem.asBytes(&remap_settings),
    };
    ctx.compute_fn(&compute_info);
    scratch_image.height_min = 0;
    scratch_image.height_max = 1;
    fbm_image.swap(&scratch_image);

    types.image_preview_f32(fbm_image, &preview_fbm_image);
    const preview_grid_key = "fbm.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_fbm_image.asBytes() });

    ctx.next_nodes.appendAssumeCapacity(doNode_heightmap);
}

var preview_heightmap_image = types.ImageRGBA.square(512);
var preview_heightmap2_image = types.ImageRGBA.square(512);
fn doNode_heightmap(ctx: *Context) void {
    heightmap.copy(fbm_image);
    heightmap.remap(0, world_settings.terrain_height_max);

    types.image_preview_f32(heightmap, &preview_heightmap_image);
    const preview_key = "heightmap.image";
    ctx.previews.putAssumeCapacity(preview_key, .{ .data = preview_heightmap_image.asBytes() });

    ctx.next_nodes.appendAssumeCapacity(doNode_gradient);
    ctx.next_nodes.appendAssumeCapacity(doNode_heightmap_file);
}

const GradientData = extern struct {
    g_buffer_width: u32,
    g_buffer_height: u32,
    g_height_ratio: f32,
    _padding: f32 = 0,
};

var preview_gradient_image = types.ImageRGBA.square(512);
fn doNode_gradient(ctx: *Context) void {
    const gradient_data = GradientData{
        .g_buffer_width = kilometers * 1024,
        .g_buffer_height = kilometers * 1024,
        .g_height_ratio = 1 / world_settings.terrain_height_max,
    };
    var compute_info_gradient = graph.ComputeInfo{
        .compute_id = .gradient,
        .buffer_width = @intCast(heightmap.size.width),
        .buffer_height = @intCast(heightmap.size.height),
        .in = heightmap.pixels.ptr,
        .out = gradient_image.pixels.ptr,
        .data_size = @sizeOf(GradientData),
        .data = std.mem.asBytes(&gradient_data),
    };
    ctx.compute_fn(&compute_info_gradient);
    nodes.math.rerangify(&gradient_image);
    // fbm_trees_image.swap(&scratch_image);

    // nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);

    types.image_preview_f32(gradient_image, &preview_gradient_image);
    const preview_grid_key = "gradient.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_gradient_image.asBytes() });

    heightmap2.copy(heightmap);
    for (0..3) |_| {
        nodes.gradient.terrace(heightmap, gradient_image, &heightmap2, &scratch_image);
        nodes.gradient.terrace(heightmap2, gradient_image, &heightmap, &scratch_image);
    }
    nodes.gradient.terrace(heightmap, gradient_image, &heightmap2, &scratch_image);

    types.image_preview_f32(heightmap2, &preview_heightmap2_image);
    const preview_key2 = "heightmap2.image";
    ctx.previews.putAssumeCapacity(preview_key2, .{ .data = preview_heightmap2_image.asBytes() });

    ctx.next_nodes.appendAssumeCapacity(doNode_cities);
    ctx.next_nodes.appendAssumeCapacity(doNode_fbm_trees);
}

var preview_cities_image = types.ImageRGBA.square(512);
fn doNode_cities(ctx: *Context) void {
    _ = ctx; // autofix
    if (!DRY_RUN) {
        nodes.experiments.cities(world_settings, heightmap2, gradient_image, &cities);
    }

    // preview_cities_image.copy(preview_heightmap_image);
    // types.image_preview_f32(cities_image, &preview_cities_image);
    // const preview_grid_key = "cities.image";
    // ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_cities_image.asBytes() });
}

var preview_fbm_trees_image = types.ImageRGBA.square(512);
fn doNode_fbm_trees(ctx: *Context) void {
    nodes.fbm.fbm(&fbm_trees_settings, &fbm_trees_image);

    remap_settings.from_min = fbm_trees_image.height_min;
    remap_settings.from_max = fbm_trees_image.height_max;
    remap_settings.to_min = 0;
    remap_settings.to_max = 1;
    var compute_info = graph.ComputeInfo{
        .compute_id = .remap,
        .buffer_width = @intCast(fbm_trees_image.size.width),
        .buffer_height = @intCast(fbm_trees_image.size.height),
        .in = fbm_trees_image.pixels.ptr,
        .out = scratch_image.pixels.ptr,
        .data_size = @sizeOf(RemapSettings),
        .data = std.mem.asBytes(&remap_settings),
    };
    ctx.compute_fn(&compute_info);
    scratch_image.height_min = 0;
    scratch_image.height_max = 1;
    fbm_trees_image.swap(&scratch_image);

    const square_settings = SquareSettings{
        .width = kilometers * 1024,
        .height = kilometers * 1024,
    };
    var compute_info_square = graph.ComputeInfo{
        .compute_id = .square,
        .buffer_width = @intCast(fbm_trees_image.size.width),
        .buffer_height = @intCast(fbm_trees_image.size.height),
        .in = fbm_trees_image.pixels.ptr,
        .out = scratch_image.pixels.ptr,
        .data_size = @sizeOf(SquareSettings),
        .data = std.mem.asBytes(&square_settings),
    };
    ctx.compute_fn(&compute_info_square);
    scratch_image.height_min = fbm_trees_image.height_min * fbm_trees_image.height_min;
    scratch_image.height_max = fbm_trees_image.height_max * fbm_trees_image.height_max;
    fbm_trees_image.swap(&scratch_image);

    // nodes.math.square(&fbm_trees_image);

    types.image_preview_f32(fbm_trees_image, &preview_fbm_trees_image);
    const preview_grid_key = "fbm_trees.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_fbm_trees_image.asBytes() });

    ctx.next_nodes.appendAssumeCapacity(doNode_trees);
}

var preview_trees_image = types.ImageRGBA.square(512);
fn doNode_trees(ctx: *Context) void {
    _ = ctx; // autofix
    var trees = types.PatchDataPts2d.create(1, fbm_trees_image.size.width / 128, 100, std.heap.c_allocator);
    nodes.experiments.points_distribution_grid(fbm_trees_image, 0.6, .{ .cell_size = 16, .size = fbm_trees_image.size }, &trees);
    if (!DRY_RUN) {
        nodes.experiments.write_trees(heightmap2, trees);
    }
}

fn doNode_heightmap_file(ctx: *Context) void {
    _ = ctx; // autofix
    if (!DRY_RUN) {
        nodes.heightmap_format.heightmap_format(world_settings, heightmap2);
    }
}
