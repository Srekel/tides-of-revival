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
pub const node_count = 20;

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
var fbm_settings_plains: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.000005,
    .octaves = 5,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var fbm_settings_mountains: nodes.fbm.FbmSettings = nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.0005,
    .octaves = 8,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var voronoi_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap_plains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap_mountains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var weight_plains: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
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

// ============ PREVIEW IMAGES ============
var preview_image_start = types.ImageRGBA.square(preview_size);
var preview_image_exit = types.ImageRGBA.square(preview_size);
var preview_image_generate_poisson_for_voronoi = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_map = types.ImageRGBA.square(preview_size);
var preview_image_generate_landscape_from_image = types.ImageRGBA.square(preview_size);
var preview_image_generate_contours = types.ImageRGBA.square(preview_size);
var preview_image_generate_image_from_voronoi = types.ImageRGBA.square(preview_size);
var preview_image_generate_beaches = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_plains = types.ImageRGBA.square(preview_size);
var preview_image_generate_fbm = types.ImageRGBA.square(preview_size);
var preview_image_fbm_to_heightmap = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_gradient = types.ImageRGBA.square(preview_size);
var preview_image_generate_terrace = types.ImageRGBA.square(preview_size);
var preview_image_generate_water = types.ImageRGBA.square(preview_size);
var preview_image_generate_cities = types.ImageRGBA.square(preview_size);
var preview_image_generate_trees_fbm = types.ImageRGBA.square(preview_size);
var preview_image_trees_square = types.ImageRGBA.square(preview_size);
var preview_image_generate_trees_points = types.ImageRGBA.square(preview_size);
var preview_image_output_trees_to_file = types.ImageRGBA.square(preview_size);
var preview_image_output_heightmap_to_file = types.ImageRGBA.square(preview_size);

// ============ NODES ============
pub fn start(ctx: *Context) void {
    // Initialize vars
    voronoi = std.heap.c_allocator.create(nodes.voronoi.Voronoi) catch unreachable;
    voronoi_points = @TypeOf(voronoi_points).init(std.heap.c_allocator);
    voronoi_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap_plains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap_mountains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_plains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    weight_mountains.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_trees_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    gradient_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    water_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    cities = @TypeOf(cities).initCapacity(std.heap.c_allocator, 100) catch unreachable;

    // Initialize preview images
    preview_image_start.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_exit.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_poisson_for_voronoi.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_map.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_landscape_from_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_contours.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_image_from_voronoi.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_beaches.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_plains.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_fbm.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_fbm_to_heightmap.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_terrace.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_water.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_cities.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_trees_fbm.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_trees_square.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_trees_points.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_trees_to_file.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_output_heightmap_to_file.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;

    ctx.next_nodes.insert(0, generate_poisson_for_voronoi) catch unreachable;
}

pub fn exit(ctx: *Context) void {
    // Unhandled node type: exit

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_poisson_for_voronoi(ctx: *Context) void {
    nodes.poisson.generate_points(world_size, 50, 1, &voronoi_points);

    ctx.next_nodes.insert(0, generate_voronoi_map) catch unreachable;
}

pub fn generate_voronoi_map(ctx: *Context) void {
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
    nodes.voronoi.contours(voronoi);

    ctx.next_nodes.insert(0, generate_beaches) catch unreachable;
    ctx.next_nodes.insert(1, generate_image_from_voronoi) catch unreachable;
}

pub fn generate_image_from_voronoi(ctx: *Context) void {
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

    ctx.next_nodes.insert(0, generate_heightmap_plains) catch unreachable;
}

pub fn generate_beaches(ctx: *Context) void {
    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };

    const downsamples = 3;
    const downsample_divistor = std.math.pow(u32, 2, downsamples);
    const preview_grid = cpp_nodes.generate_landscape_preview(
        &c_voronoi,
        preview_size / downsample_divistor,
        preview_size / downsample_divistor,
    );
    scratch_image.size.width = preview_size / downsample_divistor;
    scratch_image.size.height = preview_size / downsample_divistor;

    nodes.experiments.voronoi_to_water(preview_grid[0 .. preview_size * preview_size], &scratch_image);
    nodes.math.rerangify(&scratch_image);

    types.saveImageF32(scratch_image, "water", false);
    const upsamples = std.math.log2(world_size.width / scratch_image.size.width);
    for (0..upsamples) |i| {
        _ = i; // autofix
        scratch_image2.size.width = scratch_image.size.width * 2;
        scratch_image2.size.height = scratch_image.size.height * 2;
        scratch_image2.zeroClear();
        compute.upsample_blur(&scratch_image, &scratch_image2);
        scratch_image.size.width = scratch_image2.size.width;
        scratch_image.size.height = scratch_image2.size.height;
        scratch_image.swap(&scratch_image2);
        types.saveImageF32(scratch_image, "upblur", false);
    }
    water_image.copy(scratch_image);
    types.saveImageF32(scratch_image, "water", false);

    types.saveImageF32(scratch_image, "generate_beaches", false);
    types.image_preview_f32(scratch_image, &preview_image_generate_beaches);
    const preview_key_generate_beaches = "generate_beaches.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_beaches, .{ .data = preview_image_generate_beaches.asBytes() });

    ctx.next_nodes.insert(0, generate_fbm) catch unreachable;
}

