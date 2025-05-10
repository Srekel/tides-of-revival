const std = @import("std");

const io = @import("../io.zig");
const graph = @import("graph.zig");
const Context = graph.Context;

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");
const nodes = @import("nodes/nodes.zig");
const types = @import("types.zig");
const compute = @import("compute.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

const DRY_RUN = true;
const kilometers = if (DRY_RUN) 2 else 16;
const preview_size = 512;

pub const node_count = 5;
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

const world_size: types.Size2D = .{ .width = kilometers * 1024, .height = kilometers * 1024 };
const world_settings: types.WorldSettings = .{
    .size = world_size,
};

// IN

// OUT
var voronoi: *nodes.voronoi.Voronoi = undefined;
var heightmap: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap2: types.ImageF32 = types.ImageF32.square(world_settings.size.width);

// LOCAL
var voronoi_points: std.ArrayList(types.Vec2) = undefined;
var voronoi_settings: nodes.voronoi.VoronoiSettings = undefined;
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
var scratch_image2: types.ImageF32 = types.ImageF32.square(world_settings.size.width); // HACK
var water_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var cities: std.ArrayList([3]f32) = undefined;

var fbm_trees_settings = nodes.fbm.FbmSettings{
    .seed = 123,
    .frequency = 0.005,
    .octaves = 7,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 1,
};
var fbm_trees_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);

pub fn start(ctx: *Context) void {
    // INITIALIZE IN
    // const name_map_settings = "map";
    // map_settings = @ptrCast(@alignCast(ctx.resources.get(name_map_settings)));

    // INITIALIZE OUT
    voronoi = std.heap.c_allocator.create(nodes.voronoi.Voronoi) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_trees_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    gradient_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    water_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    preview_fbm_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * 2 * preview_size * 2) catch unreachable;
    preview_fbm_trees_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_heightmap_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_heightmap2_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_gradient_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;

    // INITIALIZE LOCAL
    voronoi_settings.seed = 0;
    voronoi_settings.size = world_size.width;
    voronoi_settings.radius = 1;
    voronoi_settings.num_relaxations = 5;
    cities = @TypeOf(cities).initCapacity(std.heap.c_allocator, 100) catch unreachable;

    voronoi_points = @TypeOf(voronoi_points).init(std.heap.c_allocator);

    // Start!
    ctx.next_nodes.append(doNode_GenerateVoronoiMap) catch unreachable;
    // ctx.next_nodes.insert(0, doNode_fbm) catch unreachable;
}

pub fn exit(ctx: *Context) void {
    _ = ctx; // autofix
    const name_grid = "voronoigrid";
    _ = name_grid; // autofix
    // ctx.resources.put(name_grid, &voronoi);

    // ctx.next_nodes.insert(0, heightmap_output.start) catch unreachable;
}

fn doNode_GenerateVoronoiMap(ctx: *Context) void {
    voronoi.* = .{
        .diagram = .{},
        .cells = std.ArrayList(nodes.voronoi.VoronoiCell).init(std.heap.c_allocator),
    };

    nodes.poisson.generate_points(world_size, 50, 1, &voronoi_points);
    nodes.voronoi.generate_voronoi_map(voronoi_settings, voronoi_points.items, voronoi);

    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };
    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);
    const preview_grid_key = "GenerateVoronoiMap1.voronoi";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size * 4] });

    ctx.next_nodes.insert(0, doNode_generate_landscape_from_image) catch unreachable;
}

fn doNode_generate_landscape_from_image(ctx: *Context) void {
    var c_voronoi = c_cpp_nodes.Voronoi{
        .voronoi_grid = voronoi.diagram,
        .voronoi_cells = @ptrCast(voronoi.cells.items.ptr),
    };

    cpp_nodes.generate_landscape_from_image(&c_voronoi, "content/tides_2.0.png");

    const preview_grid = cpp_nodes.generate_landscape_preview(&c_voronoi, preview_size, preview_size);
    const preview_grid_key = "generate_landscape_from_image.voronoi";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size * 4] });

    ctx.next_nodes.insert(0, doNode_beaches) catch unreachable;
}

