const std = @import("std");

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");

pub const fn_node = *const fn (context: *Context) void;
pub const fn_node2 = *const fn (context: *Context) void;

pub const Context = struct {
    next_nodes: std.BoundedArray(fn_node2, 16) = .{},
};

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
    map_settings = @ptrCast(ctx.resources.get(name_map_settings));

    // INITIALIZE OUT
    grid = undefined;

    // INITIALIZE LOCAL
    voronoi_settings.radius = 0.05;
    voronoi_settings.num_relaxations = 10;
    ctx.next_nodes.appendAssumeCapacity(doNode_GenerateVoronoiMap1);
}

pub fn exit(ctx: *Context) void {
    const name_grid = "voronoigrid";
    ctx.resources.put(name_grid, &grid);

    // TODO: Dealloc grid?
}

fn doNode_GenerateVoronoiMap1(ctx: *Context) void {
    cpp_nodes.generate_voronoi_map(&map_settings, &voronoi_settings, &grid);
    ctx.next_nodes.appendAssumeCapacity(doNode_generate_landscape_from_image);
}

fn doNode_generate_landscape_from_image(ctx: *Context) void {
    _ = ctx; // autofix
    cpp_nodes.generate_landscape_from_image(&grid, "content/tides_2.0.png");
}