pub fn generate_heightmap_plains(ctx: *Context) void {
    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(heightmap_plains.size.width),
        .height = @intCast(heightmap_plains.size.height),
        .seed = fbm_settings.seed,
        .frequency = fbm_settings.frequency,
        .octaves = fbm_settings.octaves,
        .scale = fbm_settings.scale,
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

    // Leaf node
}

pub fn generate_fbm(ctx: *Context) void {
    const generate_fbm_settings = compute.GenerateFBMSettings{
        .width = @intCast(fbm_image.size.width),
        .height = @intCast(fbm_image.size.height),
        .seed = fbm_settings.seed,
        .frequency = fbm_settings.frequency,
        .octaves = fbm_settings.octaves,
        .scale = fbm_settings.scale,
        ._padding = .{ 0, 0 },
    };

    compute.fbm(&fbm_image, generate_fbm_settings);
    compute.min(&fbm_image, &scratch_image);
    compute.max(&fbm_image, &scratch_image);
    nodes.math.rerangify(&fbm_image);

    compute.remap(&fbm_image, &scratch_image, 0, 1);

    types.saveImageF32(fbm_image, "generate_fbm", false);
    types.image_preview_f32(fbm_image, &preview_image_generate_fbm);
    const preview_key_generate_fbm = "generate_fbm.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_fbm, .{ .data = preview_image_generate_fbm.asBytes() });

    ctx.next_nodes.insert(0, fbm_to_heightmap) catch unreachable;
}

pub fn fbm_to_heightmap(ctx: *Context) void {
    heightmap.copy(fbm_image);
    compute.remap(&heightmap, &scratch_image, 0, world_settings.terrain_height_max);

    types.saveImageF32(heightmap, "fbm_to_heightmap", false);
    types.image_preview_f32(heightmap, &preview_image_fbm_to_heightmap);
    const preview_key_fbm_to_heightmap = "fbm_to_heightmap.image";
    ctx.previews.putAssumeCapacity(preview_key_fbm_to_heightmap, .{ .data = preview_image_fbm_to_heightmap.asBytes() });

    ctx.next_nodes.insert(0, generate_water) catch unreachable;
    ctx.next_nodes.insert(1, generate_heightmap_gradient) catch unreachable;
    ctx.next_nodes.insert(2, output_heightmap_to_file) catch unreachable;
}

pub fn generate_heightmap_gradient(ctx: *Context) void {
    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);

    types.saveImageF32(gradient_image, "generate_heightmap_gradient", false);
    types.image_preview_f32(gradient_image, &preview_image_generate_heightmap_gradient);
    const preview_key_generate_heightmap_gradient = "generate_heightmap_gradient.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_heightmap_gradient, .{ .data = preview_image_generate_heightmap_gradient.asBytes() });

    ctx.next_nodes.insert(0, generate_terrace) catch unreachable;
}

pub fn generate_terrace(ctx: *Context) void {
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
    ctx.next_nodes.insert(1, generate_trees_fbm) catch unreachable;
}

pub fn generate_water(ctx: *Context) void {
    nodes.experiments.water(water_image, &heightmap);

    types.saveImageF32(heightmap, "generate_water", false);
    types.image_preview_f32(heightmap, &preview_image_generate_water);
    const preview_key_generate_water = "generate_water.image";
    ctx.previews.putAssumeCapacity(preview_key_generate_water, .{ .data = preview_image_generate_water.asBytes() });

    // Leaf node
}

pub fn generate_cities(ctx: *Context) void {
    if (!DRY_RUN) {
        nodes.experiments.cities(world_settings, heightmap, gradient_image, &cities);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn generate_trees_fbm(ctx: *Context) void {
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
    compute.square(&fbm_trees_image, &scratch_image);

    types.saveImageF32(fbm_trees_image, "trees_square", false);
    types.image_preview_f32(fbm_trees_image, &preview_image_trees_square);
    const preview_key_trees_square = "trees_square.image";
    ctx.previews.putAssumeCapacity(preview_key_trees_square, .{ .data = preview_image_trees_square.asBytes() });

    ctx.next_nodes.insert(0, generate_trees_points) catch unreachable;
}

pub fn generate_trees_points(ctx: *Context) void {
    trees_points = types.PatchDataPts2d.create(1, fbm_trees_image.size.width / 128, 100, std.heap.c_allocator);
    nodes.experiments.points_distribution_grid(fbm_trees_image, 0.6, .{ .cell_size = 16, .size = fbm_trees_image.size }, &trees_points);

    ctx.next_nodes.insert(0, output_trees_to_file) catch unreachable;
}

pub fn output_trees_to_file(ctx: *Context) void {
    if (!DRY_RUN) {
        nodes.experiments.write_trees(heightmap, trees_points);
    }

    // Leaf node
    _ = ctx; // autofix
}

pub fn output_heightmap_to_file(ctx: *Context) void {
    if (!DRY_RUN) {
        nodes.heightmap_format.heightmap_format(world_settings, heightmap);
    }

    // Leaf node
    _ = ctx; // autofix
}

