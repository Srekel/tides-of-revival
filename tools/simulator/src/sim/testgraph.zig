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

const world_settings: types.WorldSettings = .{
    .size = .{ .width = 16 * 1024, .height = 16 * 1024 },
};

// IN
var map_settings: *c_cpp_nodes.MapSettings = undefined;

// OUT
var grid: *c_cpp_nodes.Grid = undefined;
var heightmap: types.ImageF32 = types.ImageF32.square(world_settings.size.width);

// LOCAL
var voronoi_settings: c_cpp_nodes.VoronoiSettings = undefined;
var fbm_settings = nodes.fbm.FbmSettings{
    .frequency = 0.00025,
    .octaves = 8,
    .rect = types.Rect.createOriginSquare(world_settings.size.width),
};
var fbm_image: types.ImageF32 = types.ImageF32.square(world_settings.size.width);

pub fn start(ctx: *Context) void {
    // INITIALIZE IN
    const name_map_settings = "map";
    map_settings = @ptrCast(@alignCast(ctx.resources.get(name_map_settings)));

    // INITIALIZE OUT
    grid = std.heap.c_allocator.create(c_cpp_nodes.Grid) catch unreachable;
    fbm_image.pixels = std.heap.c_allocator.alloc(f32, world_settings.size.width * world_settings.size.height) catch unreachable;
    preview_fbm_image.pixels = std.heap.c_allocator.alloc(types.ColorRGBA, 512 * 512) catch unreachable;

    // INITIALIZE LOCAL
    voronoi_settings.radius = 0.05;
    voronoi_settings.num_relaxations = 10;

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

fn doNode_beaches(ctx: *Context) void {
    nodes.voronoiContours(grid);

    const preview_grid = cpp_nodes.generate_landscape_preview(grid, 512, 512);
    const preview_grid_key = "beaches.grid";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_grid[0 .. 512 * 512 * 4] });

    ctx.next_nodes.appendAssumeCapacity(doNode_fbm);
}

var preview_fbm_image = types.ImageRGBA.square(512);
fn doNode_fbm(ctx: *Context) void {
    nodes.fbm.fbm(&fbm_settings, &fbm_image);

    types.image_preview_f32(fbm_image, &preview_fbm_image);
    const preview_grid_key = "fbm.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_fbm_image.asBytes() });

    ctx.next_nodes.appendAssumeCapacity(doNode_heightmap);
}

fn doNode_heightmap(ctx: *Context) void {
    heightmap.copy(fbm_image, std.heap.c_allocator);

    const preview_grid_key = "heightmap.image";
    ctx.previews.putAssumeCapacity(preview_grid_key, .{ .data = preview_fbm_image.asBytes() });

    ctx.next_nodes.appendAssumeCapacity(doNode_heightmap_file);
}

fn doNode_heightmap_file(ctx: *Context) void {
    nodes.heightmap_format.heightmap_format(world_settings, heightmap);
    // var output_greyscale = types.ImageGreyscale.square(512);
    // output_greyscale.pixels = std.heap.c_allocator.alloc(u8, 512 * 512) catch unreachable;
    // types.image_preview_f32_greyscale(heightmap, &output_greyscale);
    // io.writeFile(output_greyscale.pixels, "../lol.heightmap");

    ctx.next_nodes.appendAssumeCapacity(exit);
}
