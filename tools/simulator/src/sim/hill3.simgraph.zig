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
pub const node_count = 41;

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
var fbm_settings: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.0005,
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
    .frequency = 0.001,
    .octaves = 4,
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
var village_hills: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var village_gradient: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var village_points: types.ImageVec2 = types.ImageVec2.square(world_settings.size.width);
var village_points_counter: types.ImageU32 = types.ImageU32.square(world_settings.size.width);

// ============ PREVIEW IMAGES ============
var preview_image_start = types.ImageRGBA.square(preview_size);
var preview_image_exit = types.ImageRGBA.square(preview_size);
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
var preview_image_generate_cities = types.ImageRGBA.square(preview_size);
var preview_image_generate_trees_fbm = types.ImageRGBA.square(preview_size);
var preview_image_trees_square = types.ImageRGBA.square(preview_size);
var preview_image_generate_trees_points = types.ImageRGBA.square(preview_size);
var preview_image_output_trees_to_file = types.ImageRGBA.square(preview_size);
var preview_image_output_heightmap_to_file = types.ImageRGBA.square(preview_size);
var preview_image_generate_village_hill_map = types.ImageRGBA.square(preview_size);
var preview_image_generate_village_gradient = types.ImageRGBA.square(preview_size);
var preview_image_remap_village_gradient = types.ImageRGBA.square(preview_size);
var preview_image_downsample_village_gradient = types.ImageRGBA.square(preview_size);
var preview_image_upsample_village_gradient = types.ImageRGBA.square(preview_size);

// ============ NODES ============
pub fn start(ctx: *Context) void {
    std.log.debug("Node: start [start]", .{});

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
    weight_hills.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_mountains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_trees_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    gradient_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    water_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    cities = @TypeOf(cities).initCapacity(std.heap.c_allocator, 100) catch unreachable;
    village_hills.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    village_gradient.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    village_points.pixels = std.heap.c_allocator.alloc([2]f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    village_points_counter.pixels = std.heap.c_allocator.alloc(u32, world_settings.size.width * world_settings.size.height) catch unreachable;

    // Initialize preview images
    preview_image_start.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_exit.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
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
    preview_image_generate_cities.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_trees_fbm.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_trees_square.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_trees_points.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_trees_to_file.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_heightmap_to_file.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_village_hill_map.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_remap_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_downsample_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_upsample_village_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;

    ctx.next_nodes.insert(0, generate_poisson_for_voronoi) catch unreachable;
}

pub fn exit(ctx: *Context) void {
    std.log.debug("Node: exit [exit]", .{});

    // Unhandled node type: exit

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_poisson_for_voronoi(ctx: *Context) void {
    std.log.debug("Node: generate_poisson_for_voronoi [poisson]", .{});

    nodes.poisson.generate_points(world_size, 50, 1, &voronoi_points);

    ctx.next_nodes.insert(0, generate_voronoi_map) catch unreachable;
}

pub fn generate_voronoi_map(ctx: *Context) void {
    std.log.debug("Node: generate_voronoi_map [voronoi]", .{});

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

    ctx.next_nodes.insert(0, generate_landscape_from_image) catch unreachable;
}

pub fn generate_landscape_from_image(ctx: *Context) void {
    std.log.debug("Node: generate_landscape_from_image [landscape_from_image]", .{});

    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };
    cpp_nodes.generate_landscape_from_image(&c_voronoi, "content/tides_2.0.png");

    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);
    const preview_grid_key = "generate_landscape_from_image.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size] });

    ctx.next_nodes.insert(0, generate_contours) catch unreachable;
}

pub fn generate_contours(ctx: *Context) void {
    std.log.debug("Node: generate_contours [contours]", .{});

    nodes.voronoi.contours(voronoi);

    ctx.next_nodes.insert(0, generate_image_from_voronoi) catch unreachable;
    ctx.next_nodes.insert(1, generate_heightmap_gradient) catch unreachable;
    ctx.next_nodes.insert(2, output_heightmap_to_file) catch unreachable;
}

