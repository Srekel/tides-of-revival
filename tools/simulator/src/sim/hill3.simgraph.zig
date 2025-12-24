const std = @import("std");
const graph = @import("graph.zig");
const Context = graph.Context;
const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");
const nodes = @import("nodes/nodes.zig");
const types = @import("types.zig");
const compute = @import("compute.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

// ============ CONSTANTS ============
const DRY_RUN = true;
const kilometers = if (DRY_RUN) 2 else 16;
const preview_size = 512;
const preview_size_big = preview_size * 2;
pub const node_count = 50;

// ============ VARS ============
const world_size: types.Size2D = .{ .width = kilometers * 1024, .height = kilometers * 1024 };
const world_settings: types.WorldSettings = .{ .size = world_size };
var voronoi: *nodes.voronoi.Voronoi = undefined;
var voronoi_points: std.ArrayList(types.Vec2) = undefined;
var voronoi_settings: nodes.voronoi.VoronoiSettings = nodes.voronoi.VoronoiSettings{
    .seed = 0,
    .size = world_size.width,
    .radius = 1,
    .num_relaxations = 5,
};
var fbm_settings_trees: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.005,
    .octaves = 8,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 0.5,
};
var voronoi_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var fbm_settings_water: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.00005,
    .octaves = 4,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var fbm_settings_plains: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 2,
    .frequency = 0.0005,
    .octaves = 4,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var fbm_settings_hills: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 3,
    .frequency = 0.0005,
    .octaves = 6,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var fbm_settings_mountains: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 4,
    .frequency = 0.0005,
    .octaves = 8,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var heightmap_water: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap_plains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap_hills: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap_mountains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var weight_water: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var weight_plains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var weight_shore: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var weight_hills: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var weight_mountains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap2: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var fbm_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var fbm_trees_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var gradient_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var scratch_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var scratch_image2: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var water_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var cities: std.ArrayList(types.Vec3) = undefined;
var trees_points: types.PatchDataPts2d = undefined;
var village_gradient: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var village_points: types.ImageVec2 = types.ImageVec2.square(world_settings.size.width);
var village_points_counter: types.ImageU32 = types.ImageU32.square(world_settings.size.width);

// ============ PREVIEW IMAGES ============
var preview_image_start = types.ImageRGBA.square(preview_size);
var preview_image_exit = types.ImageRGBA.square(preview_size);
var preview_image_main = types.ImageRGBA.square(preview_size);
var preview_image_main_generate_voronoi = types.ImageRGBA.square(preview_size);
var preview_image_main_generate_heightmap = types.ImageRGBA.square(preview_size);
var preview_image_generate_poisson_for_voronoi = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_map = types.ImageRGBA.square(preview_size);
var preview_image_generate_landscape_from_image = types.ImageRGBA.square(preview_size);
var preview_image_generate_contours = types.ImageRGBA.square(preview_size);
var preview_image_generate_image_from_voronoi = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_water = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_weight_water = types.ImageRGBA.square(preview_size);
var preview_image_blur_weight_water = types.ImageRGBA.square(preview_size);
var preview_image_multiply_heightmap_weight_water = types.ImageRGBA.square(preview_size);
var preview_image_remap_heightmap_water = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_plains = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_weight_plains = types.ImageRGBA.square(preview_size);
var preview_image_blur_weight_plains = types.ImageRGBA.square(preview_size);
var preview_image_multiply_heightmap_weight_plains = types.ImageRGBA.square(preview_size);
var preview_image_remap_heightmap_plains = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_weight_shore = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_hills = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_weight_hills = types.ImageRGBA.square(preview_size);
var preview_image_blur_weight_hills = types.ImageRGBA.square(preview_size);
var preview_image_multiply_heightmap_weight_hills = types.ImageRGBA.square(preview_size);
var preview_image_remap_heightmap_hills = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_mountains = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_weight_mountains = types.ImageRGBA.square(preview_size);
var preview_image_blur_weight_mountains = types.ImageRGBA.square(preview_size);
var preview_image_multiply_heightmap_weight_mountains = types.ImageRGBA.square(preview_size);
var preview_image_remap_heightmap_mountains = types.ImageRGBA.square(preview_size);
var preview_image_merge_heightmaps = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_gradient = types.ImageRGBA.square(preview_size);
var preview_image_generate_terrace = types.ImageRGBA.square(preview_size);
var preview_image_generate_erosion = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_gradient2 = types.ImageRGBA.square(preview_size);
var preview_image_output_cities = types.ImageRGBA.square(preview_size);
var preview_image_generate_trees_fbm = types.ImageRGBA.square(preview_size);
var preview_image_trees_square = types.ImageRGBA.square(preview_size);
var preview_image_generate_trees_points = types.ImageRGBA.square(preview_size);
var preview_image_output_trees_to_file = types.ImageRGBA.square(preview_size);
var preview_image_output_heightmap_to_file = types.ImageRGBA.square(preview_size);
var preview_image_remap_village_gradient = types.ImageRGBA.square(preview_size);
var preview_image_downsample_village_gradient = types.ImageRGBA.square(preview_size);
var preview_image_upsample_village_gradient = types.ImageRGBA.square(preview_size);
var preview_image_multiply_village_gradient_plains = types.ImageRGBA.square(preview_size);
var preview_image_multiply_village_gradient_shore = types.ImageRGBA.square(preview_size);
var preview_image_village_output_points = types.ImageRGBA.square(preview_size);
var preview_image_village_points_filter_proximity = types.ImageRGBA.square(preview_size);

