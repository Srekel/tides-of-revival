const std = @import("std");

const g = @import("graph.zig");
const lru = @import("lru_cache.zig");
const v = @import("variant.zig");
const IdLocal = v.IdLocal;

const img = @import("zigimg");

const zm = @import("zmath");
const znoise = @import("znoise");

const HeightmapHeight = u16;
const Pos = @Vector(2, i64);

fn alignedCast(comptime ptr_type: type, ptr: anytype) ptr_type {
    const ptr_typeinfo = @typeInfo(ptr_type);
    const obj_type = ptr_typeinfo.Pointer.child;
    var ret = @ptrCast(ptr_type, @alignCast(@alignOf(obj_type), ptr));
    return ret;
}

fn getInputResult(input: *g.NodeInput, context: *g.GraphContext) v.Variant {
    if (input.reference.isUnset()) {
        return input.value;
    } else {
        const prevNodeOutput = input.source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &.{});

        if (res != .success) {
            unreachable;
        }
        return res.success;
    }
}

fn funcTemplateNumber(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = context;
    const paramValue = if (params.len == 1) params[0].value.getUInt64() else 0;
    _ = paramValue;
    if (node.inputs[0].reference.isUnset()) {
        const value = node.inputs[0].value;
        return .{ .success = v.Variant.createUInt64(value.getUInt64()) };
    }

    const prevNodeOutput = node.inputs[0].source orelse unreachable;
    const prevNode = prevNodeOutput.node orelse unreachable;
    var res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &.{});
    const number = res.success.getUInt64();
    res.success = v.Variant.createUInt64(number);
    return res;
}

fn funcTemplateAdd(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = context;
    _ = params;
    var valueA: v.Variant = undefined;
    if (node.inputs[0].reference.isUnset()) {
        valueA = node.inputs[0].value;
    } else {
        const prevNodeOutput = node.inputs[0].source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{.{
            .name = IdLocal.init("number"),
            .value = v.Variant.createUInt64(0),
        }}));
        if (res != .success) {
            return .waiting;
        }
        valueA = res.success;
    }

    var valueB: v.Variant = undefined;
    if (node.inputs[1].reference.isUnset()) {
        valueB = node.inputs[1].value;
    } else {
        const prevNodeOutput = node.inputs[1].source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{.{
            .name = IdLocal.init("number"),
            .value = v.Variant.createUInt64(0),
        }}));
        if (res != .success) {
            return .waiting;
        }
        valueB = res.success;
    }

    return .{ .success = v.Variant.createUInt64(valueA.getUInt64() + valueB.getUInt64()) };
}

// ██╗  ██╗███████╗██╗ ██████╗ ██╗  ██╗████████╗███╗   ███╗ █████╗ ██████╗
// ██║  ██║██╔════╝██║██╔════╝ ██║  ██║╚══██╔══╝████╗ ████║██╔══██╗██╔══██╗
// ███████║█████╗  ██║██║  ███╗███████║   ██║   ██╔████╔██║███████║██████╔╝
// ██╔══██║██╔══╝  ██║██║   ██║██╔══██║   ██║   ██║╚██╔╝██║██╔══██║██╔═══╝
// ██║  ██║███████╗██║╚██████╔╝██║  ██║   ██║   ██║ ╚═╝ ██║██║  ██║██║
// ╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

const HEIGHMAP_PATCH_QUERY_MAX = 32;

