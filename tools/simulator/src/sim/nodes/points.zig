const std = @import("std");
const types = @import("../types.zig");
const grid = @import("../grid.zig");
const zm = @import("zmath");
const znoise = @import("znoise");
const nodes = @import("nodes.zig");

pub fn points_distribution_grid(filter: types.ImageF32, score_min: f32, grid_settings: grid.Grid, pts_out: *types.PatchDataPts2d) void {
    const cells_x = grid_settings.size.width / grid_settings.cell_size;
    const cells_y = grid_settings.size.height / grid_settings.cell_size;
    var seed: u64 = 123;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;

    const cell_size_f: f32 = @as(f32, @floatFromInt(grid_settings.cell_size));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (0..cells_y) |y| {
        const filter_y = filter.size.height * y / cells_y;
        const patch_y = pts_out.size.height * y / cells_y;
        for (0..cells_x) |x| {
            const filter_x = filter.size.width * x / cells_x;
            const val = filter.get(filter_x, filter_y);
            if (val < score_min) {
                continue;
            }

            const pt_x: f32 = @as(f32, @floatFromInt(filter_x)) + rand.float(f32) * cell_size_f * 0.95;
            const pt_y: f32 = @as(f32, @floatFromInt(filter_y)) + rand.float(f32) * cell_size_f * 0.95;
            const patch_x = pts_out.size.width * x / cells_x;
            pts_out.addToPatch(patch_x, patch_y, .{ pt_x, pt_y });
        }
    }
}

pub fn distance_squared_2d(pt1: [2]f32, pt2: [2]f32) f32 {
    return (pt1[0] - pt2[0]) * (pt1[0] - pt2[0]) + (pt1[1] - pt2[1]) * (pt1[1] - pt2[1]);
}

pub fn points_filter_proximity_vec2(pts_in: *types.BackedList([2]f32), pts_out: *types.BackedList([2]f32), min_distance: f32) void {
    std.debug.assert(pts_in == pts_out); // TODO: Support

    const min_dist_sq = min_distance * min_distance;
    if (pts_in == pts_out) {
        for (pts_in.backed_slice[0..pts_in.count], 0..) |pt1, it1| {
            var it2: usize = it1 + 1;
            while (it2 < pts_in.count) {
                const pt2 = pts_in.backed_slice[it2];
                const dist_sq = distance_squared_2d(pt1, pt2);
                if (dist_sq < min_dist_sq) {
                    pts_in.count -= 1;
                    pts_in.backed_slice[it2] = pts_in.backed_slice[pts_in.count];
                } else {
                    it2 += 1;
                }
            }
        }
    }
}

pub fn points_filter_proximity_f32(pts_in: *const types.BackedList(f32), pts_out: *types.BackedList(f32), min_distance: f32) void {
    std.debug.assert(pts_in == pts_out); // TODO: Support

    const min_dist_sq = min_distance * min_distance;
    if (pts_in == pts_out) {
        var it1: usize = 0;
        while (it1 < pts_out.count) {
            const pt1 = [_]f32{
                pts_out.backed_slice[it1],
                pts_out.backed_slice[it1 + 1],
            };
            it1 += 2;

            var it2: usize = it1 + 2;
            while (it2 < pts_out.count) {
                const pt2 = [_]f32{
                    pts_out.backed_slice[it2],
                    pts_out.backed_slice[it2 + 1],
                };
                const dist_sq = distance_squared_2d(pt1, pt2);
                if (dist_sq < min_dist_sq) {
                    pts_out.count -= 2;
                    pts_out.backed_slice[it2] = pts_out.backed_slice[pts_out.count];
                    pts_out.backed_slice[it2 + 1] = pts_out.backed_slice[pts_out.count + 1];
                } else {
                    it2 += 2;
                }
            }
        }
    }
}
