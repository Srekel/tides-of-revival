const std = @import("std");
const config = @import("../../config.zig");
const znoise = @import("znoise");
const img = @import("zigimg");
const zm = @import("zmath");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const IdLocal = v.IdLocal;

const graph_util = @import("util.zig");
const getInputResult = graph_util.getInputResult;

pub const HeightmapHeight = u16;
pub const HEIGHTMAP_PATCH_QUERY_MAX = 128;

fn alignedCast(comptime ptr_type: type, ptr: anytype) ptr_type {
    var ret = @as(ptr_type, @ptrCast(@alignCast(ptr)));
    return ret;
}

pub const HeightmapOutputData = struct {
    patches: [HEIGHTMAP_PATCH_QUERY_MAX][]HeightmapHeight = undefined,
    patch_positions: [HEIGHTMAP_PATCH_QUERY_MAX][2]i64 = undefined,
    patch_width: u64 = undefined,
    count: u64 = undefined,
    count_x: u64 = undefined,
    count_y: u64 = undefined,

    pub fn getHeight(self: HeightmapOutputData, world_x: anytype, world_y: anytype) HeightmapHeight {
        const patch_x = @divTrunc(@as(u64, @intCast(world_x)), self.patch_width);
        const patch_y = @divTrunc(@as(u64, @intCast(world_y)), self.patch_width);
        // const patch_begin_x = @divExact(@intCast(u64, self.patch_positions[0][0]), self.patch_width);
        // const patch_begin_y = @divExact(@intCast(u64, self.patch_positions[0][1]), self.patch_width);
        const patch_begin_x = @as(u64, @intCast(self.patch_positions[0][0]));
        const patch_begin_y = @as(u64, @intCast(self.patch_positions[0][1]));
        const patch_index_x = patch_x - patch_begin_x;
        const patch_index_y = patch_y - patch_begin_y;
        const patch = self.patches[patch_index_x + patch_index_y * self.count_x];
        const inside_patch_x = @as(u64, @intCast(world_x)) % self.patch_width;
        const inside_patch_y = @as(u64, @intCast(world_y)) % self.patch_width;
        return patch[inside_patch_x + inside_patch_y * self.patch_width];
    }

    pub fn getHeightI(self: HeightmapOutputData, world_x: i64, world_y: i64) i32 {
        return self.getHeight(world_x, world_y);
    }

    pub fn getHeightWorld(self: HeightmapOutputData, world_x: anytype, world_y: anytype) f32 {
        if (@typeInfo(@TypeOf(world_x)) == .Float) {
            const height = self.getHeight(
                @as(i32, @intFromFloat(@floor(world_x))),
                @as(i32, @intFromFloat(@floor(world_y))),
            );
            const height_0_1 = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(std.math.maxInt(u16)));
            return config.noise_scale_y * height_0_1;
        }

        const height = self.getHeight(world_x, world_y);
        const height_0_1 = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(std.math.maxInt(u16)));
        return config.noise_scale_y * height_0_1;
    }
};

const HeightmapNodeData = struct {
    cache: lru.LRUCache,
    noise: znoise.FnlGenerator,
};

fn funcTemplateHeightmap(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []const g.NodeFuncParam) g.NodeFuncResult {
    _ = output;

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
            .seed = @as(i32, @intCast(seed)),
            .fractal_type = .fbm,
            .frequency = 0.001,
            .octaves = 10,
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
            const patch_cache_key = @as(u64, @intCast(patch_x + 10000 * patch_y));
            const patch_pos_x = patch_x - patch_x_begin;
            const patch_pos_y = patch_y - patch_y_begin;
            output_data.patch_positions[patch_pos_x + patch_pos_y * output_data.count_x] = .{ @as(i64, @intCast(patch_x)), @as(i64, @intCast(patch_y)) };

            var heightmap: []HeightmapHeight = undefined;
            var evictable_lru_key: ?lru.LRUKey = null;
            var evictable_lru_value: ?lru.LRUValue = null;
            var heightmapOpt = cache.try_get(patch_cache_key, &evictable_lru_key, &evictable_lru_value);
            if (heightmapOpt != null) {
                var arrptr = alignedCast([*]HeightmapHeight, heightmapOpt.?.*);
                // var arrptr = @ptrCast([*]HeightmapHeight, heightmapOpt.?.*);
                // std.debug.print("Found patch {}, {}\n", .{ patch_x, patch_y });
                heightmap = arrptr[0..@as(u64, @intCast(patch_size))];
            } else {
                if (evictable_lru_key != null) {
                    // std.debug.print("Evicting {} for patch {}, {}\n", .{ evictable_lru_key.?, patch_x, patch_y });
                    var arrptr = alignedCast([*]HeightmapHeight, evictable_lru_value);
                    heightmap = arrptr[0..@as(u64, @intCast(patch_size))];
                } else {
                    std.debug.print("[HEIGHTMAP] Cache miss for patch {}, {}\n", .{ patch_x, patch_y });
                    heightmap = node.allocator.?.alloc(HeightmapHeight, @as(u64, @intCast(patch_size))) catch unreachable;
                }

                // Calc heightmap
                var y: u64 = 0;
                while (y < patch_width) : (y += 1) {
                    var x: u64 = 0;
                    while (x < patch_width) : (x += 1) {
                        var x_world = patch_x * patch_width + x;
                        var y_world = patch_y * patch_width + y;
                        // NOTE(gmodarelli): we're remapping the noise from [-1, 1] to [0, 1] to be able to store it inside a texture,
                        // and then we're converting it to a 16-bit unsigned integer
                        var height_sample: f32 = data.noise.noise2(@as(f32, @floatFromInt(x_world)) * config.noise_scale_xz, @as(f32, @floatFromInt(y_world)) * config.noise_scale_xz) * 0.5 + 0.5;
                        if (height_sample < 0.1) {
                            height_sample = zm.mapLinearV(height_sample, 0.0, 0.05, 0, 0.1);
                        } else if (height_sample < 0.5) {
                            height_sample = zm.mapLinearV(height_sample, 0.05, 0.5, 0.1, 0.3);
                        } else if (height_sample < 0.6) {
                            height_sample = zm.mapLinearV(height_sample, 0.5, 0.6, 0.3, 0.5);
                        } else if (height_sample < 0.7) {
                            height_sample = zm.mapLinearV(height_sample, 0.6, 0.7, 0.5, 0.6);
                        } else {
                            height_sample = zm.mapLinearV(height_sample, 0.7, 1, 0.6, 1);
                        }
                        heightmap[x + y * patch_width] = @as(HeightmapHeight, @intFromFloat(height_sample * 65535));
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
                    const hmimg = img.Image.create(context.frame_allocator, patch_width, patch_width, img.PixelFormat.grayscale8) catch unreachable;
                    // _ = hm;
                    for (heightmap, 0..) |pixel, i| {
                        hmimg.pixels.grayscale8[i].value = @as(u8, @intCast(pixel / 255));
                    }

                    std.fs.cwd().makeDir("content/heightmap") catch {};

                    var namebuf: [256]u8 = undefined;
                    const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "content/heightmap/patch_x{}_y{}.pgm", .{ patch_x, patch_y }) catch unreachable;

                    var pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
                    const encoder_options = img.AllFormats.ImageEncoderOptions{ .pgm = pgm_opt };
                    hmimg.writeToFilePath(namebufslice, encoder_options) catch unreachable;
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

pub const heightmapFunc = g.NodeFuncTemplate{
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

pub const heightmapNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("Heightmap"),
    .version = 0,
    .func = heightmapFunc,
};