const HeightmapOutputData = struct {
    patches: [HEIGHMAP_PATCH_QUERY_MAX][]HeightmapHeight = undefined,
    patch_positions: [HEIGHMAP_PATCH_QUERY_MAX]Pos = undefined,
    patch_width: u64 = undefined,
    count: u64 = undefined,
    count_x: u64 = undefined,
    count_y: u64 = undefined,

    fn getHeight(self: HeightmapOutputData, world_x: i64, world_y: i64) HeightmapHeight {
        const patch_x = @divTrunc(@intCast(u64, world_x), self.patch_width);
        const patch_y = @divTrunc(@intCast(u64, world_y), self.patch_width);
        // const patch_begin_x = @divExact(@intCast(u64, self.patch_positions[0][0]), self.patch_width);
        // const patch_begin_y = @divExact(@intCast(u64, self.patch_positions[0][1]), self.patch_width);
        const patch_begin_x = @intCast(u64, self.patch_positions[0][0]);
        const patch_begin_y = @intCast(u64, self.patch_positions[0][1]);
        const patch_index_x = patch_x - patch_begin_x;
        const patch_index_y = patch_y - patch_begin_y;
        const patch = self.patches[patch_index_x + patch_index_y * self.count_x];
        const inside_patch_x = @intCast(u64, world_x) % self.patch_width;
        const inside_patch_y = @intCast(u64, world_y) % self.patch_width;
        return patch[inside_patch_x + inside_patch_y * self.patch_width];
    }

    fn getHeightI(self: HeightmapOutputData, world_x: i64, world_y: i64) i32 {
        return self.getHeight(world_x, world_y);
    }
};

const HeightmapNodeData = struct {
    cache: lru.LRUCache,
    noise: znoise.FnlGenerator,
};

