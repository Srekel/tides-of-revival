const std = @import("std");
const types = @import("../types.zig");
const zm = @import("zmath");

pub const FbmSettings = struct {
    octaves: u8,
    frequency: f32,
    rect: types.Rect,
    // resolution_inv: u32,
};

pub fn heightmap_format(world_settings: types.WorldSettings, heightmap: types.ImageF32) void {
    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;
    const folder = "heightmap";

    var folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/patch/heightmap",
        .{},
    ) catch unreachable;

    const patch_resolution = world_settings.patch_resolution; // 65

    std.fs.cwd().makeDir(folderbufslice) catch {};
    const precision = 1; // meter
    const best_lod_width = 64; // meter
    const best_lod = 0;
    const worst_lod = 3; // inclusive
    const worst_lod_width = best_lod_width * std.math.pow(u32, 2, worst_lod) / precision; // 64*8 = 512m
    for (best_lod..worst_lod + 1) |lod| {
        folderbufslice = std.fmt.bufPrintZ(
            folderbuf[0..folderbuf.len],
            "../../../../content/patch/{s}/lod{}",
            .{ folder, lod },
        ) catch unreachable;
        std.fs.cwd().makeDir(folderbufslice) catch {};

        const lod_pixel_stride = std.math.pow(usize, 2, lod) / precision;

        const lod_patch_count_per_side = std.math.pow(usize, 2, worst_lod - lod); // 8 -> 1
        const lod_patch_width = worst_lod_width / lod_patch_count_per_side; // 64 -> 512
        for (0..lod_patch_count_per_side) |lod_patch_z| {
            for (0..lod_patch_count_per_side) |lod_patch_x| {

                // Calculate range
                var range_max: f32 = 0;
                var range_min: f32 = std.math.floatMax(f32);
                for (0..patch_resolution) |pixel_z| {
                    for (0..patch_resolution) |pixel_x| {
                        const world_x = lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride;
                        const world_z = lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride;
                        const value = heightmap.get(world_x, world_z);
                        range_min = @min(range_min, value);
                        range_max = @max(range_max, value);
                    }
                }

                // TODO: Figure out height_max_mapped_edge
                // TODO: height_max_mapped_edge should use f64?
                const range_diff = range_max - range_min;
                const bitdepth: u8 = if (range_diff < 2000000) 8 else 16;
                const height_max_mapped_inside: f32 = @floatFromInt(std.math.pow(u32, 2, bitdepth) - 1);
                const height_max_mapped_edge: f32 = @floatFromInt(std.math.pow(u32, 2, 30));
                const target_endian = std.builtin.Endian.little;
                const int_type_edge = u32;

                const header_bytes = @sizeOf(HeightmapHeader);
                const edge_bytes = @sizeOf(int_type_edge) * (patch_resolution * 2 + (patch_resolution) * 2);
                const insides = (bitdepth / 8) * (patch_resolution - 2) * (patch_resolution - 2);
                const total_bytes = header_bytes + edge_bytes + insides;
                var output_blob = std.ArrayList(u8).initCapacity(std.heap.c_allocator, total_bytes) catch unreachable;
                var writer = output_blob.writer();

                // HEADER
                const header: HeightmapHeader = .{
                    .version = 1,
                    .bitdepth = bitdepth,
                    .height_min = range_min,
                    .height_max = range_max,
                };
                writer.writeStruct(header) catch unreachable;

                if (range_diff == 0) {
                    unreachable; // TODO handle
                }

                // EDGES
                // Top
                for (0..patch_resolution) |pixel_x| {
                    const pixel_z = 0;
                    const world_x = lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride;
                    const world_z = lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride;
                    const value = heightmap.get(world_x, world_z);
                    const value_mapped: f32 = zm.mapLinearV(value, world_settings.terrain_height_min, world_settings.terrain_height_max, 0, height_max_mapped_edge);
                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                }
                // Bot
                for (0..patch_resolution) |pixel_x| {
                    const pixel_z = patch_resolution - 1;
                    const world_x = lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride;
                    const world_z = lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride;
                    const value = heightmap.get(world_x, world_z);
                    const value_mapped: f32 = zm.mapLinearV(value, world_settings.terrain_height_min, world_settings.terrain_height_max, 0, height_max_mapped_edge);
                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                }
                // Left (redundant corners)
                for (0..patch_resolution) |pixel_z| {
                    const pixel_x = 0;
                    const world_x = lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride;
                    const world_z = lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride;
                    const value = heightmap.get(world_x, world_z);
                    const value_mapped: f32 = zm.mapLinearV(value, world_settings.terrain_height_min, world_settings.terrain_height_max, 0, height_max_mapped_edge);
                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                }
                // Right (redundant corners)
                for (0..patch_resolution) |pixel_z| {
                    const pixel_x = patch_resolution - 1;
                    const world_x = lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride;
                    const world_z = lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride;
                    const value = heightmap.get(world_x, world_z);
                    const value_mapped: f32 = zm.mapLinearV(value, world_settings.terrain_height_min, world_settings.terrain_height_max, 0, height_max_mapped_edge);
                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                }

                // INSIDES
                for (1..patch_resolution - 1) |pixel_z| {
                    for (1..patch_resolution - 1) |pixel_x| {
                        const world_x = lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride;
                        const world_z = lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride;

                        const value = heightmap.get(world_x, world_z);
                        const value_mapped: f32 = zm.mapLinearV(value, range_min, range_max, 0, height_max_mapped_inside);
                        switch (bitdepth) {
                            8 => {
                                const value_int: u8 = @intFromFloat(value_mapped);
                                writer.writeInt(u8, value_int, target_endian) catch unreachable;
                            },
                            16 => {
                                const value_int: u16 = @intFromFloat(value_mapped);
                                writer.writeInt(u16, value_int, target_endian) catch unreachable;
                            },
                            else => unreachable,
                        }
                    }
                }

                std.debug.assert(output_blob.capacity == output_blob.items.len);

                const namebufslice = std.fmt.bufPrintZ(
                    namebuf[0..namebuf.len],
                    "{s}/{s}_x{}_z{}.heightmap",
                    .{
                        folderbufslice,
                        folder,
                        lod_patch_x,
                        lod_patch_z,
                    },
                ) catch unreachable;
                const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
                defer file.close();
                _ = file.writeAll(output_blob.items) catch unreachable;
            }
        }
    }
}

// HACK
pub const HeightmapHeader = packed struct {
    version: u8,
    bitdepth: u8,
    height_min: f32,
    height_max: f32,
};

// pub const HeightmapHeader = extern struct {
//     version: u8,
//     bitdepth: u8,
//     _padding: u16 = 0,
//     height_min: f32,
//     height_max: f32,
//     identifier: [8]u8 = .{'A'} ** 8,
// };
