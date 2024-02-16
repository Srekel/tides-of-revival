const std = @import("std");
const img = @import("zigimg");
const zm = @import("zmath");
const zstbi = @import("zstbi");

const config = @import("../../config/config.zig");
const g = @import("graph.zig");
const lru = @import("../../../core/lru_cache.zig");
const v = @import("../../core/core.zig").variant;
const IdLocal = @import("../../core/core.zig").IdLocal;

const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;

const config_patch_width = 512;

pub fn funcTemplatePatchArtifact(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []const g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patch_type_input = node.getInputByString("Patch Type");
    const patch_type = getInputResult(patch_type_input, context).getHash();

    const folder_input = node.getInputByString("Artifact Folder");
    const folder = getInputResult(folder_input, context).getStringConst(1);

    const artifact_patch_width_input = node.getInputByString("Artifact Patch Width");
    const artifact_patch_width = getInputResult(artifact_patch_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Patches");

    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    var folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "content/patch/{s}",
        .{folder},
    ) catch unreachable;
    std.fs.cwd().makeDir(folderbufslice) catch {};

    // const image_width = artifact_patch_width;
    const precision = 1; // meter
    const best_lod_width = 64; // meter
    const best_lod = 0;
    const worst_lod = 3; // inclusive
    const worst_lod_width = best_lod_width * std.math.pow(u32, 2, worst_lod) / precision;
    const worst_lod_patch_count_per_side = (world_width) / worst_lod_width;
    for (best_lod..worst_lod + 1) |lod| {
        folderbufslice = std.fmt.bufPrintZ(
            folderbuf[0..folderbuf.len],
            "content/patch/{s}/lod{}",
            .{ folder, lod },
        ) catch unreachable;
        std.fs.cwd().makeDir(folderbufslice) catch {};

        const lod_pixel_stride = std.math.pow(usize, 2, lod) / precision;
        const image_bytes_per_component = 1; // @intCast(u32, patch_element_byte_size);
        // const image_bytes_per_component = @intCast(u32, patch_element_byte_size);
        var image = zstbi.Image{
            .data = context.frame_allocator.alloc(u8, artifact_patch_width * artifact_patch_width * 2 * 1) catch unreachable,
            .width = @as(u32, @intCast(artifact_patch_width)),
            .height = @as(u32, @intCast(artifact_patch_width)),
            .num_components = 1,
            .bytes_per_component = image_bytes_per_component,
            .bytes_per_row = image_bytes_per_component * @as(u32, @intCast(artifact_patch_width)),
            .is_hdr = false,
        };
        // defer image.deinit();

        for (0..worst_lod_patch_count_per_side) |hm_patch_z| {
            std.debug.print("Patch artifacts: lod{} row {}/{}\n", .{ lod, hm_patch_z, worst_lod_patch_count_per_side });
            for (0..worst_lod_patch_count_per_side) |hm_patch_x| {
                const patches = patch_blk: {
                    const prevNodeOutput = patches_input.source orelse unreachable;
                    const prevNode = prevNodeOutput.node orelse unreachable;
                    const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                        .{
                            .name = IdLocal.init("world_x"),
                            .value = v.Variant.createUInt64(hm_patch_x * worst_lod_width),
                        },
                        .{
                            .name = IdLocal.init("world_z"),
                            .value = v.Variant.createUInt64(hm_patch_z * worst_lod_width),
                        },
                        .{
                            .name = IdLocal.init("width"),
                            .value = v.Variant.createUInt64(worst_lod_width + 1),
                        },
                        .{
                            .name = IdLocal.init("height"),
                            .value = v.Variant.createUInt64(worst_lod_width + 1),
                        },
                    }));

                    if (res != .success) {
                        unreachable;
                    }

                    // const patches = res.success.getPtr(graph_heightmap.HeightmapOutputData, 1);
                    const patches = res.success.getPtr(graph_util.PatchOutputData(u8), 1);
                    break :patch_blk patches;
                };

                // _ = patches;

                const lod_patch_count_per_side = std.math.pow(usize, 2, worst_lod - lod);
                const lod_patch_width = worst_lod_width / lod_patch_count_per_side;
                for (0..lod_patch_count_per_side) |lod_patch_z| {
                    for (0..lod_patch_count_per_side) |lod_patch_x| {
                        switch (patch_type) {
                            config.patch_type_splatmap.hash => {
                                for (0..artifact_patch_width) |pixel_z| {
                                    for (0..artifact_patch_width) |pixel_x| {
                                        const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride));
                                        const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride));
                                        const img_i = pixel_x + pixel_z * artifact_patch_width;
                                        const value = patches.getValueDynamic(world_x, world_z, u8);
                                        image.data[img_i] = value;
                                    }
                                }

                                const namebufslice = std.fmt.bufPrintZ(
                                    namebuf[0..namebuf.len],
                                    "{s}/{s}_x{}_z{}.png",
                                    .{
                                        folderbufslice,
                                        folder,
                                        hm_patch_x * lod_patch_count_per_side + lod_patch_x,
                                        hm_patch_z * lod_patch_count_per_side + lod_patch_z,
                                    },
                                ) catch unreachable;
                                // std.debug.print("Patch artifacts: image{s} hx{} lx{} imx0:{}\n", .{
                                //     namebufslice,
                                //     hm_patch_x,
                                //     lod_patch_x,
                                //     hm_patch_x * worst_lod_width + lod_patch_z * lod_patch_width + 0 * lod_pixel_stride,
                                // });
                                image.writeToFile(namebufslice, .png) catch unreachable;
                            },
                            config.patch_type_heightmap.hash => {

                                // Calculate range
                                const range = range_blk: {
                                    var max_value: f32 = 0;
                                    var min_value: f32 = std.math.floatMax(f32);
                                    for (0..artifact_patch_width) |pixel_z| {
                                        for (0..artifact_patch_width) |pixel_x| {
                                            const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride));
                                            const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride));
                                            const value = patches.getValueDynamic(world_x, world_z, f32);
                                            min_value = @min(min_value, value);
                                            max_value = @max(max_value, value);
                                        }
                                    }

                                    break :range_blk .{ .min = min_value, .max = max_value };
                                };

                                // TODO: Figure out height_max_mapped_edge
                                // TODO: height_max_mapped_edge should use f64?
                                const range_diff = range.max - range.min;
                                const bitdepth: u8 = if (range_diff < 2000000) 8 else 16;
                                const height_max_mapped_inside: f32 = @floatFromInt(std.math.pow(u32, 2, bitdepth) - 1);
                                const height_max_mapped_edge: f32 = @floatFromInt(std.math.pow(u32, 2, 30));
                                const target_endian = std.builtin.Endian.little;
                                const int_type_edge = u32;

                                const data_size = data_blk: {
                                    const header = @sizeOf(config.HeightmapHeader);
                                    const edge_bytes = @sizeOf(int_type_edge);
                                    switch (bitdepth) {
                                        8 => {
                                            const insides_bytes = @sizeOf(u8);
                                            const edge = edge_bytes * (artifact_patch_width * 2 + (artifact_patch_width) * 2);
                                            const insides = insides_bytes * (artifact_patch_width - 2) * (artifact_patch_width - 2);
                                            const data = header + edge + insides;
                                            break :data_blk data;
                                        },
                                        16 => {
                                            const insides_bytes = @sizeOf(u16);
                                            const edge = edge_bytes * (artifact_patch_width * 2 + (artifact_patch_width) * 2);
                                            const insides = insides_bytes * (artifact_patch_width - 2) * (artifact_patch_width - 2);
                                            const data = header + edge + insides;
                                            break :data_blk data;
                                        },
                                        else => unreachable,
                                    }
                                };
                                var output_blob = std.ArrayList(u8).initCapacity(context.frame_allocator, data_size) catch unreachable;
                                var writer = output_blob.writer();

                                // HEADER
                                const header: config.HeightmapHeader = .{
                                    .version = 1,
                                    .bitdepth = bitdepth,
                                    .height_min = range.min,
                                    .height_max = range.max,
                                };
                                writer.writeStruct(header) catch unreachable;

                                if (range_diff == 0) {
                                    unreachable; // handle?
                                }

                                // EDGES
                                // Top
                                for (0..artifact_patch_width) |edge_index| {
                                    const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + edge_index * lod_pixel_stride));
                                    const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + 0 * lod_pixel_stride));
                                    const value = patches.getValueDynamic(world_x, world_z, f32);
                                    const value_mapped: f32 = zm.mapLinearV(value, config.terrain_min, config.terrain_max, 0, height_max_mapped_edge);
                                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                                }
                                // Bot
                                for (0..artifact_patch_width) |edge_index| {
                                    const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + edge_index * lod_pixel_stride));
                                    const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + (artifact_patch_width - 1) * lod_pixel_stride));
                                    const value = patches.getValueDynamic(world_x, world_z, f32);
                                    const value_mapped: f32 = zm.mapLinearV(value, config.terrain_min, config.terrain_max, 0, height_max_mapped_edge);
                                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                                }
                                // Left (redundant corners)
                                for (0..artifact_patch_width) |edge_index| {
                                    const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + 0 * lod_pixel_stride));
                                    const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + edge_index * lod_pixel_stride));
                                    const value = patches.getValueDynamic(world_x, world_z, f32);
                                    const value_mapped: f32 = zm.mapLinearV(value, config.terrain_min, config.terrain_max, 0, height_max_mapped_edge);
                                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                                }
                                // Right (redundant corners)
                                for (0..artifact_patch_width) |edge_index| {
                                    const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + (artifact_patch_width - 1) * lod_pixel_stride));
                                    const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + edge_index * lod_pixel_stride));
                                    const value = patches.getValueDynamic(world_x, world_z, f32);
                                    const value_mapped: f32 = zm.mapLinearV(value, config.terrain_min, config.terrain_max, 0, height_max_mapped_edge);
                                    const value_int: int_type_edge = @intFromFloat(value_mapped);
                                    writer.writeInt(int_type_edge, value_int, target_endian) catch unreachable;
                                }

                                // INSIDES
                                for (1..artifact_patch_width - 1) |pixel_z| {
                                    for (1..artifact_patch_width - 1) |pixel_x| {
                                        const world_x = @as(i64, @intCast(hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride));
                                        const world_z = @as(i64, @intCast(hm_patch_z * worst_lod_width + lod_patch_z * lod_patch_width + pixel_z * lod_pixel_stride));

                                        const value = patches.getValueDynamic(world_x, world_z, f32);
                                        const value_mapped: f32 = zm.mapLinearV(value, range.min, range.max, 0, height_max_mapped_inside);
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
                                        hm_patch_x * lod_patch_count_per_side + lod_patch_x,
                                        hm_patch_z * lod_patch_count_per_side + lod_patch_z,
                                    },
                                ) catch unreachable;
                                const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
                                defer file.close();
                                _ = file.writeAll(output_blob.items) catch unreachable;
                            },
                            else => unreachable,
                        }
                    }
                }

                // var pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
                // const encoder_options = img.AllFormats.ImageEncoderOptions{ .pgm = pgm_opt };
                // hmimg.writeToFilePath(namebufslice, encoder_options) catch unreachable;
            }
        }
    }

    const res = .{ .success = .{} };
    return res;
}

pub const patchArtifactFunc = g.NodeFuncTemplate{
    .name = IdLocal.init("patchArtifact"),
    .version = 0,
    .func = &funcTemplatePatchArtifact,
    .inputs = ( //
        [_]g.NodeInputTemplate{.{ .name = IdLocal.init("Patches") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Patch Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Patch Type") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Artifact Patch Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Artifact Folder") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 9),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Patch Artifacts") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 15),
};

pub const patchArtifactNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("Patch Artifact"),
    .version = 0,
    .func = patchArtifactFunc,
};