fn funcTemplateHeightmap(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = context;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patch_width_input = node.getInputByString("Heightmap Patch Width");
    const patch_width = getInputResult(patch_width_input, context).getUInt64();
    const patch_size = (patch_width) * (patch_width);

    const seed_input = node.getInputByString("Seed");
    const seed = getInputResult(seed_input, context).getUInt64();

    var world_x: u64 = 0;
    var world_y: u64 = 0;
    var width: u64 = world_width;
    var height: u64 = world_width;
    if (params.len > 0 and !params[0].value.isUnset()) {
        world_x = params[0].value.getUInt64();
        world_y = params[1].value.getUInt64();
        width = params[2].value.getUInt64();
        height = params[3].value.getUInt64();
    }

    const PATCH_CACHE_SIZE = 64 * 64;
    if (node.data == null) {
        var data = node.allocator.?.create(HeightmapNodeData) catch unreachable;
        data.cache.init(node.allocator.?, PATCH_CACHE_SIZE);
        data.noise = .{
            .seed = @intCast(i32, seed),
            .fractal_type = .fbm,
            .frequency = 0.0001,
            .octaves = 20,
        };
        node.data = data;
    }

    var data = alignedCast(*HeightmapNodeData, node.data.?);
    var cache = &data.cache;

    const patch_x_begin = @divTrunc(world_x, patch_width);
    const patch_x_end = @divTrunc((world_x + width - 1), patch_width) + 1;
    const patch_y_begin = @divTrunc(world_y, patch_width);
    const patch_y_end = @divTrunc((world_y + height - 1), patch_width) + 1;

    std.debug.assert((patch_x_end - patch_x_begin) * (patch_y_end - patch_y_begin) < PATCH_CACHE_SIZE);

    var output_data = context.frame_allocator.create(HeightmapOutputData) catch unreachable;
    output_data.count = 0;
    output_data.patch_width = patch_width;
    output_data.count_x = patch_x_end - patch_x_begin;
    output_data.count_y = patch_y_end - patch_y_begin;

    var patch_y = patch_y_begin;
    while (patch_y < patch_y_end) : (patch_y += 1) {
        var patch_x = patch_x_begin;
        while (patch_x < patch_x_end) : (patch_x += 1) {
            const patch_cache_key = @intCast(u64, patch_x + 10000 * patch_y);
            const patch_pos_x = patch_x - patch_x_begin;
            const patch_pos_y = patch_y - patch_y_begin;
            output_data.patch_positions[patch_pos_x + patch_pos_y * output_data.count_x] = .{ @intCast(i64, patch_x), @intCast(i64, patch_y) };

            var heightmap: []HeightmapHeight = undefined;
            var evictable_lru_key: ?lru.LRUKey = null;
            var evictable_lru_value: ?lru.LRUValue = null;
            var heightmapOpt = cache.try_get(patch_cache_key, &evictable_lru_key, &evictable_lru_value);
            if (heightmapOpt != null) {
                var arrptr = alignedCast([*]HeightmapHeight, heightmapOpt.?.*);
                // var arrptr = @ptrCast([*]HeightmapHeight, heightmapOpt.?.*);
                heightmap = arrptr[0..@intCast(u64, patch_size)];
            } else {
                if (evictable_lru_key != null) {
                    // std.debug.print("Evicting {} for patch {}, {}\n", .{ evictable_lru_key.?, patch_x, patch_y });
                    var arrptr = alignedCast([*]HeightmapHeight, evictable_lru_value);
                    heightmap = arrptr[0..@intCast(u64, patch_size)];
                } else {
                    // std.debug.print("Cache miss for patch {}, {}\n", .{ patch_x, patch_y });
                    heightmap = node.allocator.?.alloc(HeightmapHeight, @intCast(u64, patch_size)) catch unreachable;
                }

                // Calc heightmap
                var y: u64 = 0;
                while (y < patch_width) : (y += 1) {
                    var x: u64 = 0;
                    while (x < patch_width) : (x += 1) {
                        var x_world = patch_x * patch_width + x;
                        var y_world = patch_y * patch_width + y;
                        var height_sample: f32 = (1 + data.noise.noise2(@intToFloat(f32, x_world), @intToFloat(f32, y_world)));
                        // std.debug.assert(height_sample * 127 < 255);
                        heightmap[x + y * patch_width] = @floatToInt(HeightmapHeight, height_sample * 32512);
                        // heightmap[x + y * patch_width] = @floatToInt(HeightmapHeight, height_sample * 127);
                        // std.debug.print("({},{})", .{ x_world, y_world });
                    }
                    // std.debug.print("\n", .{});
                }
                // std.debug.print("xxxxx\n", .{});

                if (evictable_lru_key != null) {
                    cache.replace(evictable_lru_key.?, patch_cache_key, heightmap.ptr);
                } else {
                    cache.put(patch_cache_key, heightmap.ptr);
                }

                if (node.output_artifacts) {
                    // const hm = output_data.patches[0];
                    const hmimg = img.image.Image.create(context.frame_allocator, patch_width, patch_width, img.PixelFormat.grayscale8) catch unreachable;
                    // _ = hm;
                    _ = hmimg;
                    for (heightmap) |pixel, i| {
                        hmimg.pixels.?.grayscale8[i].value = @intCast(u8, pixel / 255);
                    }

                    var namebuf: [256]u8 = undefined;
                    const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "heightmap_x{}_y{}.pgm", .{ patch_x, patch_y }) catch unreachable;

                    var pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
                    const encoder_options = img.AllFormats.ImageEncoderOptions{ .pgm = pgm_opt };
                    hmimg.writeToFilePath(namebufslice, img.ImageFormat.pgm, encoder_options) catch unreachable;
                }
                var lol: i32 = 3;
                lol += 1;
            }

            output_data.patches[output_data.count] = heightmap;
            output_data.count += 1;
        }
    }

    const res = .{ .success = v.Variant.createPtr(output_data, 1) };
    return res;
}

//  ██████╗██╗████████╗██╗   ██╗
// ██╔════╝██║╚══██╔══╝╚██╗ ██╔╝
// ██║     ██║   ██║    ╚████╔╝
// ██║     ██║   ██║     ╚██╔╝
// ╚██████╗██║   ██║      ██║
//  ╚═════╝╚═╝   ╚═╝      ╚═╝

