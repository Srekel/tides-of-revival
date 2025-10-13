const std = @import("std");
const assert = std.debug.assert;
const types = @import("../types.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

const jcv_diagram = c_cpp_nodes.jcv_diagram;
const jcv_diagram_ = c_cpp_nodes.jcv_diagram_;
const jcv_point = c_cpp_nodes.jcv_point;
const jcv_real = c_cpp_nodes.jcv_real;
const jcv_rect = c_cpp_nodes.jcv_rect;
const jcv_site_ = c_cpp_nodes.jcv_site_;
const jcv_diagram_free = c_cpp_nodes.jcv_diagram_free;
const jcv_diagram_get_sites = c_cpp_nodes.jcv_diagram_get_sites;
const jcv_diagram_generate = c_cpp_nodes.jcv_diagram_generate;

// TODO: Unhardcode this
pub const VoronoiCellType = enum(u32) {
    NONE = 0,
    WATER = 1,
    SHORE = 2,
    LAND = 3,
    MOUNTAIN = 4,
};

pub const VoronoiCell = extern struct {
    cell_type: VoronoiCellType = .NONE,
    noise_value: f32 = 0,
    site: ?*jcv_site_ = null,
};

pub const VoronoiSettings = struct {
    size: f32,
    seed: i32,
    radius: f32,
    num_relaxations: i32,
};

pub const Voronoi = struct {
    diagram: jcv_diagram_, // read-only
    cells: std.ArrayList(VoronoiCell), // read-write
};

pub fn generate_voronoi_map(voronoi_settings: VoronoiSettings, points: []types.Vec2, voronoi: *Voronoi) void {
    assert(points.len > 0);
    const bounding_box = jcv_rect{
        .min = .{ .x = 0.0, .y = 0.0 },
        .max = .{ .x = voronoi_settings.size, .y = voronoi_settings.size },
    };

    // Relax points
    for (0..@intCast(voronoi_settings.num_relaxations)) |_| {
        var diagram: jcv_diagram = .{};
        jcv_diagram_generate(@intCast(points.len), @ptrCast(points.ptr), &bounding_box, 0, &diagram);
        relax_points(&diagram, points);
        jcv_diagram_free(&diagram);
    }

    // Generate voronoi diagram
    voronoi.diagram = .{};
    jcv_diagram_generate(@intCast(points.len), @ptrCast(points.ptr), &bounding_box, 0, &voronoi.diagram);

    assert(voronoi.diagram.numsites > 0);
    voronoi.cells.resize(0) catch unreachable;
    voronoi.cells.ensureTotalCapacity(@intCast(voronoi.diagram.numsites)) catch unreachable;
    // voronoi.cells.resize(@intCast(voronoi.diagram.numsites)) catch unreachable;
    // @memset(std.mem.sliceAsBytes(voronoi.cells), 0);
    voronoi.cells.appendNTimesAssumeCapacity(.{}, @intCast(voronoi.diagram.numsites));
}

pub fn contours(voronoi: *Voronoi) void {
    const sites = c_cpp_nodes.jcv_diagram_get_sites(&voronoi.diagram);
    for (0..@intCast(voronoi.diagram.numsites)) |i| {
        const site = &sites[i];
        var cell = &voronoi.cells.items[@intCast(site.index)];
        if (cell.cell_type == .WATER) {
            var edge = site.edges;
            while (edge != null) {
                if (edge.*.neighbor != null) {
                    const cell_index = edge.*.neighbor.*.index;
                    const neighbor = &voronoi.cells.items[@intCast(cell_index)];
                    if (neighbor.cell_type == .LAND) {
                        cell.cell_type = .SHORE;
                        break;
                    }
                }

                edge = edge.*.next;
            }
        }
    }
}

pub fn relax_points(diagram: *jcv_diagram, points: []types.Vec2) void {
    const sites = jcv_diagram_get_sites(diagram);
    for (0..@intCast(diagram.*.numsites)) |i| {
        const site = &sites[i];
        var sum = site.p;
        var count: jcv_real = 1;

        var edge = site.edges;

        while (edge != null) {
            sum.x += edge.*.pos[0].x;
            sum.y += edge.*.pos[0].y;
            count += 1;
            edge = edge.*.next;
        }

        points[@intCast(site.index)].x = sum.x / count;
        points[@intCast(site.index)].y = sum.y / count;
    }
}
