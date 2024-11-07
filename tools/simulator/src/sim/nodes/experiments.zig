const std = @import("std");
const types = @import("../types.zig");
const grid = @import("../grid.zig");
const zm = @import("zmath");
const znoise = @import("znoise");
const nodes = @import("nodes.zig");

pub fn cities(world_settings: types.WorldSettings, heightmap: types.ImageF32, gradient: types.ImageF32, cities_out: *std.ArrayList([3]f32)) void {
    _ = world_settings; // autofix
    _ = gradient; // autofix

    // TODO gradient stuff
    for (2..4) |z_div| {
        for (2..4) |x_div| {
            const x = heightmap.size.width / x_div;
            const z = heightmap.size.height / z_div;
            const height = heightmap.get(x, z);
            cities_out.appendAssumeCapacity(.{ @floatFromInt(x), height, @floatFromInt(z) });
        }
    }

    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    const folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/systems",
        .{},
    ) catch unreachable;

    std.fs.cwd().makeDir(folderbufslice) catch {};

    var output_file_data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, cities_out.items.len * 50) catch unreachable;
    var writer = output_file_data.writer();

    for (cities_out.items) |city| {
        // city,1072.000,145.403,1152.000,43
        writer.print("city,{d:.3},{d:.3},{d:.3},{}\n", .{ city[0], city[1], city[2], 0 }) catch unreachable;
    }

    const namebufslice = std.fmt.bufPrintZ(
        namebuf[0..namebuf.len],
        "{s}/cities.txt",
        .{
            folderbufslice,
        },
    ) catch unreachable;
    const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
    defer file.close();
    _ = file.writeAll(output_file_data.items) catch unreachable;
}

pub fn points_distribution_grid(filter: types.ImageF32, score_min: f32, grid_settings: grid.Grid, pts_out: *types.PatchDataPts2d) void {
    const cells_x = grid_settings.size.width / grid_settings.cell_size;
    const cells_y = grid_settings.size.height / grid_settings.cell_size;
    // const cells_x = pts_out.size.width;
    // const cells_y = pts_out.size.height;
    for (0..cells_y) |y| {
        const filter_y = filter.size.height * y / cells_y;
        const patch_y = pts_out.size.height * y / cells_y;
        for (0..cells_x) |x| {
            const filter_x = filter.size.width * x / cells_x;
            const val = filter.get(filter_x, filter_y);
            if (val < score_min) {
                continue;
            }

            const pt_x: f32 = @floatFromInt(filter_x);
            const pt_y: f32 = @floatFromInt(filter_y);
            const patch_x = pts_out.size.width * x / cells_x;
            pts_out.addToPatch(patch_x, patch_y, .{ pt_x, pt_y });
        }
    }
}

pub fn write_trees(heightmap: types.ImageF32, points: types.PatchDataPts2d) void {
    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    const PROPS_LOD = 1;
    _ = PROPS_LOD; // autofix

    const folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/patch/props/lod{}",
        .{points.lod},
    ) catch unreachable;

    std.fs.cwd().makeDir(folderbufslice) catch {};

    for (0..points.size.height) |patch_z| {
        for (0..points.size.width) |patch_x| {
            const namebufslice = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "{s}/props_x{}_z{}.txt",
                .{
                    folderbufslice,
                    patch_x,
                    patch_z,
                },
            ) catch unreachable;

            const props = points.getPatch(patch_x, patch_z);
            if (props.len == 0) {
                std.fs.cwd().deleteFile(namebufslice) catch {};
                continue;
            }

            var output_file_data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, props.len * 50) catch unreachable;
            var writer = output_file_data.writer();

            for (props) |prop| {
                // city,1072.000,145.403,1152.000,43
                const height = heightmap.get(
                    @as(u64, @intFromFloat(@trunc(prop[0]))),
                    @as(u64, @intFromFloat(@trunc(prop[1]))),
                );
                const rot = 0;
                writer.print("tree,{d:.3},{d:.3},{d:.3},{}\n", .{ prop[0], height, prop[1], rot }) catch unreachable;
            }

            const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
            defer file.close();
            _ = file.writeAll(output_file_data.items) catch unreachable;
        }
    }
}

// pub fn voronoi_to_water(voronoi_image: types.ImageRGBA, water_image: *types.ImageF32) void {
pub fn voronoi_to_water(voronoi_image: []u8, water_image: *types.ImageF32) void {
    for (0..water_image.size.height) |y| {
        for (0..water_image.size.width) |x| {
            const voronoi_index = (x + y * water_image.size.width) * 4;
            if (voronoi_image[voronoi_index] == 38) {
                water_image.set(x, y, 1);
            } else if (voronoi_image[voronoi_index] == 255) {
                water_image.set(x, y, 0.5);
            }
        }
    }
}

pub fn water(water_image: types.ImageF32, heightmap: *types.ImageF32) void {
    for (0..water_image.size.height) |y| {
        for (0..water_image.size.width) |x| {
            const height_curr = heightmap.get(x, y);
            const water_curr = water_image.get(x, y);
            heightmap.set(x, y, height_curr * water_curr);
        }
    }
}