fn funcTemplateCity(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = context;
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

    const CITY_WIDTH_MAX = 1024;
    const CITY_MARGIN_EDGE = CITY_WIDTH_MAX * 2;
    const CITY_MARGIN_CITY = CITY_WIDTH_MAX * 6;
    const CITY_SKIP = 64;
    const CITY_HEIGHT_TEST_SKIP = 16;
    _ = CITY_HEIGHT_TEST_SKIP;
    var patch_width: u64 = 1024; // hack

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
                const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
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

            patch_width = patches.patch_width;

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
                std.debug.print("city: pos{}, len{}\n", .{ city.pos, city.border_pos.items.len });
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

        const image_width = 8192;
        const stride = @intCast(i64, @divExact(world_width, image_width));
        const hmimg = img.image.Image.create(context.frame_allocator, image_width, image_width, img.PixelFormat.rgba32) catch unreachable;
        const pixels = hmimg.pixels.?.rgba32;
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
                    const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
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
            std.debug.print("....city pos:{} size:{}\n", .{ city.pos, city.border_pos.items.len });
            for (city.border_pos.items) |pos, i| {
                _ = i;
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
        hmimg.writeToFilePath(namebufslice, img.ImageFormat.qoi, encoder_options) catch unreachable;
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

pub fn generate() void {
    std.debug.print("LOL\n", .{});

    const numberFunc = g.NodeFuncTemplate{
        .name = IdLocal.init("number"),
        .version = 0,
        .func = &funcTemplateNumber,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("value") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 15),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("value") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const addFunc = g.NodeFuncTemplate{
        .name = IdLocal.init("add"),
        .version = 0,
        .func = &funcTemplateAdd,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("valueA") }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("valueB") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 14),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("value") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const heightmapFunc = g.NodeFuncTemplate{
        .name = IdLocal.init("heightmap"),
        .version = 0,
        .func = &funcTemplateHeightmap,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patch Width") }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 13),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Patches") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const cityFunc = g.NodeFuncTemplate{
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

    // const imageSamplerFunc = g.NodeFuncTemplate{
    //     .name = IdLocal.init("imageSampler"),
    //     .version = 0,
    //     .func = &funcTemplateImageSampler,
    //     .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Images") }}) //
    //         ++
    //         ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Sample Span") }}) //
    //         ++ //
    //         ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
    //         ++ //
    //         ([_]g.NodeInputTemplate{.{}} ** 13),
    //     .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Patches") }}) //
    //         ++ //
    //         ([_]g.NodeOutputTemplate{.{}} ** 15),
    // };

    const numberNodeTemplate = g.NodeTemplate{
        .name = IdLocal.init("Number"),
        .version = 0,
        .func = numberFunc,
    };
    const addNodeTemplate = g.NodeTemplate{
        .name = IdLocal.init("Add"),
        .version = 0,
        .func = addFunc,
    };
    _ = addNodeTemplate;

    const heightmapNodeTemplate = g.NodeTemplate{
        .name = IdLocal.init("Heightmap"),
        .version = 0,
        .func = heightmapFunc,
    };

    const cityNodeTemplate = g.NodeTemplate{
        .name = IdLocal.init("City"),
        .version = 0,
        .func = cityFunc,
    };

    //
    var seedNode = g.Node{
        .name = IdLocal.init("Seed"),
        .template = numberNodeTemplate,
    };
    seedNode.init();
    var seedInputValue = seedNode.getInput(IdLocal.init("value"));
    seedInputValue.value = v.Variant.createUInt64(1);
    var seedOutputValue = seedNode.getOutput(IdLocal.init("value"));
    seedOutputValue.reference.set("seed");

    //
    var worldWidthNode = g.Node{
        .name = IdLocal.init("World Width"),
        .template = numberNodeTemplate,
    };
    worldWidthNode.init();
    var worldWidthInputValue = worldWidthNode.getInput(IdLocal.init("value"));
    worldWidthInputValue.value = v.Variant.createUInt64(1024 * 64);
    worldWidthInputValue.value = v.Variant.createUInt64(1024 * 8);
    var worldWidthOutputValue = worldWidthNode.getOutput(IdLocal.init("value"));
    worldWidthOutputValue.reference.set("worldWidth");

    //
    var patchWidthNode = g.Node{
        .name = IdLocal.init("Patch Width"),
        .template = numberNodeTemplate,
    };
    patchWidthNode.init();
    var patchWidthInputValue = patchWidthNode.getInput(IdLocal.init("value"));
    // patchWidthInputValue.value = v.Variant.createUInt64(256);
    patchWidthInputValue.value = v.Variant.createUInt64(1024);
    var patchWidthOutputValue = patchWidthNode.getOutput(IdLocal.init("value"));
    patchWidthOutputValue.reference.set("heightmapPatchWidth");

    //
    var heightmapNode = g.Node{
        .name = IdLocal.init("Heightmap"),
        .template = heightmapNodeTemplate,
        .allocator = std.heap.page_allocator,
        // .output_artifacts = true,
    };
    heightmapNode.init();
    var heightmapPatchWidthInputValue = heightmapNode.getInput(IdLocal.init("Heightmap Patch Width"));
    heightmapPatchWidthInputValue.reference = IdLocal.init("heightmapPatchWidth");
    var heightmapSeedInputValue = heightmapNode.getInput(IdLocal.init("Seed"));
    heightmapSeedInputValue.reference = IdLocal.init("seed");
    var heightmapWorldWidthInputValue = heightmapNode.getInput(IdLocal.init("World Width"));
    heightmapWorldWidthInputValue.reference = IdLocal.init("worldWidth");
    var heightmapOutputValue = heightmapNode.getOutput(IdLocal.init("Patches"));
    heightmapOutputValue.reference.set("heightmapPatches");

    //
    var cityNode = g.Node{
        .name = IdLocal.init("City"),
        .template = cityNodeTemplate,
        .allocator = std.heap.page_allocator,
        .output_artifacts = true,
    };
    cityNode.init();
    var cityPatchesInputValue = cityNode.getInput(IdLocal.init("Heightmap Patches"));
    cityPatchesInputValue.reference = IdLocal.init("heightmapPatches");
    var citySeedInputValue = cityNode.getInput(IdLocal.init("Seed"));
    citySeedInputValue.reference = IdLocal.init("seed");
    var cityWorldWidthInputValue = cityNode.getInput(IdLocal.init("World Width"));
    cityWorldWidthInputValue.reference = IdLocal.init("worldWidth");
    // var cityOutputValue = cityNode.getOutput(IdLocal.init("Cities"));
    // cityOutputValue.reference.set("cities");

    // var pcgNode = g.Node{
    //     .name = IdLocal.init("pcg"),
    //     .template = numberNodeTemplate,
    // };
    // pcgNode.init();
    // var pcgInputValue = pcgNode.getInput(IdLocal.init("value"));
    // pcgInputValue.reference.set("seed");
    // var pcgOutputValue = pcgNode.getOutput(IdLocal.init("value"));
    // pcgOutputValue.reference.set("pcg");

    // var addNode = g.Node{
    //     .name = IdLocal.init("add"),
    //     .template = addNodeTemplate,
    // };
    // addNode.init();
    // var addInputValueA = addNode.getInput(IdLocal.init("valueA"));
    // addInputValueA.value = 2;
    // var addInputValueB = addNode.getInput(IdLocal.init("valueB"));
    // addInputValueB.reference.set("pcg");

    var allocator = std.heap.page_allocator;
    var graph = g.Graph{
        .nodes = std.ArrayList(g.Node).init(allocator),
    };

    _ = graph;

    graph.nodes.append(seedNode) catch unreachable;
    graph.nodes.append(patchWidthNode) catch unreachable;
    graph.nodes.append(worldWidthNode) catch unreachable;
    graph.nodes.append(heightmapNode) catch unreachable;
    graph.nodes.append(cityNode) catch unreachable;
    // graph.nodes.append(pcgNode) catch unreachable;
    // graph.nodes.append(addNode) catch unreachable;

    std.debug.print("Graph:", .{});
    graph.connect();
    graph.run(allocator);

    // const numberNode = g.NodeTemplate{};

    // graph.nodes.append(.{ .name = "hello", .version = 1, .input = .{} });
}
