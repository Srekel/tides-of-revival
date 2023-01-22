const std = @import("std");
const img = @import("zigimg");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const IdLocal = v.IdLocal;

const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;
const Pos = [2]i64;

const config_patch_width = 512;

//  ██████╗██╗████████╗██╗   ██╗
// ██╔════╝██║╚══██╔══╝╚██╗ ██╔╝
// ██║     ██║   ██║    ╚████╔╝
// ██║     ██║   ██║     ╚██╔╝
// ╚██████╗██║   ██║      ██║
//  ╚═════╝╚═╝   ╚═╝      ╚═╝

pub fn funcTemplateCity(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const City = struct {
        pos: Pos,
        border_pos: std.ArrayList(Pos),
        is_border: std.ArrayList(bool),
    };

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Heightmap Patches");

    var cities = std.ArrayList(City).init(context.frame_allocator);

    const CITY_WIDTH_MAX = 256;
    const CITY_MARGIN_EDGE = CITY_WIDTH_MAX * 2;
    const CITY_MARGIN_CITY = CITY_WIDTH_MAX * 6;
    const CITY_SKIP = 64;
    const CITY_HEIGHT_TEST_SKIP = 16;

    var world_y: i64 = CITY_MARGIN_EDGE;
    while (world_y < world_width - CITY_MARGIN_EDGE) : (world_y += CITY_SKIP) {
        var world_x: i64 = CITY_MARGIN_EDGE;
        x_loop: while (world_x < world_width - CITY_MARGIN_EDGE) : (world_x += CITY_SKIP) {
            for (cities.items) |city| {
                const city_diff_x = std.math.absInt(city.pos[0] - world_x) catch unreachable;
                const city_diff_y = std.math.absInt(city.pos[1] - world_y) catch unreachable;
                if (city_diff_x + city_diff_y - @intCast(i64, (city.border_pos.items.len - 15) * 1) < CITY_MARGIN_CITY) {
                    continue :x_loop;
                }
            }

            const patches = patch_blk: {
                const prevNodeOutput = patches_input.source orelse unreachable;
                const prevNode = prevNodeOutput.node orelse unreachable;
                const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                    .{
                        .name = IdLocal.init("world_x"),
                        .value = v.Variant.createUInt64(world_x - CITY_WIDTH_MAX),
                    },
                    .{
                        .name = IdLocal.init("world_y"),
                        .value = v.Variant.createUInt64(world_y - CITY_WIDTH_MAX),
                    },
                    .{
                        .name = IdLocal.init("width"),
                        .value = v.Variant.createUInt64(CITY_WIDTH_MAX * 2),
                    },
                    .{
                        .name = IdLocal.init("height"),
                        .value = v.Variant.createUInt64(CITY_WIDTH_MAX * 2),
                    },
                }));

                if (res != .success) {
                    unreachable;
                }

                const data = res.success.getPtr(HeightmapOutputData, 1);
                break :patch_blk data;
            };

            const height_center = patches.getHeight(world_x, world_y);
            if (height_center < 90 * 255 or height_center > 200 * 255) {
                continue;
            }

            var city: City = .{
                .pos = .{ world_x, world_y },
                .border_pos = std.ArrayList(Pos).init(context.frame_allocator),
                .is_border = std.ArrayList(bool).init(context.frame_allocator),
            };

            var stack_index: u64 = 0;
            city.border_pos.append(city.pos) catch unreachable;
            city.is_border.append(false) catch unreachable;
            // city_blk:
            while (stack_index < city.border_pos.items.len) {
                const pos_curr = city.border_pos.items[stack_index];
                const height_curr = patches.getHeightI(pos_curr[0], pos_curr[1]);
                stack_index += 1;

                const posNSWE = [_]Pos{
                    .{
                        pos_curr[0],
                        pos_curr[1] + CITY_HEIGHT_TEST_SKIP,
                    },
                    .{
                        pos_curr[0],
                        pos_curr[1] - CITY_HEIGHT_TEST_SKIP,
                    },
                    .{
                        pos_curr[0] - CITY_HEIGHT_TEST_SKIP,
                        pos_curr[1],
                    },
                    .{
                        pos_curr[0] + CITY_HEIGHT_TEST_SKIP,
                        pos_curr[1],
                    },
                };

                // const pos_curr_diff_x = std.math.absInt(city.pos[0] - pos_curr[0]) catch unreachable;
                // const pos_curr_diff_y = std.math.absInt(city.pos[1] - pos_curr[1]) catch unreachable;
                const max_slope_center = 200;
                const max_slope_edge = 50;
                nswe_blk: for (posNSWE) |pos| {
                    const pos_diff_x = std.math.absInt(city.pos[0] - pos[0]) catch unreachable;
                    const pos_diff_y = std.math.absInt(city.pos[1] - pos[1]) catch unreachable;
                    if (pos_diff_x >= CITY_WIDTH_MAX or pos_diff_y >= CITY_WIDTH_MAX) {
                        continue;
                    }

                    const height_side = patches.getHeightI(pos[0], pos[1]);
                    const height_diff_i = std.math.absInt(height_side - height_curr) catch unreachable;
                    const height_diff = @intToFloat(f32, height_diff_i);
                    // if (height_diff > CITY_HEIGHT_TEST_SKIP / 2) {
                    // const pos_curr_diff_x = std.math.absInt(pos_curr[0] - pos[0]) catch unreachable;
                    // const pos_curr_diff_y = std.math.absInt(pos_curr[1] - pos[1]) catch unreachable;
                    const dist = pos_diff_x + pos_diff_y;
                    var slope_height_diff = max_slope_center + (max_slope_edge - max_slope_center) * @intToFloat(f32, dist) / CITY_WIDTH_MAX;
                    if (stack_index < 4) {
                        slope_height_diff *= 0.02;
                    }
                    // const slope_height_diff = max_slope_center + @divFloor((max_slope_edge - max_slope_center) * dist, CITY_WIDTH_MAX);
                    if (height_diff > slope_height_diff) {
                        city.is_border.items[stack_index - 1] = true;
                        // std.debug.print("LOLsi: {}, height_curr:{}, height_side:{}, max_slope_center: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, max_slope_center, height_diff_i, slope_height_diff });
                        continue;
                        // continue :city_blk;
                    }

                    // if (stack_index < 3) {
                    //     std.debug.print("si: {}, height_curr:{}, height_side:{}, height_diff: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, height_diff, height_diff_i, slope_height_diff });
                    // }

                    if (height_side < 90 * 255 or height_side > 200 * 255) {
                        // std.debug.print("WTFsi: {}, height_curr:{}, height_side:{}, height_diff: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, height_diff, height_diff_i, slope_height_diff });
                        continue;
                    }

                    for (city.border_pos.items) |bp| {
                        if (bp[0] == pos[0] and bp[1] == pos[1]) {
                            // std.debug.print("WTFFFsi: {}, height_curr:{}, height_side:{}, height_diff: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, height_diff, height_diff_i, slope_height_diff });
                            continue :nswe_blk;
                        }
                    }

                    city.border_pos.append(pos) catch unreachable;
                    city.is_border.append(false) catch unreachable;
                }
            }

            if (city.border_pos.items.len > 15) {
                cities.append(city) catch unreachable;
                std.debug.print("city: pos{any}, len{}\n", .{ city.pos, city.border_pos.items.len });
            }
        }
    }

    for (cities.items) |city| {
        for (city.border_pos.items) |pos_curr, i| {
            const posNSWE = [_]Pos{
                .{
                    pos_curr[0],
                    pos_curr[1] + CITY_HEIGHT_TEST_SKIP,
                },
                .{
                    pos_curr[0],
                    pos_curr[1] - CITY_HEIGHT_TEST_SKIP,
                },
                .{
                    pos_curr[0] - CITY_HEIGHT_TEST_SKIP,
                    pos_curr[1],
                },
                .{
                    pos_curr[0] + CITY_HEIGHT_TEST_SKIP,
                    pos_curr[1],
                },
            };

            var count: u64 = 0;
            for (posNSWE) |pos| {
                for (city.border_pos.items) |bp| {
                    if (bp[0] == pos[0] and bp[1] == pos[1]) {
                        count += 1;
                        break;
                    }
                }
            }

            city.is_border.items[i] = count < 4;
        }
    }

    if (node.output_artifacts) {
        std.debug.print("city: outputting artifact...\n", .{});

        const patch_width = config_patch_width;
        const image_width = 4096;
        const stride = @intCast(i64, @divExact(world_width, image_width));
        const hmimg = img.Image.create(context.frame_allocator, image_width, image_width, img.PixelFormat.rgba32) catch unreachable;
        const pixels = hmimg.pixels.rgba32;
        var pixels_index: u64 = 0;

        world_y = 0;
        const patch_width_i = @intCast(i64, patch_width);
        while (world_y < world_width - patch_width + 1) : (world_y += patch_width_i) {
            std.debug.print("..{}\n", .{world_y});
            var world_x: i64 = 0;
            while (world_x < world_width - patch_width + 1) : (world_x += patch_width_i) {
                const patches = patch_blk: {
                    const prevNodeOutput = patches_input.source orelse unreachable;
                    const prevNode = prevNodeOutput.node orelse unreachable;
                    const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                        .{
                            .name = IdLocal.init("world_x"),
                            .value = v.Variant.createUInt64(world_x),
                        },
                        .{
                            .name = IdLocal.init("world_y"),
                            .value = v.Variant.createUInt64(world_y),
                        },
                        .{
                            .name = IdLocal.init("width"),
                            .value = v.Variant.createUInt64(patch_width),
                        },
                        .{
                            .name = IdLocal.init("height"),
                            .value = v.Variant.createUInt64(patch_width),
                        },
                    }));

                    if (res != .success) {
                        unreachable;
                    }

                    const data = res.success.getPtr(HeightmapOutputData, 1);
                    break :patch_blk data;
                };

                const p2 = patches;
                std.debug.assert(p2.count == 1);

                // const world_width_i = @intCast(i64, world_width);
                var world_patch_y: i64 = 0;
                while (world_patch_y < patch_width) : (world_patch_y += stride) {
                    var world_patch_x: i64 = 0;
                    while (world_patch_x < patch_width) : (world_patch_x += stride) {
                        pixels_index = @intCast(u64, @divFloor(world_x + world_patch_x, stride) + @divFloor((world_y + world_patch_y) * image_width, stride));
                        const height = @intCast(u8, patches.getHeight(world_x + world_patch_x, world_y + world_patch_y) / 255);
                        pixels[pixels_index].r = height;
                        pixels[pixels_index].g = height;
                        pixels[pixels_index].b = height;
                        pixels[pixels_index].a = 255;
                        if (height < 80) {
                            pixels[pixels_index].r = 50 + height / 2;
                            pixels[pixels_index].g = 50 + height / 2;
                            pixels[pixels_index].b = 90 + height * 2;
                        } else if (height > 200) {
                            pixels[pixels_index].r = 140 + (height - 200) * 2;
                            pixels[pixels_index].g = 140 + (height - 200) * 2;
                            pixels[pixels_index].b = 140 + (height - 200) * 2;
                        } else {
                            pixels[pixels_index].r = 20 + height / 2;
                            pixels[pixels_index].g = 50 + height / 2;
                            pixels[pixels_index].b = 20 + height / 2;
                        }

                        if (@intCast(u64, (world_x + world_patch_x)) % (patch_width * 4) < 32 or @intCast(u64, (world_y + world_patch_y)) % (patch_width * 4) < 32) {
                            pixels[pixels_index].r -= 5;
                            pixels[pixels_index].g -= 5;
                            pixels[pixels_index].b -= 5;
                        } else if (@intCast(u64, (world_x + world_patch_x)) % patch_width < 4 or @intCast(u64, (world_y + world_patch_y)) % patch_width < 4) {
                            pixels[pixels_index].r -= 5;
                            pixels[pixels_index].g -= 5;
                            pixels[pixels_index].b -= 5;
                        }
                    }
                }
            }
        }

        std.debug.print("..cities\n", .{});
        for (cities.items) |city| {
            std.debug.print("....city pos:{any} size:{}\n", .{ city.pos, city.border_pos.items.len });
            for (city.border_pos.items) |pos, i| {
                const is_border = city.is_border.items[i];
                var city_y: i64 = 0;
                while (city_y < CITY_HEIGHT_TEST_SKIP) : (city_y += stride) {
                    var city_x: i64 = 0;
                    while (city_x < CITY_HEIGHT_TEST_SKIP) : (city_x += stride) {
                        pixels_index = @intCast(u64, @divFloor(pos[0] + city_x, stride) + @divFloor((pos[1] + city_y) * image_width, stride));
                        // pixels_index = @intCast(u64, @divFloor(pos[0], stride) + @divFloor((pos[1] + 0) * image_width, stride));
                        // const height = patches.getHeight(pos[0],pos[1]);
                        const height = pixels[pixels_index].r;
                        const add = std.math.min(100, 255 - height);
                        const sub = std.math.min(add, std.math.min(20, pixels[pixels_index].b));
                        pixels[pixels_index].r += if (is_border) add else add / 2;
                        // pixels[pixels_index].R = pixels[pixels_index].R / 2;
                        pixels[pixels_index].g -= sub;
                        pixels[pixels_index].b -= sub;
                    }
                }
            }
        }
        // const hm = output_data.patches[0];
        // _ = hm;
        // _ = hmimg;
        // for (heightmap) |pixel, i| {
        //     hmimg.pixels.?.Grayscale8[i].value = pixel;
        // }

        std.debug.print("..writing image {}\n", .{image_width});

        var namebuf: [256]u8 = undefined;
        const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "citymap_{}_{}.qoi", .{ world_width, image_width }) catch unreachable;

        var enc_opt: img.AllFormats.QOI.EncoderOptions = .{ .colorspace = .linear };
        const encoder_options = img.AllFormats.ImageEncoderOptions{ .qoi = enc_opt };
        hmimg.writeToFilePath(namebufslice, encoder_options) catch unreachable;
    }

    const res = .{ .success = .{} };
    return res;
}

// ███╗   ███╗ █████╗ ██╗███╗   ██╗
// ████╗ ████║██╔══██╗██║████╗  ██║
// ██╔████╔██║███████║██║██╔██╗ ██║
// ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
// ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const cityFunc = g.NodeFuncTemplate{
    .name = IdLocal.init("city"),
    .version = 0,
    .func = &funcTemplateCity,
    .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patches") }}) //
        ++
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 13),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Cities") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 15),
};

pub const cityNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("City"),
    .version = 0,
    .func = cityFunc,
};
