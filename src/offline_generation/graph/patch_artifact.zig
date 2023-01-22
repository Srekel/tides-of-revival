const std = @import("std");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const IdLocal = v.IdLocal;

const img = @import("zigimg");
const zm = @import("zmath");
const zstbi = @import("zstbi");

const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;
const Pos = [2]i64;

const config_patch_width = 512;

pub fn funcTemplatePatchArtifact(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const artifact_patch_width_input = node.getInputByString("Artifact Patch Width");
    const artifact_patch_width = getInputResult(artifact_patch_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Heightmap Patches");

    std.fs.cwd().makeDir("content/patch/lod0") catch {};
    std.fs.cwd().makeDir("content/patch/lod1") catch {};
    std.fs.cwd().makeDir("content/patch/lod2") catch {};
    std.fs.cwd().makeDir("content/patch/lod3") catch {};
    var namebuf: [256]u8 = undefined;

    // const image_width = artifact_patch_width;
    const precision = 1; // meter
    const best_lod_width = 64; // meter
    const best_lod = 0;
    const worst_lod = 3; // inclusive
    const worst_lod_width = best_lod_width * std.math.pow(u32, 2, worst_lod) / precision;
    const worst_lod_patch_count_per_side = (world_width) / worst_lod_width;
    var lod: u32 = best_lod;
    while (lod <= worst_lod) : (lod += 1) {
        const lod_pixel_stride = std.math.pow(u32, 2, lod) / precision;
        var image = zstbi.Image{
            .data = context.frame_allocator.alloc(u8, artifact_patch_width * artifact_patch_width * 2 * 1) catch unreachable,
            .width = @intCast(u32, artifact_patch_width),
            .height = @intCast(u32, artifact_patch_width),
            .num_components = 1,
            .bytes_per_component = 2,
            .bytes_per_row = 2 * @intCast(u32, artifact_patch_width),
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

                    const data = res.success.getPtr(graph_heightmap.HeightmapOutputData, 1);
                    break :patch_blk data;
                };

                const lod_patch_count_per_side = std.math.pow(u32, 2, worst_lod - lod);
                const lod_patch_width = worst_lod_width / lod_patch_count_per_side;
                var lod_patch_y: u32 = 0;
                while (lod_patch_y < lod_patch_count_per_side) : (lod_patch_y += 1) {
                    var lod_patch_x: u32 = 0;
                    while (lod_patch_x < lod_patch_count_per_side) : (lod_patch_x += 1) {
                        var pixel_y: u32 = 0;
                        while (pixel_y < artifact_patch_width) : (pixel_y += 1) {
                            var pixel_x: u32 = 0;
                            while (pixel_x < artifact_patch_width) : (pixel_x += 1) {
                                // TODO: Need to be float
                                const world_x = @intCast(i64, hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride);
                                const world_y = @intCast(i64, hm_patch_y * worst_lod_width + lod_patch_y * lod_patch_width + pixel_y * lod_pixel_stride);
                                const height = patches.getHeight(world_x, world_y);
                                const img_i = pixel_x + pixel_y * artifact_patch_width;
                                image.data[img_i] = @intCast(u8, height >> 8);
                                image.data[img_i + 1] = @intCast(u8, height & 0xFF);
                            }
                        }

                        const namebufslice = std.fmt.bufPrintZ(
                            namebuf[0..namebuf.len],
                            "content/patch/lod{}/heightmap_x{}_y{}.png",
                            .{
                                lod,
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
        [_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patch Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Artifact Patch Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patches") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Artifact Patches") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 10),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Patch Artifacts") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 15),
};

pub const patchArtifactNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("Patch Artifact"),
    .version = 0,
    .func = patchArtifactFunc,
};