pub fn generate_image_from_voronoi(ctx: *Context) void {
    std.log.debug("Node: generate_image_from_voronoi [image_from_voronoi]", .{});

    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };

    const imagef32_data = cpp_nodes.voronoi_to_imagef32(&c_voronoi, world_settings.size.width, world_settings.size.height);
    voronoi_image.copyPixels(imagef32_data);
    nodes.math.rerangify(&voronoi_image);

    types.saveImageF32(voronoi_image, "generate_image_from_voronoi", false);
    types.image_preview_f32(voronoi_image, &preview_image_generate_image_from_voronoi);
    const preview_key_generate_image_from_voronoi = "generate_image_from_voronoi.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_image_from_voronoi, .{ .data = preview_image_generate_image_from_voronoi.asBytes() });

    ctx.next_nodes.insert(0, generate_heightmap_water) catch unreachable;
    ctx.next_nodes.insert(1, generate_heightmap_plains) catch unreachable;
    ctx.next_nodes.insert(2, generate_heightmap_hills) catch unreachable;
    ctx.next_nodes.insert(3, generate_heightmap_mountains) catch unreachable;
    ctx.next_nodes.insert(4, merge_heightmaps) catch unreachable;
}

pub fn generate_heightmap_water(ctx: *Context) void {
    std.log.debug("Node: generate_heightmap_water [fbm]", .{});

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

    types.saveImageF32(heightmap_water, "generate_heightmap_water", false);
    types.image_preview_f32(heightmap_water, &preview_image_generate_heightmap_water);
    const preview_key_generate_heightmap_water = "generate_heightmap_water.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_heightmap_water, .{ .data = preview_image_generate_heightmap_water.asBytes() });

    ctx.next_nodes.insert(0, generate_voronoi_weight_water) catch unreachable;
}

