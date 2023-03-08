const std = @import("std");
const img = @import("zigimg");
const zm = @import("zmath");
const zstbi = @import("zstbi");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const IdLocal = v.IdLocal;

const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;

const config_patch_width = 512;

pub fn funcTemplatePatchArtifact(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patch_element_byte_size_input = node.getInputByString("Patch Element Byte Size");
    const patch_element_byte_size = getInputResult(patch_element_byte_size_input, context).getUInt64();

    const folder_input = node.getInputByString("Artifact Folder");
    const folder = getInputResult(folder_input, context).getStringConst(1);

    const artifact_patch_width_input = node.getInputByString("Artifact Patch Width");
    const artifact_patch_width = getInputResult(artifact_patch_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Patches");

    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    var folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "content/{s}",
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
    var lod: u32 = best_lod;
    while (lod <= worst_lod) : (lod += 1) {
        folderbufslice = std.fmt.bufPrintZ(
            folderbuf[0..folderbuf.len],
            "content/{s}/lod{}",
            .{ folder, lod },
        ) catch unreachable;
        std.fs.cwd().makeDir(folderbufslice) catch {};

        const lod_pixel_stride = std.math.pow(u32, 2, lod) / precision;
        const image_bytes_per_component = 1; // @intCast(u32, patch_element_byte_size);
        // const image_bytes_per_component = @intCast(u32, patch_element_byte_size);
        var image = zstbi.Image{
            .data = context.frame_allocator.alloc(u8, artifact_patch_width * artifact_patch_width * 2 * 1) catch unreachable,
            .width = @intCast(u32, artifact_patch_width),
            .height = @intCast(u32, artifact_patch_width),
            .num_components = 1,
            .bytes_per_component = image_bytes_per_component,
            .bytes_per_row = image_bytes_per_component * @intCast(u32, artifact_patch_width),
            .is_hdr = false,
        };
        // defer image.deinit();

        var hm_patch_y: u32 = 0;
        while (hm_patch_y < worst_lod_patch_count_per_side) : (hm_patch_y += 1) {
            std.debug.print("Patch artifacts: lod{} row {}/{}\n", .{ lod, hm_patch_y, worst_lod_patch_count_per_side });
            var hm_patch_x: u32 = 0;
            while (hm_patch_x < worst_lod_patch_count_per_side) : (hm_patch_x += 1) {
                const patches = patch_blk: {
                    const prevNodeOutput = patches_input.source orelse unreachable;
                    const prevNode = prevNodeOutput.node orelse unreachable;
                    const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                        .{
                            .name = IdLocal.init("world_x"),
                            .value = v.Variant.createUInt64(hm_patch_x * worst_lod_width),
                        },
                        .{
                            .name = IdLocal.init("world_y"),
                            .value = v.Variant.createUInt64(hm_patch_y * worst_lod_width),
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
                    const patches = res.success.getPtr(graph_util.PatchOutputData(u0), 1);
                    break :patch_blk patches;
                };

                // _ = patches;

                const lod_patch_count_per_side = std.math.pow(u32, 2, worst_lod - lod);
                const lod_patch_width = worst_lod_width / lod_patch_count_per_side;
                var lod_patch_y: u32 = 0;
                while (lod_patch_y < lod_patch_count_per_side) : (lod_patch_y += 1) {
                    var lod_patch_x: u32 = 0;
                    while (lod_patch_x < lod_patch_count_per_side) : (lod_patch_x += 1) {
                        const range = range_blk: {
                            var max_value: u16 = 0;
                            var min_value: u16 = std.math.maxInt(u16);
                            _ = switch (patch_element_byte_size) {
                                1 => {
                                    min_value = 0;
                                    max_value = 255;
                                    break :range_blk .{ .min = min_value, .max = max_value };
                                },
                                2 => {
                                    // min_value = 0;
                                    // max_value = std.math.maxInt(u16);
                                    // break :range_blk .{ .min = min_value, .max = max_value };
                                    var pixel_y: u32 = 0;
                                    while (pixel_y < artifact_patch_width) : (pixel_y += 1) {
                                        var pixel_x: u32 = 0;
                                        while (pixel_x < artifact_patch_width) : (pixel_x += 1) {
                                            const world_x = @intCast(i64, hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride);
                                            const world_y = @intCast(i64, hm_patch_y * worst_lod_width + lod_patch_y * lod_patch_width + pixel_y * lod_pixel_stride);
                                            const value = patches.getValueDynamic(world_x, world_y, u16);
                                            min_value = std.math.min(min_value, value);
                                            max_value = std.math.max(max_value, value);
                                        }
                                    }

                                    break :range_blk .{ .min = min_value, .max = max_value };
                                },
                                else => unreachable,
                            };
                        };

                        const range_diff = @intToFloat(f64, range.max - range.min);
                        // const full_range_diff = @intToFloat(f64, std.math.maxInt(u16));

                        var pixel_y: u32 = 0;
                        while (pixel_y < artifact_patch_width) : (pixel_y += 1) {
                            var pixel_x: u32 = 0;
                            while (pixel_x < artifact_patch_width) : (pixel_x += 1) {
                                const world_x = @intCast(i64, hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride);
                                const world_y = @intCast(i64, hm_patch_y * worst_lod_width + lod_patch_y * lod_patch_width + pixel_y * lod_pixel_stride);
                                const img_i = pixel_x + pixel_y * artifact_patch_width;
                                _ = switch (patch_element_byte_size) {
                                    1 => {
                                        const value = patches.getValueDynamic(world_x, world_y, u8);
                                        image.data[img_i] = value;
                                    },
                                    2 => {
                                        const value = patches.getValueDynamic(world_x, world_y, u16);

                                        // TODO: Do range mapping optionally based on parameter
                                        if (range_diff == 0) {
                                            image.data[img_i] = @intCast(u8, 0);
                                            // image.data[img_i + 1] = @intCast(u8, 0);
                                            continue;
                                        }

                                        const value_mapped = @floatToInt(u8, (@intToFloat(f64, (value - range.min)) / range_diff) * 255);
                                        image.data[img_i] = @intCast(u8, value_mapped);
                                        // image.data[img_i] = @intCast(u8, value >> 8);
                                        // image.data[img_i + 1] = @intCast(u8, value & 0xFF);
                                    },
                                    else => unreachable,
                                };
                            }
                        }

                        const namebufslice = std.fmt.bufPrintZ(
                            namebuf[0..namebuf.len],
                            "{s}/heightmap_x{}_y{}.png",
                            .{
                                folderbufslice,
                                hm_patch_x * lod_patch_count_per_side + lod_patch_x,
                                hm_patch_y * lod_patch_count_per_side + lod_patch_y,
                            },
                        ) catch unreachable;
                        // std.debug.print("Patch artifacts: image{s} hx{} lx{} imx0:{}\n", .{
                        //     namebufslice,
                        //     hm_patch_x,
                        //     lod_patch_x,
                        //     hm_patch_x * worst_lod_width + lod_patch_y * lod_patch_width + 0 * lod_pixel_stride,
                        // });
                        image.writeToFile(namebufslice, .png) catch unreachable;

                        if (patch_element_byte_size == 2) {
                            const remap_namebufslice = std.fmt.bufPrintZ(
                                namebuf[0..namebuf.len],
                                "{s}/heightmap_x{}_y{}.txt",
                                .{
                                    folderbufslice,
                                    hm_patch_x * lod_patch_count_per_side + lod_patch_x,
                                    hm_patch_y * lod_patch_count_per_side + lod_patch_y,
                                },
                            ) catch unreachable;
                            const remap_file = std.fs.cwd().createFile(
                                remap_namebufslice,
                                .{ .read = true },
                            ) catch unreachable;
                            defer remap_file.close();

                            const remap_content_slice = std.fmt.bufPrintZ(
                                namebuf[0..namebuf.len],
                                "{},{}",
                                .{
                                    range.min,
                                    range.max,
                                },
                            ) catch unreachable;
                            const bytes_written = remap_file.writeAll(remap_content_slice) catch unreachable;
                            _ = bytes_written;
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
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Patch Element Byte Size") }}) //
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