// ============ NODES ============
pub fn start(ctx: *Context) void {
    std.log.info("Node: start [start]", .{});

    // Initialize vars
    voronoi = std.heap.c_allocator.create(nodes.voronoi.Voronoi) catch unreachable;
    voronoi_points = @TypeOf(voronoi_points).init(std.heap.c_allocator);
    voronoi_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap_water.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap_plains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap_hills.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap_mountains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_water.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_plains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_shore.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_hills.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_mountains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_trees_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    gradient_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    water_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    cities = @TypeOf(cities).initCapacity(std.heap.c_allocator, 1000) catch unreachable;
    village_gradient.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    village_points.pixels = std.heap.c_allocator.alloc([2]f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    village_points_counter.pixels = std.heap.c_allocator.alloc(u32, world_settings.size.width * world_settings.size.height) catch unreachable;

    // Initialize preview images
    preview_image_start.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_exit.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_main.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_main_generate_voronoi.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_main_generate_heightmap.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_poisson_for_voronoi.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_map.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_landscape_from_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_contours.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_image_from_voronoi.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_water.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_weight_water.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_blur_weight_water.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_multiply_heightmap_weight_water.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_remap_heightmap_water.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_weight_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_blur_weight_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_multiply_heightmap_weight_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_remap_heightmap_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_weight_shore.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_hills.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_weight_hills.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_blur_weight_hills.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_multiply_heightmap_weight_hills.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_remap_heightmap_hills.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_mountains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_weight_mountains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_blur_weight_mountains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_multiply_heightmap_weight_mountains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_remap_heightmap_mountains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_merge_heightmaps.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_terrace.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_erosion.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_gradient2.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_cities.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_trees_fbm.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_trees_square.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_trees_points.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_trees_to_file.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_heightmap_to_file.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_remap_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_downsample_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_upsample_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_multiply_village_gradient_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_multiply_village_gradient_shore.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_village_output_points.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_village_points_filter_proximity.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;

    ctx.next_nodes.insert(0, main) catch unreachable;
}

pub fn exit(ctx: *Context) void {
    std.log.info("Node: exit [exit]", .{});

    // Unhandled node type: exit

    // Leaf node
    _ = ctx; // autofix
}

pub fn main(ctx: *Context) void {
    std.log.info("Node: main [sequence]", .{});

    // Sequence:

    ctx.next_nodes.insert(0, main_generate_voronoi) catch unreachable;
    ctx.next_nodes.insert(1, main_generate_heightmap) catch unreachable;
    ctx.next_nodes.insert(2, generate_trees_fbm) catch unreachable;
    ctx.next_nodes.insert(3, output_heightmap_to_file) catch unreachable;
    ctx.next_nodes.insert(4, remap_village_gradient) catch unreachable;
    ctx.next_nodes.insert(5, output_cities) catch unreachable;
}

pub fn main_generate_voronoi(ctx: *Context) void {
    std.log.info("Node: main_generate_voronoi [sequence]", .{});

    // Sequence:

    ctx.next_nodes.insert(0, generate_poisson_for_voronoi) catch unreachable;
    ctx.next_nodes.insert(1, generate_voronoi_map) catch unreachable;
    ctx.next_nodes.insert(2, generate_landscape_from_image) catch unreachable;
    ctx.next_nodes.insert(3, generate_image_from_voronoi) catch unreachable;
}

pub fn main_generate_heightmap(ctx: *Context) void {
    std.log.info("Node: main_generate_heightmap [sequence]", .{});

    // Sequence:

    ctx.next_nodes.insert(0, generate_heightmap_hills) catch unreachable;
    ctx.next_nodes.insert(1, generate_heightmap_mountains) catch unreachable;
    ctx.next_nodes.insert(2, merge_heightmaps) catch unreachable;
    ctx.next_nodes.insert(3, generate_heightmap_gradient) catch unreachable;
    ctx.next_nodes.insert(4, generate_erosion) catch unreachable;
    ctx.next_nodes.insert(5, generate_heightmap_gradient2) catch unreachable;
}

pub fn generate_poisson_for_voronoi(ctx: *Context) void {
    std.log.info("Node: generate_poisson_for_voronoi [poisson]", .{});

    nodes.poisson.generate_points(world_size, 50, 1, &voronoi_points);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_voronoi_map(ctx: *Context) void {
    std.log.info("Node: generate_voronoi_map [voronoi]", .{});

    voronoi.* = .{
        .diagram = .{},
        .cells = std.ArrayList(nodes.voronoi.VoronoiCell).init(std.heap.c_allocator),
    };

    nodes.voronoi.generate_voronoi_map(voronoi_settings, voronoi_points.items, voronoi);

    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };
    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);
    const preview_grid_key = "generate_voronoi_map.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size] });

    // Leaf node
}