fn doNode_beaches(ctx: *Context) void {
    nodes.voronoi.contours(voronoi);

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
    // const preview_grid_key = "beaches.voronoi";
    // ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size * 4] });

    scratch_image.size.width = preview_size / downsample_divistor;
    scratch_image.size.height = preview_size / downsample_divistor;

    nodes.experiments.voronoi_to_water(preview_grid[0 .. preview_size * preview_size], &scratch_image);

    // types.image_preview_f32(water_image, &preview_fbm_image);
    // const preview_grid_key2 = "beaches.voronoi";
    // ctx.previews.putAssumeCapacity(preview_grid_key2, .{ .data = preview_fbm_image.asBytes() });

    // const downsamples = 1;
    // for (0..downsamples) |i| {
    //     _ = i; // autofix
    //     scratch_image2.size.width = scratch_image.size.width / 2;
    //     scratch_image2.size.height = scratch_image.size.height / 2;
    //     compute.downsample(&scratch_image, &scratch_image2);
    //     scratch_image.size.width = scratch_image2.size.width;
    //     scratch_image.size.height = scratch_image2.size.height;
    //     scratch_image.swap(&scratch_image2);
    // }

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

    types.image_preview_f32(scratch_image, &preview_fbm_image);
    const preview_grid_key3 = "beaches2.voronoi";
    ctx.previews.putAssumeCapacity(preview_grid_key3, .{ .data = preview_fbm_image.asBytes() });

    ctx.next_nodes.insert(0, doNode_fbm) catch unreachable;
}

var preview_fbm_image = types.ImageRGBA.square(preview_size * 2);
fn doNode_fbm(ctx: *Context) void {
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

    types.image_preview_f32(fbm_image, &preview_fbm_image);
    const preview_grid_key = "fbm.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_fbm_image.asBytes() });

    ctx.next_nodes.insert(0, doNode_heightmap) catch unreachable;
}

var preview_heightmap_image = types.ImageRGBA.square(preview_size);
var preview_heightmap2_image = types.ImageRGBA.square(preview_size);
fn doNode_heightmap(ctx: *Context) void {
    heightmap.copy(fbm_image);
    heightmap.remap(0, world_settings.terrain_height_max);

    types.image_preview_f32(heightmap, &preview_heightmap_image);
    const preview_key = "heightmap.image";
    ctx.previews.putAssumeCapacity(preview_key, .{ .data = preview_heightmap_image.asBytes() });

    ctx.next_nodes.insert(0, doNode_water) catch unreachable;
    ctx.next_nodes.insert(1, doNode_gradient) catch unreachable;
    ctx.next_nodes.insert(2, doNode_heightmap_file) catch unreachable;
}

var preview_gradient_image = types.ImageRGBA.square(preview_size);
fn doNode_gradient(ctx: *Context) void {
    // compute.gradient(&heightmap, &gradient_image, 1 / world_settings.terrain_height_max);
    // compute.min(&gradient_image, &scratch_image);
    // compute.max(&gradient_image, &scratch_image);

    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);
    // nodes.math.rerangify(&gradient_image);
    // nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);
    // gradient_image.height_min = 0;

    types.image_preview_f32(gradient_image, &preview_gradient_image);
    const preview_grid_key = "gradient.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_gradient_image.asBytes() });

    heightmap2.copy(heightmap);
    types.saveImageF32(gradient_image, "gradient_image_b4terrace", false);
    types.saveImageF32(heightmap, "heightmap_b4terrace", false);
    for (0..1) |_| {
        for (0..1) |_| {
            // nodes.gradient.terrace(heightmap, gradient_image, &heightmap2, &scratch_image);
            // heightmap.swap(&heightmap2);
            compute.terrace(&gradient_image, &heightmap, &scratch_image);
            // compute.min(&heightmap, &scratch_image);
            // compute.max(&heightmap, &scratch_image);
            nodes.math.rerangify(&heightmap);
            types.saveImageF32(heightmap, "heightmap", false);
        }
        // compute.gradient(&heightmap, &gradient_image, 1 / world_settings.terrain_height_max);
        // compute.min(&gradient_image, &scratch_image);
        // compute.max(&gradient_image, &scratch_image);
        // nodes.math.rerangify(&g);
    }

    types.image_preview_f32(heightmap, &preview_heightmap2_image);
    const preview_key2 = "heightmap_terraced.image";
    ctx.previews.putAssumeCapacity(preview_key2, .{ .data = preview_heightmap2_image.asBytes() });

    ctx.next_nodes.insert(0, doNode_cities) catch unreachable;
    ctx.next_nodes.insert(1, doNode_fbm_trees) catch unreachable;
}

