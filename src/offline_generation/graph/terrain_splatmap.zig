const std = @import("std");
const znoise = @import("znoise");
const img = @import("zigimg");

const config = @import("../../config/config.zig");
const g = @import("graph.zig");
const lru = @import("../../core/lru_cache.zig");
const v = @import("../../core/core.zig").variant;
const IdLocal = @import("../../core/core.zig").IdLocal;

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
    _ = obj_type;
    const ret: ptr_type = @ptrCast(@alignCast(ptr));
    return ret;
}

fn funcTemplateSplatmap(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []const g.NodeFuncParam) g.NodeFuncResult {
    _ = output;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patch_width_input = node.getInputByString("Heightmap Patch Width");
    const patch_width = getInputResult(patch_width_input, context).getUInt64();
    const patch_size = (patch_width) * (patch_width);

    const seed_input = node.getInputByString("Seed");
    const seed = getInputResult(seed_input, context).getUInt64();

    var world_rect_x: u64 = 0;
    var world_rect_z: u64 = 0;
    var world_rect_width: u64 = world_width;
    var world_rect_height: u64 = world_width;
    if (params.len > 0 and !params[0].value.isUnset()) {
        world_rect_x = params[0].value.getUInt64();
        world_rect_z = params[1].value.getUInt64();
        world_rect_width = params[2].value.getUInt64();
        world_rect_height = params[3].value.getUInt64();
    }

    const PATCH_CACHE_SIZE = 64 * 64;
    if (node.data == null) {
        var data = node.allocator.?.create(SplatmapNodeData) catch unreachable;
        data.cache.init(node.allocator.?, PATCH_CACHE_SIZE);
        data.noise = .{
            .seed = @intCast(seed),
            .fractal_type = .fbm,
            .frequency = 0.01,
            .octaves = 8,
        };
        node.data = data;
    }

    var data = alignedCast(*SplatmapNodeData, node.data.?);
    var cache = &data.cache;

    const patch_x_begin = @divTrunc(world_rect_x, patch_width);
    const patch_x_end = @divTrunc((world_rect_x + world_rect_width - 1), patch_width) + 1;
    const patch_z_begin = @divTrunc(world_rect_z, patch_width);
    const patch_z_end = @divTrunc((world_rect_z + world_rect_height - 1), patch_width) + 1;

    var output_data = context.frame_allocator.create(SplatmapOutputData) catch unreachable;
    output_data.count = 0;
    output_data.patch_width = patch_width;
    output_data.count_x = patch_x_end - patch_x_begin;
    output_data.count_z = patch_z_end - patch_z_begin;

    std.debug.assert((patch_x_end - patch_x_begin) * (patch_z_end - patch_z_begin) < PATCH_CACHE_SIZE);
    std.debug.assert((patch_x_end - patch_x_begin) * (patch_z_end - patch_z_begin) <= output_data.patch_positions.len);

    var patch_z = patch_z_begin;
    while (patch_z < patch_z_end) : (patch_z += 1) {
        // std.debug.print("splatmap:row {}/{}\n", .{ patch_z, patch_z_end });
        var patch_x = patch_x_begin;
        while (patch_x < patch_x_end) : (patch_x += 1) {
            // var patch_z: u64 = patch_z_begin;
            // while (hm_patch_z < patch_z_end) : (hm_patch_z += 1) {
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
                        .name = IdLocal.init("world_z"),
                        .value = v.Variant.createUInt64(patch_z * patch_width),
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

            const patch_cache_key = @as(u64, @intCast(patch_x + 10000 * patch_z));
            const patch_pos_x = patch_x - patch_x_begin;
            const patch_pos_z = patch_z - patch_z_begin;
            output_data.patch_positions[patch_pos_x + patch_pos_z * output_data.count_x] = .{ @as(i64, @intCast(patch_x)), @as(i64, @intCast(patch_z)) };

            var splatmap: []SplatmapMaterial = undefined;
            var evictable_lru_key: ?lru.LRUKey = null;
            var evictable_lru_value: ?lru.LRUValue = null;
            const splatmapOpt = cache.try_get(patch_cache_key, &evictable_lru_key, &evictable_lru_value);
            if (splatmapOpt != null) {
                var arrptr = alignedCast([*]SplatmapMaterial, splatmapOpt.?.*);
                // var arrptr = @ptrCast([*]SplatmapMaterial, splatmapOpt.?.*);
                // std.debug.print("Found patch {}, {}\n", .{ patch_x, patch_z });
                splatmap = arrptr[0..@as(u64, @intCast(patch_size))];
            } else {
                if (evictable_lru_key != null) {
                    // std.debug.print("Evicting {} for patch {}, {}\n", .{ evictable_lru_key.?, patch_x, patch_z });
                    var arrptr = alignedCast([*]SplatmapMaterial, evictable_lru_value);
                    splatmap = arrptr[0..@as(u64, @intCast(patch_size))];
                } else {
                    // std.debug.print("[SPLATMAP] Cache miss for patch {}, {}\n", .{ patch_x, patch_z });
                    splatmap = node.allocator.?.alloc(SplatmapMaterial, @as(u64, @intCast(patch_size))) catch unreachable;
                }

                // Calc splatmap
                var z: u64 = 0;
                while (z < patch_width) : (z += 1) {
                    var x: u64 = 0;
                    while (x < patch_width) : (x += 1) {
                        const world_x = patch_x * patch_width + x;
                        const world_z = patch_z * patch_width + z;
                        const world_y = heightmap_patches.getHeight(world_x, world_z);

                        const noise_value: f32 = data.noise.noise2(
                            @as(f32, @floatFromInt(world_x)) * config.noise_scale_xz,
                            @as(f32, @floatFromInt(world_z)) * config.noise_scale_xz,
                        );
                        const world_z_noised = std.math.clamp(world_y + noise_value * 100, 0, config.terrain_max);
                        splatmap[x + z * patch_width] = @intFromFloat(4 * world_z_noised / config.terrain_max);
                        // if (height_sample < 1000) {
                        //     splatmap[x + z * patch_width] = 50;
                        // } else {
                        //     splatmap[x + z * patch_width] = @intCast(SplatmapMaterial, height_sample / 256);
                        //     splatmap[x + z * patch_width] = 200;
                        // }
                        // heightmap[x + z * patch_width] = @floatToInt(SplatmapMaterial, height_sample * 127);
                        // std.debug.print("({},{})", .{ world_x, world_z });
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
                    for (splatmap, 0..) |pixel, i| {
                        hmimg.pixels.grayscale8[i].value = @as(u8, @intCast(pixel));
                    }

                    std.fs.cwd().makeDir("content/splatmap") catch {};

                    var namebuf: [256]u8 = undefined;
                    const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "content/splatmap/patch_x{}_z{}.pgm", .{ patch_x, patch_z }) catch unreachable;

                    const pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
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
