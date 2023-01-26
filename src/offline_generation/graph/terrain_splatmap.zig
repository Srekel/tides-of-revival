const std = @import("std");
const znoise = @import("znoise");
const img = @import("zigimg");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const IdLocal = v.IdLocal;

const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;

pub const SplatmapMaterial = u8;
pub const SPLATMAP_PATCH_QUERY_MAX = 32;

const SplatmapNodeData = struct {
    cache: lru.LRUCache,
    noise: znoise.FnlGenerator,
};

const SplatmapOutputData = graph_util.PatchOutputData(SplatmapMaterial);

fn alignedCast(comptime ptr_type: type, ptr: anytype) ptr_type {
    const ptr_typeinfo = @typeInfo(ptr_type);
    const obj_type = ptr_typeinfo.Pointer.child;
    var ret = @ptrCast(ptr_type, @alignCast(@alignOf(obj_type), ptr));
    return ret;
}

fn funcTemplateSplatmap(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
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
        var data = node.allocator.?.create(SplatmapNodeData) catch unreachable;
        data.cache.init(node.allocator.?, PATCH_CACHE_SIZE);
        data.noise = .{
            .seed = @intCast(i32, seed),
            .fractal_type = .fbm,
            .frequency = 0.001,
            .octaves = 10,
        };
        node.data = data;
    }

    var data = alignedCast(*SplatmapNodeData, node.data.?);
    var cache = &data.cache;

    const patch_x_begin = @divTrunc(world_x, patch_width);
    const patch_x_end = @divTrunc((world_x + width - 1), patch_width) + 1;
    const patch_y_begin = @divTrunc(world_y, patch_width);
    const patch_y_end = @divTrunc((world_y + height - 1), patch_width) + 1;

    var output_data = context.frame_allocator.create(SplatmapOutputData) catch unreachable;
    output_data.count = 0;
    output_data.patch_width = patch_width;
    output_data.count_x = patch_x_end - patch_x_begin;
    output_data.count_y = patch_y_end - patch_y_begin;

    std.debug.assert((patch_x_end - patch_x_begin) * (patch_y_end - patch_y_begin) < PATCH_CACHE_SIZE);
    std.debug.assert((patch_x_end - patch_x_begin) * (patch_y_end - patch_y_begin) <= output_data.patch_positions.len);

    var patch_y = patch_y_begin;
    while (patch_y < patch_y_end) : (patch_y += 1) {
        // std.debug.print("splatmap:row {}/{}\n", .{ patch_y, patch_y_end });
        var patch_x = patch_x_begin;
        while (patch_x < patch_x_end) : (patch_x += 1) {
            // var patch_y: u64 = patch_y_begin;
            // while (hm_patch_y < patch_y_end) : (hm_patch_y += 1) {
            //     var hm_patch_x: u64 = patch_x_begin;
            //     while (hm_patch_x < patch_x_end) : (hm_patch_x += 1) {
            const heightmap_patches = patch_blk: {
                const heightmap_patches_input = node.getInputByString("Heightmap Patches");
                const prevNodeOutput = heightmap_patches_input.source orelse unreachable;
                const prevNode = prevNodeOutput.node orelse unreachable;
                const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                    .{
                        .name = IdLocal.init("world_x"),
                        .value = v.Variant.createUInt64(patch_x * patch_width),
                    },
                    .{
                        .name = IdLocal.init("world_y"),
                        .value = v.Variant.createUInt64(patch_y * patch_width),
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

                const heightmap_data = res.success.getPtr(graph_heightmap.HeightmapOutputData, 1);
                break :patch_blk heightmap_data;
            };

            const patch_cache_key = @intCast(u64, patch_x + 10000 * patch_y);
            const patch_pos_x = patch_x - patch_x_begin;
            const patch_pos_y = patch_y - patch_y_begin;
            output_data.patch_positions[patch_pos_x + patch_pos_y * output_data.count_x] = .{ @intCast(i64, patch_x), @intCast(i64, patch_y) };

            var splatmap: []SplatmapMaterial = undefined;
            var evictable_lru_key: ?lru.LRUKey = null;
            var evictable_lru_value: ?lru.LRUValue = null;
            var splatmapOpt = cache.try_get(patch_cache_key, &evictable_lru_key, &evictable_lru_value);
            if (splatmapOpt != null) {
                var arrptr = alignedCast([*]SplatmapMaterial, splatmapOpt.?.*);
                // var arrptr = @ptrCast([*]SplatmapMaterial, splatmapOpt.?.*);
                // std.debug.print("Found patch {}, {}\n", .{ patch_x, patch_y });
                splatmap = arrptr[0..@intCast(u64, patch_size)];
            } else {
                if (evictable_lru_key != null) {
                    // std.debug.print("Evicting {} for patch {}, {}\n", .{ evictable_lru_key.?, patch_x, patch_y });
                    var arrptr = alignedCast([*]SplatmapMaterial, evictable_lru_value);
                    splatmap = arrptr[0..@intCast(u64, patch_size)];
                } else {
                    std.debug.print("[SPLATMAP] Cache miss for patch {}, {}\n", .{ patch_x, patch_y });
                    splatmap = node.allocator.?.alloc(SplatmapMaterial, @intCast(u64, patch_size)) catch unreachable;
                }

                // Calc splatmap
                var y: u64 = 0;
                while (y < patch_width) : (y += 1) {
                    var x: u64 = 0;
                    while (x < patch_width) : (x += 1) {
                        var world_sample_x = patch_x * patch_width + x;
                        var world_sample_y = patch_y * patch_width + y;
                        var height_sample = heightmap_patches.getHeight(world_sample_x, world_sample_y);
                        // std.debug.assert(height_sample * 127 < 255);
                        const chunked_height_sample = @intCast(SplatmapMaterial, height_sample / 16000);
                        splatmap[x + y * patch_width] = 0 + 1 * chunked_height_sample;
                        // if (height_sample < 1000) {
                        //     splatmap[x + y * patch_width] = 50;
                        // } else {
                        //     splatmap[x + y * patch_width] = @intCast(SplatmapMaterial, height_sample / 256);
                        //     splatmap[x + y * patch_width] = 200;
                        // }
                        // heightmap[x + y * patch_width] = @floatToInt(SplatmapMaterial, height_sample * 127);
                        // std.debug.print("({},{})", .{ world_x, world_y });
                    }
                    // std.debug.print("\n", .{});
                }
                // std.debug.print("xxxxx\n", .{});

                if (evictable_lru_key != null) {
                    cache.replace(evictable_lru_key.?, patch_cache_key, splatmap.ptr);
                } else {
                    cache.put(patch_cache_key, splatmap.ptr);
                }

                if (node.output_artifacts) {
                    // const hm = output_data.patches[0];
                    const hmimg = img.Image.create(context.frame_allocator, patch_width, patch_width, img.PixelFormat.grayscale8) catch unreachable;
                    // _ = hm;
                    for (splatmap) |pixel, i| {
                        hmimg.pixels.grayscale8[i].value = @intCast(u8, pixel);
                    }

                    std.fs.cwd().makeDir("content/splatmap") catch {};

                    var namebuf: [256]u8 = undefined;
                    const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "content/splatmap/patch_x{}_y{}.pgm", .{ patch_x, patch_y }) catch unreachable;

                    var pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
                    const encoder_options = img.AllFormats.ImageEncoderOptions{ .pgm = pgm_opt };
                    hmimg.writeToFilePath(namebufslice, encoder_options) catch unreachable;
                }
                var lol: i32 = 3;
                lol += 1;
            }

            output_data.patches[output_data.count] = splatmap;
            output_data.count += 1;
        }
    }

    const res = .{ .success = v.Variant.createPtr(output_data, 1) };
    return res;
}

pub const splatmapFunc = g.NodeFuncTemplate{
    .name = IdLocal.init("splatmap"),
    .version = 0,
    .func = &funcTemplateSplatmap,
    .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patch Width") }}) //
        ++
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patches") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 12),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Patches") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 15),
};

pub const splatmapNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("Splatmap"),
    .version = 0,
    .func = splatmapFunc,
};