fn doNode_water(ctx: *Context) void {
    nodes.experiments.water(water_image, &heightmap);

    types.image_preview_f32(heightmap, &preview_heightmap2_image);
    const preview_key2 = "heightmap_waterify.image";
    ctx.previews.putAssumeCapacity(preview_key2, .{ .data = preview_heightmap2_image.asBytes() });
}

var preview_cities_image = types.ImageRGBA.square(preview_size);
fn doNode_cities(ctx: *Context) void {
    _ = ctx; // autofix
    if (!DRY_RUN) {
        nodes.experiments.cities(world_settings, heightmap, gradient_image, &cities);
    }

    // preview_cities_image.copy(preview_heightmap_image);
    // types.image_preview_f32(cities_image, &preview_cities_image);
    // const preview_grid_key = "cities.image";
    // ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_cities_image.asBytes() });
}

var preview_fbm_trees_image = types.ImageRGBA.square(preview_size);
fn doNode_fbm_trees(ctx: *Context) void {
    // CPU FBM
    // nodes.fbm.fbm(&fbm_trees_settings, &fbm_trees_image);

    // GPU FBM
    {
        const generate_fbm_settings = compute.GenerateFBMSettings{
            .width = @intCast(fbm_trees_image.size.width),
            .height = @intCast(fbm_trees_image.size.height),
            .seed = fbm_settings.seed,
            .frequency = fbm_trees_settings.frequency,
            .octaves = fbm_trees_settings.octaves,
            .scale = fbm_trees_settings.scale,
            ._padding = .{ 0, 0 },
        };

        compute.fbm(&fbm_trees_image, generate_fbm_settings);
        compute.min(&fbm_trees_image, &scratch_image);
        compute.max(&fbm_trees_image, &scratch_image);
        nodes.math.rerangify(&fbm_trees_image);
    }

    compute.remap(&fbm_trees_image, &scratch_image, 0, 1);

    compute.square(&fbm_trees_image, &scratch_image);

    types.image_preview_f32(fbm_trees_image, &preview_fbm_trees_image);
    const preview_grid_key = "fbm_trees.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_fbm_trees_image.asBytes() });

    ctx.next_nodes.insert(0, doNode_trees) catch unreachable;
}

var preview_trees_image = types.ImageRGBA.square(preview_size);
fn doNode_trees(ctx: *Context) void {
    _ = ctx; // autofix
    var trees = types.PatchDataPts2d.create(1, fbm_trees_image.size.width / 128, 100, std.heap.c_allocator);
    nodes.experiments.points_distribution_grid(fbm_trees_image, 0.6, .{ .cell_size = 16, .size = fbm_trees_image.size }, &trees);
    if (!DRY_RUN) {
        nodes.experiments.write_trees(heightmap, trees);
    }
}

fn doNode_heightmap_file(ctx: *Context) void {
    _ = ctx; // autofix
    if (!DRY_RUN) {
        nodes.heightmap_format.heightmap_format(world_settings, heightmap);
    }
}