pub fn generate_landscape_from_image(ctx: *Context) void {
    std.log.info("Node: generate_landscape_from_image [landscape_from_image]", .{});

    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };
    cpp_nodes.generate_landscape_from_image(&c_voronoi, "../../../../content/world/hill3/tides.png");

    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);
    const preview_grid_key = "generate_landscape_from_image.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size] });

    // Leaf node
}

pub fn generate_contours(ctx: *Context) void {
    std.log.info("Node: generate_contours [contours]", .{});

    nodes.voronoi.contours(voronoi);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_image_from_voronoi(ctx: *Context) void {
    std.log.info("Node: generate_image_from_voronoi [image_from_voronoi]", .{});

    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };

    const imagef32_data = cpp_nodes.voronoi_to_imagef32(&c_voronoi, world_settings.size.width, world_settings.size.height);
    voronoi_image.copyPixels(imagef32_data);
    nodes.math.rerangify(&voronoi_image);

    types.image_preview_f32(voronoi_image, &preview_image_generate_image_from_voronoi);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_heightmap_water(ctx: *Context) void {
    std.log.info("Node: generate_heightmap_water [fbm]", .{});

    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(heightmap_water.size.width),
        .height = @intCast(heightmap_water.size.height),
        .seed = fbm_settings_water.seed,
        .frequency = fbm_settings_water.frequency,
        .octaves = fbm_settings_water.octaves,
        .scale = fbm_settings_water.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&heightmap_water, generate_fbm_settings);
    compute.min(&heightmap_water, &scratch_image);
    compute.max(&heightmap_water, &scratch_image);
    nodes.math.rerangify(&heightmap_water);

    compute.remap(&heightmap_water, &scratch_image, 0, 1);

    types.image_preview_f32(heightmap_water, &preview_image_generate_heightmap_water);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_voronoi_weight_water(ctx: *Context) void {
    std.log.info("Node: generate_voronoi_weight_water [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 1},
        .{ .x = 2, .y = 0},
        .{ .x = 3, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_water);

    types.image_preview_f32(weight_water, &preview_image_generate_voronoi_weight_water);

    ctx.next_nodes.insert(0, blur_weight_water) catch unreachable;
}

pub fn blur_weight_water(ctx: *Context) void {
    std.log.info("Node: blur_weight_water [blur]", .{});

    compute.blur(&weight_water, &scratch_image, &weight_water);

    types.image_preview_f32(weight_water, &preview_image_blur_weight_water);

    ctx.next_nodes.insert(0, remap_heightmap_water) catch unreachable;
}

pub fn multiply_heightmap_weight_water(ctx: *Context) void {
    std.log.info("Node: multiply_heightmap_weight_water [math]", .{});

    compute.math_multiply( &heightmap_water, &weight_water, &heightmap_water, &scratch_image);

    types.image_preview_f32(heightmap_water, &preview_image_multiply_heightmap_weight_water);

    // Leaf node
    _ = ctx; // autofix
}

pub fn remap_heightmap_water(ctx: *Context) void {
    std.log.info("Node: remap_heightmap_water [remap]", .{});

    compute.remap(&heightmap_water, &scratch_image, 0, 50);

    types.image_preview_f32(heightmap_water, &preview_image_remap_heightmap_water);

    ctx.next_nodes.insert(0, multiply_heightmap_weight_water) catch unreachable;
}

pub fn generate_heightmap_plains(ctx: *Context) void {
    std.log.info("Node: generate_heightmap_plains [fbm]", .{});

    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(heightmap_plains.size.width),
        .height = @intCast(heightmap_plains.size.height),
        .seed = fbm_settings_plains.seed,
        .frequency = fbm_settings_plains.frequency,
        .octaves = fbm_settings_plains.octaves,
        .scale = fbm_settings_plains.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&heightmap_plains, generate_fbm_settings);
    compute.min(&heightmap_plains, &scratch_image);
    compute.max(&heightmap_plains, &scratch_image);
    nodes.math.rerangify(&heightmap_plains);

    compute.remap(&heightmap_plains, &scratch_image, 0, 1);

    types.image_preview_f32(heightmap_plains, &preview_image_generate_heightmap_plains);

    ctx.next_nodes.insert(0, generate_voronoi_weight_plains) catch unreachable;
}

pub fn generate_voronoi_weight_plains(ctx: *Context) void {
    std.log.info("Node: generate_voronoi_weight_plains [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 1},
        .{ .x = 3, .y = 1},
        .{ .x = 4, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_plains);

    types.image_preview_f32(weight_plains, &preview_image_generate_voronoi_weight_plains);

    ctx.next_nodes.insert(0, blur_weight_plains) catch unreachable;
}

pub fn blur_weight_plains(ctx: *Context) void {
    std.log.info("Node: blur_weight_plains [blur]", .{});

    compute.blur(&weight_plains, &scratch_image, &weight_plains);

    types.image_preview_f32(weight_plains, &preview_image_blur_weight_plains);

    ctx.next_nodes.insert(0, remap_heightmap_plains) catch unreachable;
}

pub fn multiply_heightmap_weight_plains(ctx: *Context) void {
    std.log.info("Node: multiply_heightmap_weight_plains [math]", .{});

    compute.math_multiply( &heightmap_plains, &weight_plains, &heightmap_plains, &scratch_image);

    types.image_preview_f32(heightmap_plains, &preview_image_multiply_heightmap_weight_plains);

    // Leaf node
    _ = ctx; // autofix
}

pub fn remap_heightmap_plains(ctx: *Context) void {
    std.log.info("Node: remap_heightmap_plains [remap]", .{});

    compute.remap(&heightmap_plains, &scratch_image, 50, 150);

    types.image_preview_f32(heightmap_plains, &preview_image_remap_heightmap_plains);

    ctx.next_nodes.insert(0, multiply_heightmap_weight_plains) catch unreachable;
}

pub fn generate_voronoi_weight_shore(ctx: *Context) void {
    std.log.info("Node: generate_voronoi_weight_shore [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 1},
        .{ .x = 3, .y = 0},
        .{ .x = 4, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_shore);

    types.image_preview_f32(weight_shore, &preview_image_generate_voronoi_weight_shore);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_heightmap_hills(ctx: *Context) void {
    std.log.info("Node: generate_heightmap_hills [fbm]", .{});

    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(heightmap_hills.size.width),
        .height = @intCast(heightmap_hills.size.height),
        .seed = fbm_settings_hills.seed,
        .frequency = fbm_settings_hills.frequency,
        .octaves = fbm_settings_hills.octaves,
        .scale = fbm_settings_hills.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&heightmap_hills, generate_fbm_settings);
    compute.min(&heightmap_hills, &scratch_image);
    compute.max(&heightmap_hills, &scratch_image);
    nodes.math.rerangify(&heightmap_hills);

    compute.remap(&heightmap_hills, &scratch_image, 0, 1);

    types.image_preview_f32(heightmap_hills, &preview_image_generate_heightmap_hills);

    ctx.next_nodes.insert(0, generate_voronoi_weight_hills) catch unreachable;
}

pub fn generate_voronoi_weight_hills(ctx: *Context) void {
    std.log.info("Node: generate_voronoi_weight_hills [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 0},
        .{ .x = 3, .y = 0},
        .{ .x = 4, .y = 1},
        .{ .x = 5, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_hills);

    types.image_preview_f32(weight_hills, &preview_image_generate_voronoi_weight_hills);

    ctx.next_nodes.insert(0, blur_weight_hills) catch unreachable;
}

pub fn blur_weight_hills(ctx: *Context) void {
    std.log.info("Node: blur_weight_hills [blur]", .{});

    compute.blur(&weight_hills, &scratch_image, &weight_hills);

    types.image_preview_f32(weight_hills, &preview_image_blur_weight_hills);

    ctx.next_nodes.insert(0, remap_heightmap_hills) catch unreachable;
}

pub fn multiply_heightmap_weight_hills(ctx: *Context) void {
    std.log.info("Node: multiply_heightmap_weight_hills [math]", .{});

    compute.math_multiply( &heightmap_hills, &weight_hills, &heightmap_hills, &scratch_image);

    types.image_preview_f32(heightmap_hills, &preview_image_multiply_heightmap_weight_hills);

    // Leaf node
    _ = ctx; // autofix
}

pub fn remap_heightmap_hills(ctx: *Context) void {
    std.log.info("Node: remap_heightmap_hills [remap]", .{});

    compute.remap(&heightmap_hills, &scratch_image, 150, 500);

    types.image_preview_f32(heightmap_hills, &preview_image_remap_heightmap_hills);

    ctx.next_nodes.insert(0, multiply_heightmap_weight_hills) catch unreachable;
}

pub fn generate_heightmap_mountains(ctx: *Context) void {
    std.log.info("Node: generate_heightmap_mountains [fbm]", .{});

    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(heightmap_mountains.size.width),
        .height = @intCast(heightmap_mountains.size.height),
        .seed = fbm_settings_mountains.seed,
        .frequency = fbm_settings_mountains.frequency,
        .octaves = fbm_settings_mountains.octaves,
        .scale = fbm_settings_mountains.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&heightmap_mountains, generate_fbm_settings);
    compute.min(&heightmap_mountains, &scratch_image);
    compute.max(&heightmap_mountains, &scratch_image);
    nodes.math.rerangify(&heightmap_mountains);

    compute.remap(&heightmap_mountains, &scratch_image, 0, 1);

    types.image_preview_f32(heightmap_mountains, &preview_image_generate_heightmap_mountains);

    ctx.next_nodes.insert(0, generate_voronoi_weight_mountains) catch unreachable;
}

pub fn generate_voronoi_weight_mountains(ctx: *Context) void {
    std.log.info("Node: generate_voronoi_weight_mountains [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 0},
        .{ .x = 3, .y = 0},
        .{ .x = 4, .y = 0},
        .{ .x = 5, .y = 1},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_mountains);

    types.image_preview_f32(weight_mountains, &preview_image_generate_voronoi_weight_mountains);

    ctx.next_nodes.insert(0, blur_weight_mountains) catch unreachable;
}

pub fn blur_weight_mountains(ctx: *Context) void {
    std.log.info("Node: blur_weight_mountains [blur]", .{});

    compute.blur(&weight_mountains, &scratch_image, &weight_mountains);

    types.image_preview_f32(weight_mountains, &preview_image_blur_weight_mountains);

    ctx.next_nodes.insert(0, remap_heightmap_mountains) catch unreachable;
}

pub fn multiply_heightmap_weight_mountains(ctx: *Context) void {
    std.log.info("Node: multiply_heightmap_weight_mountains [math]", .{});

    compute.math_multiply( &heightmap_mountains, &weight_mountains, &heightmap_mountains, &scratch_image);

    types.image_preview_f32(heightmap_mountains, &preview_image_multiply_heightmap_weight_mountains);

    // Leaf node
    _ = ctx; // autofix
}

pub fn remap_heightmap_mountains(ctx: *Context) void {
    std.log.info("Node: remap_heightmap_mountains [remap]", .{});

    compute.remap(&heightmap_mountains, &scratch_image, 20, 1500);

    types.image_preview_f32(heightmap_mountains, &preview_image_remap_heightmap_mountains);

    ctx.next_nodes.insert(0, multiply_heightmap_weight_mountains) catch unreachable;
}

pub fn merge_heightmaps(ctx: *Context) void {
    std.log.info("Node: merge_heightmaps [math]", .{});

    compute.math_add( &heightmap_hills, &heightmap_mountains, &heightmap, &scratch_image);

    types.image_preview_f32(heightmap, &preview_image_merge_heightmaps);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_heightmap_gradient(ctx: *Context) void {
    std.log.info("Node: generate_heightmap_gradient [gradient]", .{});

    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);

    types.image_preview_f32(gradient_image, &preview_image_generate_heightmap_gradient);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_terrace(ctx: *Context) void {
    std.log.info("Node: generate_terrace [terrace]", .{});

    heightmap2.copy(heightmap);
    types.saveImageF32(gradient_image, "gradient_image_b4terrace", false);
    types.saveImageF32(heightmap, "heightmap_b4terrace", false);
    for (0..1) |_| {
        for (0..1) |_| {
            compute.terrace(&gradient_image, &heightmap, &scratch_image);
            nodes.math.rerangify(&heightmap);
            types.saveImageF32(heightmap, "heightmap", false);
        }
    }

    types.image_preview_f32(heightmap, &preview_image_generate_terrace);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_erosion(ctx: *Context) void {
    std.log.info("Node: generate_erosion [erosion]", .{});

    for (0..1) |_| {
        compute.erosion(&heightmap, &scratch_image);
        nodes.math.rerangify(&heightmap);
    }

    types.image_preview_f32(heightmap, &preview_image_generate_erosion);

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_heightmap_gradient2(ctx: *Context) void {
    std.log.info("Node: generate_heightmap_gradient2 [gradient]", .{});

    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);

    types.image_preview_f32(gradient_image, &preview_image_generate_heightmap_gradient2);

    // Leaf node
    _ = ctx; // autofix
}

pub fn output_cities(ctx: *Context) void {
    std.log.info("Node: output_cities [cities]", .{});

    if (!DRY_RUN) {
        const x = types.BackedListVec2.createFromImageVec2(&village_points, village_points_counter.pixels[0]);
        nodes.experiments.cities(world_settings, heightmap,gradient_image, &x, &cities);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_trees_fbm(ctx: *Context) void {
    std.log.info("Node: generate_trees_fbm [fbm]", .{});

    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(fbm_trees_image.size.width),
        .height = @intCast(fbm_trees_image.size.height),
        .seed = fbm_settings_trees.seed,
        .frequency = fbm_settings_trees.frequency,
        .octaves = fbm_settings_trees.octaves,
        .scale = fbm_settings_trees.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&fbm_trees_image, generate_fbm_settings);
    compute.min(&fbm_trees_image, &scratch_image);
    compute.max(&fbm_trees_image, &scratch_image);
    nodes.math.rerangify(&fbm_trees_image);

    compute.remap(&fbm_trees_image, &scratch_image, 0, 1);

    types.image_preview_f32(fbm_trees_image, &preview_image_generate_trees_fbm);

    ctx.next_nodes.insert(0, generate_trees_points) catch unreachable;
}

pub fn trees_square(ctx: *Context) void {
    std.log.info("Node: trees_square [square]", .{});

    compute.square(&fbm_trees_image, &scratch_image);

    types.image_preview_f32(fbm_trees_image, &preview_image_trees_square);

    ctx.next_nodes.insert(0, generate_trees_points) catch unreachable;
}

pub fn generate_trees_points(ctx: *Context) void {
    std.log.info("Node: generate_trees_points [points_grid]", .{});

    trees_points = types.PatchDataPts2d.create(1, fbm_trees_image.size.width / 128, 100, std.heap.c_allocator);
    nodes.experiments.points_distribution_grid(fbm_trees_image, 0.7, .{ .cell_size = 8, .size = fbm_trees_image.size }, &trees_points);

    ctx.next_nodes.insert(0, output_trees_to_file) catch unreachable;
}

pub fn output_trees_to_file(ctx: *Context) void {
    std.log.info("Node: output_trees_to_file [write_trees]", .{});

    if (!DRY_RUN) {
        nodes.experiments.write_trees(heightmap, trees_points);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn output_heightmap_to_file(ctx: *Context) void {
    std.log.info("Node: output_heightmap_to_file [write_heightmap]", .{});

    if (!DRY_RUN) {
        nodes.heightmap_format.heightmap_format(world_settings, heightmap);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn remap_village_gradient(ctx: *Context) void {
    std.log.info("Node: remap_village_gradient [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 1},
        .{ .x = 0.0003, .y = 0},
    };
    compute.remapCurve(&gradient_image, &curve, &village_gradient);

    types.image_preview_f32(village_gradient, &preview_image_remap_village_gradient);

    ctx.next_nodes.insert(0, downsample_village_gradient) catch unreachable;
}

pub fn downsample_village_gradient(ctx: *Context) void {
    std.log.info("Node: downsample_village_gradient [downsample]", .{});

    const orig_scratch_image_size = scratch_image.size;
    compute.downsample(&village_gradient, &scratch_image, &village_gradient, .min);
    compute.downsample(&village_gradient, &scratch_image, &village_gradient, .min);
    compute.downsample(&village_gradient, &scratch_image, &village_gradient, .min);
    compute.downsample(&village_gradient, &scratch_image, &village_gradient, .min);
    scratch_image.size = orig_scratch_image_size;

    types.image_preview_f32(village_gradient, &preview_image_downsample_village_gradient);

    ctx.next_nodes.insert(0, upsample_village_gradient) catch unreachable;
}

pub fn upsample_village_gradient(ctx: *Context) void {
    std.log.info("Node: upsample_village_gradient [upsample]", .{});

    const orig_scratch_image_size = scratch_image.size;
    compute.upsample(&village_gradient, &scratch_image, &village_gradient, .first);
    compute.upsample(&village_gradient, &scratch_image, &village_gradient, .first);
    compute.upsample(&village_gradient, &scratch_image, &village_gradient, .first);
    compute.upsample(&village_gradient, &scratch_image, &village_gradient, .first);
    scratch_image.size = orig_scratch_image_size;

    types.image_preview_f32(village_gradient, &preview_image_upsample_village_gradient);

    ctx.next_nodes.insert(0, multiply_village_gradient_plains) catch unreachable;
}

pub fn multiply_village_gradient_plains(ctx: *Context) void {
    std.log.info("Node: multiply_village_gradient_plains [math]", .{});

    compute.math_multiply( &village_gradient, &weight_plains, &village_gradient, &scratch_image);

    types.image_preview_f32(village_gradient, &preview_image_multiply_village_gradient_plains);

    ctx.next_nodes.insert(0, multiply_village_gradient_shore) catch unreachable;
}

pub fn multiply_village_gradient_shore(ctx: *Context) void {
    std.log.info("Node: multiply_village_gradient_shore [math]", .{});

    compute.math_multiply( &village_gradient, &weight_shore, &village_gradient, &scratch_image);

    types.image_preview_f32(village_gradient, &preview_image_multiply_village_gradient_shore);

    ctx.next_nodes.insert(0, village_output_points) catch unreachable;
}

pub fn village_output_points(ctx: *Context) void {
    std.log.info("Node: village_output_points [gather_points]", .{});

    compute.gatherPoints(&village_gradient, world_settings.size.width, world_settings.size.height, 0.01, &village_points, &village_points_counter);
    std.log.info("LOL count:{d}", .{village_points_counter.pixels[0]});
    std.log.info("LOL pt:{d},{d}", .{ village_points.pixels[0][0], village_points.pixels[0][1] } );
    std.log.info("LOL pt:{d:.3},{d:.3}", .{ village_points.pixels[0][0], village_points.pixels[0][1] } );

    ctx.next_nodes.insert(0, village_points_filter_proximity) catch unreachable;
}

pub fn village_points_filter_proximity(ctx: *Context) void {
    std.log.info("Node: village_points_filter_proximity [points_filter_proximity]", .{});

    var x = types.BackedListVec2.createFromImageVec2(&village_points, village_points_counter.pixels[0]);
    std.log.info("points_filter_proximity count:{d}", .{x.count} );
    nodes.points.points_filter_proximity_vec2(&x, &x, 7000);
    village_points_counter.pixels[0] = x.count;
    std.log.info("points_filter_proximity count:{d}", .{x.count} );

    // Leaf node
    _ = ctx; // autofix
}

