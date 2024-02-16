const std = @import("std");
const img = @import("zigimg");
const zm = @import("zmath");

const g = @import("graph.zig");
const lru = @import("../../../core/lru_cache.zig");
const v = @import("../../core/core.zig").variant;
const IdLocal = @import("../../core/core.zig").IdLocal;

const graph_heightmap = @import("heightmap.zig");
const graph_props = @import("props.zig");
const graph_util = @import("util.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;
const Pos = [3]f32;

const config_patch_width = 512;

pub const City = struct {
    pos: Pos,
    border_pos: std.ArrayList(Pos),
    is_border: std.ArrayList(bool),
};

pub const CityOutputData = struct {
    cities: std.ArrayList(City),
};

//  ██████╗██╗████████╗██╗   ██╗
// ██╔════╝██║╚══██╔══╝╚██╗ ██╔╝
// ██║     ██║   ██║    ╚████╔╝
// ██║     ██║   ██║     ╚██╔╝
// ╚██████╗██║   ██║      ██║
//  ╚═════╝╚═╝   ╚═╝      ╚═╝

pub fn funcTemplateCity(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []const g.NodeFuncParam) g.NodeFuncResult {
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Heightmap Patches");

    var cities = std.ArrayList(City).init(context.frame_allocator);

    const CITY_WIDTH_MAX = 64;
    const CITY_MARGIN_EDGE = CITY_WIDTH_MAX * 16;
    const CITY_MARGIN_CITY = CITY_WIDTH_MAX * 16;
    const CITY_SKIP = 16;
    const CITY_HEIGHT_TEST_SKIP = 16;
    const CITY_MIN_BORDERS = 15;

    var world_z: i64 = CITY_MARGIN_EDGE;
    while (world_z < world_width - CITY_MARGIN_EDGE) : (world_z += CITY_SKIP) {
        var world_x: i64 = CITY_MARGIN_EDGE;
        x_loop: while (world_x < world_width - CITY_MARGIN_EDGE) : (world_x += CITY_SKIP) {
            const world_x_f = @as(f32, @floatFromInt(world_x));
            const world_z_f = @as(f32, @floatFromInt(world_z));
            for (cities.items) |city| {
                const city_diff_x = @abs(city.pos[0] - world_x_f);
                const city_diff_z = @abs(city.pos[2] - world_z_f);
                if (city_diff_x + city_diff_z - @as(f32, @floatFromInt((city.border_pos.items.len - CITY_MIN_BORDERS) * 1)) < CITY_MARGIN_CITY) {
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
                        .name = IdLocal.init("world_z"),
                        .value = v.Variant.createUInt64(world_z - CITY_WIDTH_MAX),
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

            const world_y = patches.getHeightWorld(world_x, world_z);
            if (world_y < 50 or world_y > 200) {
                continue;
            }

            var city: City = .{
                .pos = .{ world_x_f, world_y, world_z_f },
                .border_pos = std.ArrayList(Pos).init(context.frame_allocator),
                .is_border = std.ArrayList(bool).init(context.frame_allocator),
            };

            var stack_index: u64 = 0;
            city.border_pos.append(city.pos) catch unreachable;
            city.is_border.append(false) catch unreachable;
            // city_blk:
            while (stack_index < city.border_pos.items.len) {
                const pos_curr = city.border_pos.items[stack_index];
                const height_curr = patches.getHeightWorld(pos_curr[0], pos_curr[2]);
                stack_index += 1;

                const posNSWE = [_]Pos{
                    .{
                        pos_curr[0],
                        0,
                        pos_curr[2] + CITY_HEIGHT_TEST_SKIP,
                    },
                    .{
                        pos_curr[0],
                        0,
                        pos_curr[2] - CITY_HEIGHT_TEST_SKIP,
                    },
                    .{
                        pos_curr[0] - CITY_HEIGHT_TEST_SKIP,
                        0,
                        pos_curr[2],
                    },
                    .{
                        pos_curr[0] + CITY_HEIGHT_TEST_SKIP,
                        0,
                        pos_curr[2],
                    },
                };

                // const pos_curr_diff_x = std.math.absInt(city.pos[0] - pos_curr[0]) catch unreachable;
                // const pos_curr_diff_z = std.math.absInt(city.pos[2] - pos_curr[2]) catch unreachable;
                const max_slope_center = 10;
                const max_slope_edge = 3;
                nswe_blk: for (posNSWE) |pos| {
                    const pos_diff_x = @abs(city.pos[0] - pos[0]);
                    const pos_diff_z = @abs(city.pos[2] - pos[2]);
                    if (pos_diff_x >= CITY_WIDTH_MAX or pos_diff_z >= CITY_WIDTH_MAX) {
                        continue;
                    }

                    const height_side = patches.getHeightWorld(
                        @as(i32, @intFromFloat(pos[0])),
                        @as(i32, @intFromFloat(pos[2])),
                    );
                    const height_diff = @abs(height_side - height_curr);
                    // const height_diff = @floatFromInt(f32, height_diff_i);
                    // if (height_diff > CITY_HEIGHT_TEST_SKIP / 2) {
                    // const pos_curr_diff_x = std.math.absInt(pos_curr[0] - pos[0]) catch unreachable;
                    // const pos_curr_diff_z = std.math.absInt(pos_curr[2] - pos[2]) catch unreachable;
                    const dist = pos_diff_x + pos_diff_z;
                    var slope_height_diff = max_slope_center + (max_slope_edge - max_slope_center) * dist / CITY_WIDTH_MAX;
                    if (stack_index < 4) {
                        slope_height_diff *= 0.02;
                    }
                    // const slope_height_diff = max_slope_center + @divFloor((max_slope_edge - max_slope_center) * dist, CITY_WIDTH_MAX);
                    if (height_diff > slope_height_diff) {
                        city.is_border.items[stack_index - 1] = false;
                        // std.debug.print("LOLsi: {}, height_curr:{}, height_side:{}, max_slope_center: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, max_slope_center, height_diff_i, slope_height_diff });
                        continue;
                        // continue :city_blk;
                    }

                    // if (stack_index < 3) {
                    //     std.debug.print("si: {}, height_curr:{}, height_side:{}, height_diff: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, height_diff, height_diff_i, slope_height_diff });
                    // }

                    // if (height_side < 90 * 255 or height_side > 200 * 255) {
                    //     // std.debug.print("WTFsi: {}, height_curr:{}, height_side:{}, height_diff: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, height_diff, height_diff_i, slope_height_diff });
                    //     continue;
                    // }

                    for (city.border_pos.items) |border_pos| {
                        if (border_pos[0] == pos[0] and border_pos[2] == pos[2]) {
                            // std.debug.print("WTFFFsi: {}, height_curr:{}, height_side:{}, height_diff: {}, height_diff_i: {}, slope_height_diff: {}\n", .{ stack_index, height_curr, height_side, height_diff, height_diff_i, slope_height_diff });
                            continue :nswe_blk;
                        }
                    }

                    city.border_pos.append([_]f32{ pos[0], height_side, pos[2] }) catch unreachable;
                    city.is_border.append(false) catch unreachable;
                }
            }

            if (city.border_pos.items.len > CITY_MIN_BORDERS) {
                cities.append(city) catch unreachable;
                std.debug.print("city: pos{any}, len{}\n", .{ city.pos, city.border_pos.items.len });
            }
        }
    }

    for (cities.items) |*city| {
        var to_remove = std.BoundedArray(u64, 512).init(0) catch unreachable;
        for (city.border_pos.items, 0..) |pos_curr, i| {
            const posNSWE = [_]Pos{
                .{
                    pos_curr[0],
                    pos_curr[1],
                    pos_curr[2] + CITY_HEIGHT_TEST_SKIP,
                },
                .{
                    pos_curr[0],
                    pos_curr[1],
                    pos_curr[2] - CITY_HEIGHT_TEST_SKIP,
                },
                .{
                    pos_curr[0] - CITY_HEIGHT_TEST_SKIP,
                    pos_curr[1],
                    pos_curr[2],
                },
                .{
                    pos_curr[0] + CITY_HEIGHT_TEST_SKIP,
                    pos_curr[1],
                    pos_curr[2],
                },
            };

            var border_count: u64 = 0;
            var inside_count: u64 = 0;
            for (posNSWE) |pos| {
                for (city.border_pos.items, city.is_border.items) |border_pos, is_border| {
                    if (border_pos[0] == pos[0] and border_pos[2] == pos[2]) {
                        if (is_border) {
                            border_count += 1;
                        } else {
                            inside_count += 1;
                        }
                        break;
                    }
                }
            }

            city.is_border.items[i] = false;
            if (inside_count == 0) {
                to_remove.appendAssumeCapacity(i);
            }
            if (border_count + inside_count < 4) {
                city.is_border.items[i] = true;
            }
        }

        while (to_remove.len > 0) {
            const i = to_remove.pop();
            _ = city.border_pos.swapRemove(i);
            _ = city.is_border.swapRemove(i);
        }
    }

    // if (node.output_artifacts) {
    //     for (cities.items) |city| {
    //         std.debug.print("....city pos:{any} size:{}\n", .{ city.pos, city.border_pos.items.len });
    //         for (city.border_pos.items, 0..) |pos, i| {
    //             const is_border = city.is_border.items[i];
    //             var city_z: i64 = 0;
    //             while (city_z < CITY_HEIGHT_TEST_SKIP) : (city_z += stride) {
    //                 var city_x: i64 = 0;
    //                 while (city_x < CITY_HEIGHT_TEST_SKIP) : (city_x += stride) {
    //                     pixels_index = @intCast(u64, @divFloor(pos[0] + city_x, stride) + @divFloor((pos[2] + city_z) * image_width, stride));
    //                     // pixels_index = @intCast(u64, @divFloor(pos[0], stride) + @divFloor((pos[2] + 0) * image_width, stride));
    //                     // const height = patches.getHeight(pos[0],pos[2]);
    //                     const height = pixels[pixels_index].r;
    //                     const add = @min(100, 255 - height);
    //                     const sub = @min(add, @min(20, pixels[pixels_index].b));
    //                     pixels[pixels_index].r += if (is_border) add else add / 2;
    //                     // pixels[pixels_index].R = pixels[pixels_index].R / 2;
    //                     pixels[pixels_index].g -= sub;
    //                     pixels[pixels_index].b -= sub;
    //                 }
    //             }
    //         }
    //     }
    // }

    const write_image = false;

    if (node.output_artifacts and write_image) {
        std.debug.print("city: outputting artifact...\n", .{});

        const patch_width = config_patch_width;
        const image_width = 2048;
        const stride = @as(i64, @intCast(@divExact(world_width, image_width)));
        const hmimg = img.Image.create(context.frame_allocator, image_width, image_width, img.PixelFormat.rgba32) catch unreachable;
        const pixels = hmimg.pixels.rgba32;
        var pixels_index: u64 = 0;

        world_z = 0;
        const patch_width_i = @as(i64, @intCast(patch_width));
        while (world_z < world_width - patch_width + 1) : (world_z += patch_width_i) {
            std.debug.print("..{}\n", .{world_z});
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
                            .name = IdLocal.init("world_z"),
                            .value = v.Variant.createUInt64(world_z),
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
                var world_patch_z: i64 = 0;
                while (world_patch_z < patch_width) : (world_patch_z += stride) {
                    var world_patch_x: i64 = 0;
                    while (world_patch_x < patch_width) : (world_patch_x += stride) {
                        pixels_index = @as(u64, @intCast(@divFloor(world_x + world_patch_x, stride) + @divFloor((world_z + world_patch_z) * image_width, stride)));
                        const height = @as(u8, @intCast(patches.getHeight(world_x + world_patch_x, world_z + world_patch_z) / 255));
                        pixels[pixels_index].r = height;
                        pixels[pixels_index].g = height;
                        pixels[pixels_index].b = height;
                        pixels[pixels_index].a = 255;
                        if (height < 10) {
                            pixels[pixels_index].r = 50 + height / 2;
                            pixels[pixels_index].g = 50 + height / 2;
                            pixels[pixels_index].b = 90 + height * 2;
                        } else if (height > 200) {
                            pixels[pixels_index].r = 145 + (height - 200) * 2;
                            pixels[pixels_index].g = 145 + (height - 200) * 2;
                            pixels[pixels_index].b = 145 + (height - 200) * 2;
                        } else {
                            pixels[pixels_index].r = 20 + height / 2;
                            pixels[pixels_index].g = 50 + height / 2;
                            pixels[pixels_index].b = 20 + height / 2;
                        }

                        if (@as(u64, @intCast((world_x + world_patch_x))) % (patch_width * 4) < 32 or @as(u64, @intCast((world_z + world_patch_z))) % (patch_width * 4) < 32) {
                            pixels[pixels_index].r -= 5;
                            pixels[pixels_index].g -= 5;
                            pixels[pixels_index].b -= 5;
                        } else if (@as(u64, @intCast((world_x + world_patch_x))) % patch_width < 4 or @as(u64, @intCast((world_z + world_patch_z))) % patch_width < 4) {
                            pixels[pixels_index].r -= 5;
                            pixels[pixels_index].g -= 5;
                            pixels[pixels_index].b -= 5;
                        }
                    }
                }
            }
        }

        std.debug.print("..cities\n", .{});
        const stride_f = @as(f32, @floatFromInt(stride));
        for (cities.items) |city| {
            std.debug.print("....city pos:{any} size:{}\n", .{ city.pos, city.border_pos.items.len });
            for (city.border_pos.items, 0..) |pos, i| {
                const is_border = city.is_border.items[i];
                var city_z: f32 = 0;
                while (city_z < CITY_HEIGHT_TEST_SKIP) : (city_z += stride_f) {
                    var city_x: f32 = 0;
                    while (city_x < CITY_HEIGHT_TEST_SKIP) : (city_x += stride_f) {
                        pixels_index = @as(u64, //
                            @intFromFloat(@divFloor(pos[0] + city_x, stride_f) + //
                            @divFloor((pos[2] + city_z) * image_width, stride_f)));
                        // pixels_index = @intCast(u64, @divFloor(pos[0], stride) + @divFloor((pos[2] + 0) * image_width, stride));
                        // const height = patches.getHeight(pos[0],pos[2]);
                        const height = pixels[pixels_index].r;
                        const add = @min(100, 255 - height);
                        const sub = @min(add, @min(20, pixels[pixels_index].b));
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
        const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "citymap_{}_{}.png", .{ world_width, image_width }) catch unreachable;

        const enc_opt: img.AllFormats.PNG.EncoderOptions = .{};
        const encoder_options = img.AllFormats.ImageEncoderOptions{ .png = enc_opt };
        hmimg.writeToFilePath(namebufslice, encoder_options) catch unreachable;
    }

    const write_cities = node.getInput(IdLocal.init("Write Cities")).value.getUInt64() == 1;
    if (write_cities and node.output_artifacts) {
        var folderbuf: [256]u8 = undefined;
        var namebuf: [256]u8 = undefined;

        const folderbufslice = std.fmt.bufPrintZ(
            folderbuf[0..folderbuf.len],
            "content/systems",
            .{},
        ) catch unreachable;
        std.fs.cwd().makeDir(folderbufslice) catch {};

        const namebufslice = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "{s}/cities.txt",
            .{
                folderbufslice,
            },
        ) catch unreachable;

        const remap_file = std.fs.cwd().createFile(
            namebufslice,
            .{ .read = true },
        ) catch unreachable;
        defer remap_file.close();

        for (cities.items) |city| {
            const prop_slice = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "city,{d:.3},{d:.3},{d:.3},{any}\n",
                .{
                    city.pos[0], city.pos[1], city.pos[2], city.border_pos.items.len,
                },
            ) catch unreachable;
            const bytes_written = remap_file.writeAll(prop_slice) catch unreachable;
            _ = bytes_written;
        }
    }

    var rand1 = std.rand.DefaultPrng.init(0);
    const rand = rand1.random();
    _ = rand;
    if (output.template.?.name.eqlStr("City Props")) {
        const city_id = IdLocal.init("city");
        const house_id = IdLocal.init("house");
        const wall_id = IdLocal.init("wall");
        _ = wall_id;
        var props = std.ArrayList(graph_props.Prop).initCapacity(context.frame_allocator, 1000) catch unreachable;
        for (cities.items) |city| {
            props.append(.{
                .id = city_id,
                .pos = .{
                    @as(f32, @floatCast(city.pos[0])),
                    @as(f32, @floatCast(city.pos[1])),
                    @as(f32, @floatCast(city.pos[2])),
                },
                .rot = 0,
            }) catch unreachable;

            props.append(.{
                .id = house_id,
                .pos = .{
                    @as(f32, @floatCast(city.pos[0])),
                    @as(f32, @floatCast(city.pos[1])),
                    @as(f32, @floatCast(city.pos[2])),
                },
                .rot = 0,
            }) catch unreachable;

            // for (city.border_pos.items, city.is_border.items) |pos, is_border| {
            //     if (!is_border) {
            //         if (rand.float(f32) < 0.05) {
            //             props.append(.{
            //                 .id = house_id,
            //                 .pos = .{
            //                     @floatCast(f32, pos[0]),
            //                     @floatCast(f32, pos[1]),
            //                     @floatCast(f32, pos[2]),
            //                 },
            //                 .rot = rand.float(f32) * std.math.pi * 2,
            //             }) catch unreachable;
            //         }
            //         continue;
            //     }

            //     const dir_to_city = zm.normalize3(zm.loadArr3(pos) - zm.loadArr3(city.pos));

            //     props.append(.{
            //         .id = wall_id,
            //         .pos = .{
            //             @floatCast(f32, pos[0]),
            //             @floatCast(f32, pos[1]),
            //             @floatCast(f32, pos[2]),
            //         },
            //         .rot = std.math.atan2(f32, -dir_to_city[2], dir_to_city[0]),
            //     }) catch unreachable;
            // }
        }

        // HACK: need to handle this memory properly
        const res = .{ .success = v.Variant.createSlice(props.items, 1) };
        return res;
    }

    const res = .{ .success = .{} };
    // const res = .{ .success = v.Variant.createPtr(trees.items, 1) };
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
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Write Cities") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 12),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Cities") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("City Props") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 14),
};

pub const cityNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("City"),
    .version = 0,
    .func = cityFunc,
};