pub fn generate_voronoi_weight_water(ctx: *Context) void {
    std.log.debug("Node: generate_voronoi_weight_water [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 1},
        .{ .x = 2, .y = 0},
        .{ .x = 3, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_water);

    types.saveImageF32(weight_water, "generate_voronoi_weight_water", false);
    types.image_preview_f32(weight_water, &preview_image_generate_voronoi_weight_water);
    const preview_key_generate_voronoi_weight_water = "generate_voronoi_weight_water.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_voronoi_weight_water, .{ .data = preview_image_generate_voronoi_weight_water.asBytes() });

    ctx.next_nodes.insert(0, blur_weight_water) catch unreachable;
}

pub fn blur_weight_water(ctx: *Context) void {
    std.log.debug("Node: blur_weight_water [blur]", .{});

    compute.blur(&weight_water, &scratch_image, &weight_water);

    types.saveImageF32(weight_water, "blur_weight_water", false);
    types.image_preview_f32(weight_water, &preview_image_blur_weight_water);
    const preview_key_blur_weight_water = "blur_weight_water.image";
    ctx.previews.putAssumeCapacity(preview_key_blur_weight_water, .{ .data = preview_image_blur_weight_water.asBytes() });

    ctx.next_nodes.insert(0, remap_heightmap_water) catch unreachable;
}

pub fn multiply_heightmap_weight_water(ctx: *Context) void {
    std.log.debug("Node: multiply_heightmap_weight_water [math]", .{});

    scratch_image.copy(heightmap_water);
    compute.math_multiply( &scratch_image, &weight_water, &heightmap_water);
    scratch_image.copy(heightmap_water);

    types.saveImageF32(heightmap_water, "multiply_heightmap_weight_water", false);
    types.image_preview_f32(heightmap_water, &preview_image_multiply_heightmap_weight_water);
    const preview_key_multiply_heightmap_weight_water_1 = "multiply_heightmap_weight_water.image";
    ctx.previews.putAssumeCapacity(preview_key_multiply_heightmap_weight_water_1, .{ .data = preview_image_multiply_heightmap_weight_water.asBytes() });

    // Leaf node
}

pub fn remap_heightmap_water(ctx: *Context) void {
    std.log.debug("Node: remap_heightmap_water [remap]", .{});

    compute.remap(&heightmap_water, &scratch_image, 0, 50);

    types.saveImageF32(heightmap_water, "remap_heightmap_water", false);
    types.image_preview_f32(heightmap_water, &preview_image_remap_heightmap_water);
    const preview_key_remap_heightmap_water = "remap_heightmap_water.image";
    ctx.previews.putAssumeCapacity(preview_key_remap_heightmap_water, .{ .data = preview_image_remap_heightmap_water.asBytes() });

    ctx.next_nodes.insert(0, multiply_heightmap_weight_water) catch unreachable;
}

pub fn generate_heightmap_plains(ctx: *Context) void {
    std.log.debug("Node: generate_heightmap_plains [fbm]", .{});

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

    types.saveImageF32(heightmap_plains, "generate_heightmap_plains", false);
    types.image_preview_f32(heightmap_plains, &preview_image_generate_heightmap_plains);
    const preview_key_generate_heightmap_plains = "generate_heightmap_plains.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_heightmap_plains, .{ .data = preview_image_generate_heightmap_plains.asBytes() });

    ctx.next_nodes.insert(0, generate_voronoi_weight_plains) catch unreachable;
}

pub fn generate_voronoi_weight_plains(ctx: *Context) void {
    std.log.debug("Node: generate_voronoi_weight_plains [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 1},
        .{ .x = 3, .y = 1},
        .{ .x = 4, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_plains);

    types.saveImageF32(weight_plains, "generate_voronoi_weight_plains", false);
    types.image_preview_f32(weight_plains, &preview_image_generate_voronoi_weight_plains);
    const preview_key_generate_voronoi_weight_plains = "generate_voronoi_weight_plains.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_voronoi_weight_plains, .{ .data = preview_image_generate_voronoi_weight_plains.asBytes() });

    ctx.next_nodes.insert(0, blur_weight_plains) catch unreachable;
}

pub fn blur_weight_plains(ctx: *Context) void {
    std.log.debug("Node: blur_weight_plains [blur]", .{});

    compute.blur(&weight_plains, &scratch_image, &weight_plains);

    types.saveImageF32(weight_plains, "blur_weight_plains", false);
    types.image_preview_f32(weight_plains, &preview_image_blur_weight_plains);
    const preview_key_blur_weight_plains = "blur_weight_plains.image";
    ctx.previews.putAssumeCapacity(preview_key_blur_weight_plains, .{ .data = preview_image_blur_weight_plains.asBytes() });

    ctx.next_nodes.insert(0, remap_heightmap_plains) catch unreachable;
}

pub fn multiply_heightmap_weight_plains(ctx: *Context) void {
    std.log.debug("Node: multiply_heightmap_weight_plains [math]", .{});

    scratch_image.copy(heightmap_plains);
    compute.math_multiply( &scratch_image, &weight_plains, &heightmap_plains);
    scratch_image.copy(heightmap_plains);

    types.saveImageF32(heightmap_plains, "multiply_heightmap_weight_plains", false);
    types.image_preview_f32(heightmap_plains, &preview_image_multiply_heightmap_weight_plains);
    const preview_key_multiply_heightmap_weight_plains_1 = "multiply_heightmap_weight_plains.image";
    ctx.previews.putAssumeCapacity(preview_key_multiply_heightmap_weight_plains_1, .{ .data = preview_image_multiply_heightmap_weight_plains.asBytes() });

    // Leaf node
}

pub fn remap_heightmap_plains(ctx: *Context) void {
    std.log.debug("Node: remap_heightmap_plains [remap]", .{});

    compute.remap(&heightmap_plains, &scratch_image, 50, 75);

    types.saveImageF32(heightmap_plains, "remap_heightmap_plains", false);
    types.image_preview_f32(heightmap_plains, &preview_image_remap_heightmap_plains);
    const preview_key_remap_heightmap_plains = "remap_heightmap_plains.image";
    ctx.previews.putAssumeCapacity(preview_key_remap_heightmap_plains, .{ .data = preview_image_remap_heightmap_plains.asBytes() });

    ctx.next_nodes.insert(0, multiply_heightmap_weight_plains) catch unreachable;
}

pub fn generate_heightmap_hills(ctx: *Context) void {
    std.log.debug("Node: generate_heightmap_hills [fbm]", .{});

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

    types.saveImageF32(heightmap_hills, "generate_heightmap_hills", false);
    types.image_preview_f32(heightmap_hills, &preview_image_generate_heightmap_hills);
    const preview_key_generate_heightmap_hills = "generate_heightmap_hills.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_heightmap_hills, .{ .data = preview_image_generate_heightmap_hills.asBytes() });

    ctx.next_nodes.insert(0, generate_voronoi_weight_hills) catch unreachable;
}

pub fn generate_voronoi_weight_hills(ctx: *Context) void {
    std.log.debug("Node: generate_voronoi_weight_hills [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 0},
        .{ .x = 3, .y = 0},
        .{ .x = 4, .y = 1},
        .{ .x = 5, .y = 0},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_hills);

    types.saveImageF32(weight_hills, "generate_voronoi_weight_hills", false);
    types.image_preview_f32(weight_hills, &preview_image_generate_voronoi_weight_hills);
    const preview_key_generate_voronoi_weight_hills = "generate_voronoi_weight_hills.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_voronoi_weight_hills, .{ .data = preview_image_generate_voronoi_weight_hills.asBytes() });

    ctx.next_nodes.insert(0, blur_weight_hills) catch unreachable;
}

pub fn blur_weight_hills(ctx: *Context) void {
    std.log.debug("Node: blur_weight_hills [blur]", .{});

    compute.blur(&weight_hills, &scratch_image, &weight_hills);

    types.saveImageF32(weight_hills, "blur_weight_hills", false);
    types.image_preview_f32(weight_hills, &preview_image_blur_weight_hills);
    const preview_key_blur_weight_hills = "blur_weight_hills.image";
    ctx.previews.putAssumeCapacity(preview_key_blur_weight_hills, .{ .data = preview_image_blur_weight_hills.asBytes() });

    ctx.next_nodes.insert(0, remap_heightmap_hills) catch unreachable;
}

pub fn multiply_heightmap_weight_hills(ctx: *Context) void {
    std.log.debug("Node: multiply_heightmap_weight_hills [math]", .{});

    scratch_image.copy(heightmap_hills);
    compute.math_multiply( &scratch_image, &weight_hills, &heightmap_hills);
    scratch_image.copy(heightmap_hills);

    types.saveImageF32(heightmap_hills, "multiply_heightmap_weight_hills", false);
    types.image_preview_f32(heightmap_hills, &preview_image_multiply_heightmap_weight_hills);
    const preview_key_multiply_heightmap_weight_hills_1 = "multiply_heightmap_weight_hills.image";
    ctx.previews.putAssumeCapacity(preview_key_multiply_heightmap_weight_hills_1, .{ .data = preview_image_multiply_heightmap_weight_hills.asBytes() });

    // Leaf node
}

pub fn remap_heightmap_hills(ctx: *Context) void {
    std.log.debug("Node: remap_heightmap_hills [remap]", .{});

    compute.remap(&heightmap_hills, &scratch_image, 100, 250);

    types.saveImageF32(heightmap_hills, "remap_heightmap_hills", false);
    types.image_preview_f32(heightmap_hills, &preview_image_remap_heightmap_hills);
    const preview_key_remap_heightmap_hills = "remap_heightmap_hills.image";
    ctx.previews.putAssumeCapacity(preview_key_remap_heightmap_hills, .{ .data = preview_image_remap_heightmap_hills.asBytes() });

    ctx.next_nodes.insert(0, multiply_heightmap_weight_hills) catch unreachable;
}

pub fn generate_heightmap_mountains(ctx: *Context) void {
    std.log.debug("Node: generate_heightmap_mountains [fbm]", .{});

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

    types.saveImageF32(heightmap_mountains, "generate_heightmap_mountains", false);
    types.image_preview_f32(heightmap_mountains, &preview_image_generate_heightmap_mountains);
    const preview_key_generate_heightmap_mountains = "generate_heightmap_mountains.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_heightmap_mountains, .{ .data = preview_image_generate_heightmap_mountains.asBytes() });

    ctx.next_nodes.insert(0, generate_voronoi_weight_mountains) catch unreachable;
}

pub fn generate_voronoi_weight_mountains(ctx: *Context) void {
    std.log.debug("Node: generate_voronoi_weight_mountains [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 1, .y = 0},
        .{ .x = 2, .y = 0},
        .{ .x = 3, .y = 0},
        .{ .x = 4, .y = 0},
        .{ .x = 5, .y = 1},
    };
    compute.remapCurve(&voronoi_image, &curve, &weight_mountains);

    types.saveImageF32(weight_mountains, "generate_voronoi_weight_mountains", false);
    types.image_preview_f32(weight_mountains, &preview_image_generate_voronoi_weight_mountains);
    const preview_key_generate_voronoi_weight_mountains = "generate_voronoi_weight_mountains.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_voronoi_weight_mountains, .{ .data = preview_image_generate_voronoi_weight_mountains.asBytes() });

    ctx.next_nodes.insert(0, blur_weight_mountains) catch unreachable;
}

pub fn blur_weight_mountains(ctx: *Context) void {
    std.log.debug("Node: blur_weight_mountains [blur]", .{});

    compute.blur(&weight_mountains, &scratch_image, &weight_mountains);

    types.saveImageF32(weight_mountains, "blur_weight_mountains", false);
    types.image_preview_f32(weight_mountains, &preview_image_blur_weight_mountains);
    const preview_key_blur_weight_mountains = "blur_weight_mountains.image";
    ctx.previews.putAssumeCapacity(preview_key_blur_weight_mountains, .{ .data = preview_image_blur_weight_mountains.asBytes() });

    ctx.next_nodes.insert(0, remap_heightmap_mountains) catch unreachable;
}

pub fn multiply_heightmap_weight_mountains(ctx: *Context) void {
    std.log.debug("Node: multiply_heightmap_weight_mountains [math]", .{});

    scratch_image.copy(heightmap_mountains);
    compute.math_multiply( &scratch_image, &weight_mountains, &heightmap_mountains);
    scratch_image.copy(heightmap_mountains);

    types.saveImageF32(heightmap_mountains, "multiply_heightmap_weight_mountains", false);
    types.image_preview_f32(heightmap_mountains, &preview_image_multiply_heightmap_weight_mountains);
    const preview_key_multiply_heightmap_weight_mountains_1 = "multiply_heightmap_weight_mountains.image";
    ctx.previews.putAssumeCapacity(preview_key_multiply_heightmap_weight_mountains_1, .{ .data = preview_image_multiply_heightmap_weight_mountains.asBytes() });

    // Leaf node
}

pub fn remap_heightmap_mountains(ctx: *Context) void {
    std.log.debug("Node: remap_heightmap_mountains [remap]", .{});

    compute.remap(&heightmap_mountains, &scratch_image, 20, 1000);

    types.saveImageF32(heightmap_mountains, "remap_heightmap_mountains", false);
    types.image_preview_f32(heightmap_mountains, &preview_image_remap_heightmap_mountains);
    const preview_key_remap_heightmap_mountains = "remap_heightmap_mountains.image";
    ctx.previews.putAssumeCapacity(preview_key_remap_heightmap_mountains, .{ .data = preview_image_remap_heightmap_mountains.asBytes() });

    ctx.next_nodes.insert(0, multiply_heightmap_weight_mountains) catch unreachable;
}

pub fn merge_heightmaps(ctx: *Context) void {
    std.log.debug("Node: merge_heightmaps [math]", .{});

    scratch_image.copy(heightmap_water);
    compute.math_add( &scratch_image, &heightmap_plains, &heightmap);
    scratch_image.copy(heightmap);

    types.saveImageF32(heightmap, "merge_heightmaps", false);
    types.image_preview_f32(heightmap, &preview_image_merge_heightmaps);
    const preview_key_merge_heightmaps_1 = "merge_heightmaps.image";
    ctx.previews.putAssumeCapacity(preview_key_merge_heightmaps_1, .{ .data = preview_image_merge_heightmaps.asBytes() });
    compute.math_add( &scratch_image, &heightmap_hills, &heightmap);
    scratch_image.copy(heightmap);

    types.saveImageF32(heightmap, "merge_heightmaps", false);
    types.image_preview_f32(heightmap, &preview_image_merge_heightmaps);
    const preview_key_merge_heightmaps_2 = "merge_heightmaps.image";
    ctx.previews.putAssumeCapacity(preview_key_merge_heightmaps_2, .{ .data = preview_image_merge_heightmaps.asBytes() });
    compute.math_add( &scratch_image, &heightmap_mountains, &heightmap);
    scratch_image.copy(heightmap);

    types.saveImageF32(heightmap, "merge_heightmaps", false);
    types.image_preview_f32(heightmap, &preview_image_merge_heightmaps);
    const preview_key_merge_heightmaps_3 = "merge_heightmaps.image";
    ctx.previews.putAssumeCapacity(preview_key_merge_heightmaps_3, .{ .data = preview_image_merge_heightmaps.asBytes() });

    ctx.next_nodes.insert(0, generate_heightmap_gradient) catch unreachable;
}

pub fn generate_heightmap_gradient(ctx: *Context) void {
    std.log.debug("Node: generate_heightmap_gradient [gradient]", .{});

    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);

    types.saveImageF32(gradient_image, "generate_heightmap_gradient", false);
    types.image_preview_f32(gradient_image, &preview_image_generate_heightmap_gradient);
    const preview_key_generate_heightmap_gradient = "generate_heightmap_gradient.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_heightmap_gradient, .{ .data = preview_image_generate_heightmap_gradient.asBytes() });

    ctx.next_nodes.insert(0, generate_terrace) catch unreachable;
}

pub fn generate_terrace(ctx: *Context) void {
    std.log.debug("Node: generate_terrace [terrace]", .{});

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

    types.saveImageF32(heightmap, "generate_terrace", false);
    types.image_preview_f32(heightmap, &preview_image_generate_terrace);
    const preview_key_generate_terrace = "generate_terrace.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_terrace, .{ .data = preview_image_generate_terrace.asBytes() });

    ctx.next_nodes.insert(0, generate_cities) catch unreachable;
    ctx.next_nodes.insert(1, generate_village_hill_map) catch unreachable;
    ctx.next_nodes.insert(2, generate_trees_fbm) catch unreachable;
    ctx.next_nodes.insert(3, output_heightmap_to_file) catch unreachable;
}

pub fn generate_cities(ctx: *Context) void {
    std.log.debug("Node: generate_cities [cities]", .{});

    if (!DRY_RUN) {
        nodes.experiments.cities(world_settings, heightmap, gradient_image, &cities);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_trees_fbm(ctx: *Context) void {
    std.log.debug("Node: generate_trees_fbm [fbm]", .{});

    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(fbm_trees_image.size.width),
        .height = @intCast(fbm_trees_image.size.height),
        .seed = fbm_settings.seed,
        .frequency = fbm_settings.frequency,
        .octaves = fbm_settings.octaves,
        .scale = fbm_settings.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&fbm_trees_image, generate_fbm_settings);
    compute.min(&fbm_trees_image, &scratch_image);
    compute.max(&fbm_trees_image, &scratch_image);
    nodes.math.rerangify(&fbm_trees_image);

    compute.remap(&fbm_trees_image, &scratch_image, 0, 1);

    types.saveImageF32(fbm_trees_image, "generate_trees_fbm", false);
    types.image_preview_f32(fbm_trees_image, &preview_image_generate_trees_fbm);
    const preview_key_generate_trees_fbm = "generate_trees_fbm.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_trees_fbm, .{ .data = preview_image_generate_trees_fbm.asBytes() });

    ctx.next_nodes.insert(0, trees_square) catch unreachable;
}

pub fn trees_square(ctx: *Context) void {
    std.log.debug("Node: trees_square [square]", .{});

    compute.square(&fbm_trees_image, &scratch_image);

    types.saveImageF32(fbm_trees_image, "trees_square", false);
    types.image_preview_f32(fbm_trees_image, &preview_image_trees_square);
    const preview_key_trees_square = "trees_square.image";
    ctx.previews.putAssumeCapacity(preview_key_trees_square, .{ .data = preview_image_trees_square.asBytes() });

    ctx.next_nodes.insert(0, generate_trees_points) catch unreachable;
}

pub fn generate_trees_points(ctx: *Context) void {
    std.log.debug("Node: generate_trees_points [points_grid]", .{});

    trees_points = types.PatchDataPts2d.create(1, fbm_trees_image.size.width / 128, 100, std.heap.c_allocator);
    nodes.experiments.points_distribution_grid(fbm_trees_image, 0.6, .{ .cell_size = 16, .size = fbm_trees_image.size }, &trees_points);

    ctx.next_nodes.insert(0, output_trees_to_file) catch unreachable;
}

pub fn output_trees_to_file(ctx: *Context) void {
    std.log.debug("Node: output_trees_to_file [write_trees]", .{});

    if (!DRY_RUN) {
        nodes.experiments.write_trees(heightmap, trees_points);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn output_heightmap_to_file(ctx: *Context) void {
    std.log.debug("Node: output_heightmap_to_file [write_heightmap]", .{});

    if (!DRY_RUN) {
        nodes.heightmap_format.heightmap_format(world_settings, heightmap);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_village_hill_map(ctx: *Context) void {
    std.log.debug("Node: generate_village_hill_map [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 0},
        .{ .x = 140, .y = 0},
        .{ .x = 150, .y = 1},
        .{ .x = 250, .y = 1},
        .{ .x = 260, .y = 0},
    };
    compute.remapCurve(&heightmap, &curve, &village_hills);

    types.saveImageF32(village_hills, "generate_village_hill_map", false);
    types.image_preview_f32(village_hills, &preview_image_generate_village_hill_map);
    const preview_key_generate_village_hill_map = "generate_village_hill_map.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_village_hill_map, .{ .data = preview_image_generate_village_hill_map.asBytes() });

    ctx.next_nodes.insert(0, generate_village_gradient) catch unreachable;
}

pub fn generate_village_gradient(ctx: *Context) void {
    std.log.debug("Node: generate_village_gradient [gradient]", .{});

    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &village_gradient);

    types.saveImageF32(village_gradient, "generate_village_gradient", false);
    types.image_preview_f32(village_gradient, &preview_image_generate_village_gradient);
    const preview_key_generate_village_gradient = "generate_village_gradient.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_village_gradient, .{ .data = preview_image_generate_village_gradient.asBytes() });

    ctx.next_nodes.insert(0, remap_village_gradient) catch unreachable;
}

pub fn remap_village_gradient(ctx: *Context) void {
    std.log.debug("Node: remap_village_gradient [remap_curve]", .{});

    const curve = [_]types.Vec2{
        .{ .x = 0, .y = 1},
        .{ .x = 0.001, .y = 0},
    };
    compute.remapCurve(&village_gradient, &curve, &village_gradient);

    types.saveImageF32(village_gradient, "remap_village_gradient", false);
    types.image_preview_f32(village_gradient, &preview_image_remap_village_gradient);
    const preview_key_remap_village_gradient = "remap_village_gradient.image";
    ctx.previews.putAssumeCapacity(preview_key_remap_village_gradient, .{ .data = preview_image_remap_village_gradient.asBytes() });

    ctx.next_nodes.insert(0, downsample_village_gradient) catch unreachable;
}

pub fn downsample_village_gradient(ctx: *Context) void {
    std.log.debug("Node: downsample_village_gradient [downsample]", .{});

    const orig_scratch_image_size = scratch_image.size;
    compute.downsample(&village_gradient, &scratch_image, &village_gradient, .min);
    compute.downsample(&village_gradient, &scratch_image, &village_gradient, .min);
    scratch_image.size = orig_scratch_image_size;

    types.saveImageF32(village_gradient, "downsample_village_gradient", false);
    types.image_preview_f32(village_gradient, &preview_image_downsample_village_gradient);
    const preview_key_downsample_village_gradient = "downsample_village_gradient.image";
    ctx.previews.putAssumeCapacity(preview_key_downsample_village_gradient, .{ .data = preview_image_downsample_village_gradient.asBytes() });

    ctx.next_nodes.insert(0, upsample_village_gradient) catch unreachable;
}

pub fn upsample_village_gradient(ctx: *Context) void {
    std.log.debug("Node: upsample_village_gradient [upsample]", .{});

    const orig_scratch_image_size = scratch_image.size;
    compute.upsample(&village_gradient, &scratch_image, &village_gradient, .first);
    compute.upsample(&village_gradient, &scratch_image, &village_gradient, .first);
    scratch_image.size = orig_scratch_image_size;

    types.saveImageF32(village_gradient, "upsample_village_gradient", false);
    types.image_preview_f32(village_gradient, &preview_image_upsample_village_gradient);
    const preview_key_upsample_village_gradient = "upsample_village_gradient.image";
    ctx.previews.putAssumeCapacity(preview_key_upsample_village_gradient, .{ .data = preview_image_upsample_village_gradient.asBytes() });

    // Leaf node
}

