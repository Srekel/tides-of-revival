const  std = @import("std");
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
const DRY_RUN = false;
const kilometers = if (DRY_RUN) 2 else 16;
const preview_size = 512;
const preview_size_big = preview_size * 2;
pub const node_count = 11;

// ============ VARS ============
const world_size : types.Size2D = .{ .width = 2 * 1024, .height = 2 * 1024 };
const world_settings : types.WorldSettings = .{ .size = world_size };
var voronoi : *nodes.voronoi.Voronoi = undefined;
var voronoi_points : std.ArrayList(types.Vec2) = undefined;
var voronoi_settings : nodes.voronoi.VoronoiSettings =  nodes.voronoi.VoronoiSettings{
    .seed = 0,
    .size = world_size.width,
    .radius = 1,
    .num_relaxations = 5,
};
var fbm_settings : nodes.fbm.FbmSettings =  nodes.fbm.FbmSettings{
    .seed = 1,
    .frequency = 0.00025,
    .octaves = 8,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
    .scale = 0.5,
};
var heightmap : types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var heightmap2 : types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var fbm_image : types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var gradient_image : types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var scratch_image : types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var scratch_image2 : types.ImageF32 = types.ImageF32.square(world_settings.size.width);
var water_image : types.ImageF32 = types.ImageF32.square(world_settings.size.width);

// ============ PREVIEW IMAGES ============
var preview_image_start = types.ImageRGBA.square(preview_size);
var preview_image_exit = types.ImageRGBA.square(preview_size);
var preview_image_generate_poisson_for_voronoi = types.ImageRGBA.square(preview_size);
var preview_image_generate_voronoi_map = types.ImageRGBA.square(preview_size);
var preview_image_generate_landscape_from_image = types.ImageRGBA.square(preview_size);
var preview_image_generate_contours = types.ImageRGBA.square(preview_size);
var preview_image_generate_beaches = types.ImageRGBA.square(preview_size);
var preview_image_generate_fbm = types.ImageRGBA.square(preview_size);
var preview_image_fbm_to_heightmap = types.ImageRGBA.square(preview_size);
var preview_image_generate_heightmap_gradient = types.ImageRGBA.square(preview_size);
var preview_image_generate_terrace = types.ImageRGBA.square(preview_size);

// ============ NODES ============
pub fn start(ctx: *Context) void {
    // Initialize vars
    voronoi = std.heap.c_allocator.create(nodes.voronoi.Voronoi) catch unreachable;
    voronoi_points = @TypeOf(voronoi_points).init(std.heap.c_allocator);
    heightmap.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    heightmap2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    gradient_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    scratch_image2.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    water_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;

    // Initialize preview images
    preview_image_start.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_exit.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_poisson_for_voronoi.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_voronoi_map.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_landscape_from_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_contours.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_beaches.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_fbm.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_fbm_to_heightmap.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_heightmap_gradient.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;
    preview_image_generate_terrace.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, preview_size * preview_size) catch unreachable;

    ctx.next_nodes.insert(0, generate_poisson_for_voronoi) catch unreachable;
}

pub fn exit(ctx: *Context) void {

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
    const preview_grid_key = "generate_voronoi_map.voronoi";
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
    const preview_grid_key = "generate_landscape_from_image.voronoi";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. preview_size * preview_size] });

    ctx.next_nodes.insert(0, generate_contours) catch unreachable;
}

pub fn generate_contours(ctx: *Context) void {
    nodes.voronoi.contours(voronoi);

    ctx.next_nodes.insert(0, generate_beaches) catch unreachable;
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
    types.image_preview_f32(scratch_image, &preview_image_generate_beaches);
    const preview_grid_key = "generate_beaches.voronoi";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_image_generate_beaches.asBytes() });

    ctx.next_nodes.insert(0, generate_fbm) catch unreachable;
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
    
    types.image_preview_f32(fbm_image, &preview_image_generate_fbm);
    const preview_grid_key = "generate_fbm.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_image_generate_fbm.asBytes() });

    ctx.next_nodes.insert(0, fbm_to_heightmap) catch unreachable;
}

pub fn fbm_to_heightmap(ctx: *Context) void {
    heightmap.copy(fbm_image);
    heightmap.remap(0, world_settings.terrain_height_max);
    
    types.image_preview_f32(heightmap, &preview_image_fbm_to_heightmap);
    const preview_key = "fbm_to_heightmap.image";
    ctx.previews.putAssumeCapacity(preview_key, .{ .data = preview_image_fbm_to_heightmap.asBytes() });

    ctx.next_nodes.insert(0, generate_heightmap_gradient) catch unreachable;
    ctx.next_nodes.insert(1, generate_heightmap_gradient) catch unreachable;
}

pub fn generate_heightmap_gradient(ctx: *Context) void {
    nodes.gradient.gradient(heightmap, 1 / world_settings.terrain_height_max, &gradient_image);
    
    types.image_preview_f32(gradient_image, &preview_image_generate_heightmap_gradient);
    const preview_grid_key = "generate_heightmap_gradient.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_image_generate_heightmap_gradient.asBytes() });

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
    
    types.image_preview_f32(heightmap, &preview_image_generate_terrace);
    const preview_key = "generate_terrace.image";
    ctx.previews.putAssumeCapacity(preview_key, .{ .data = preview_image_generate_terrace.asBytes() });

    // Leaf node
}

