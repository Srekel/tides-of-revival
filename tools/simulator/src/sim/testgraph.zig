const std = @import("std");

const graph = @import("graph.zig");
const Context = graph.Context;

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");
const nodes = @import("nodes/nodes.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

// IN
var map_settings: *c_cpp_nodes.MapSettings = undefined;

// OUT
var grid: *c_cpp_nodes.Grid = undefined;

// LOCAL
var voronoi_settings: c_cpp_nodes.VoronoiSettings = undefined;

pub fn start(ctx: *Context) void {
    // INITIALIZE IN
    const name_map_settings = "map";
    map_settings = @ptrCast(@alignCast(ctx.resources.get(name_map_settings)));

    // INITIALIZE OUT
    grid = std.heap.c_allocator.create(c_cpp_nodes.Grid) catch unreachable;

    // INITIALIZE LOCAL
    voronoi_settings.radius = 0.05;
    voronoi_settings.num_relaxations = 10;

    // Start!
    ctx.next_nodes.appendAssumeCapacity(doNode_GenerateVoronoiMap1);
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
    const preview_grid_key = "GenerateVoronoiMap1_grid";
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

    ctx.next_nodes.appendAssumeCapacity(exit);
}
