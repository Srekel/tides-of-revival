const std = @import("std");

const g = @import("graph.zig");
const lru = @import("lru_cache.zig");
const v = @import("variant.zig");

const img = @import("zigimg");

const zm = @import("zmath");
const znoise = @import("znoise");

const HeightmapHeight = u8;
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
            .name = g.IdLocal.init("number"),
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
            .name = g.IdLocal.init("number"),
            .value = v.Variant.createUInt64(0),
        }}));
        if (res != .success) {
            return .waiting;
        }
        valueB = res.success;
    }

    return .{ .success = v.Variant.createUInt64(valueA.getUInt64() + valueB.getUInt64()) };
}

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

    if (node.data == null) {
        var data = node.allocator.?.create(HeightmapNodeData) catch unreachable;
        data.cache.init(node.allocator.?, 128);
        data.noise = .{
            .seed = @intCast(i32, seed),
            .fractal_type = .fbm,
            .frequency = 0.001,
            .octaves = 10,
        };
        node.data = data;
    }

    var data = alignedCast(*HeightmapNodeData, node.data.?);
    var cache = &data.cache;

    const patch_x_begin = @divTrunc(world_x, patch_width);
    const patch_x_end = @divTrunc((world_x + width), patch_width) + 1;
    const patch_y_begin = @divTrunc(world_y, patch_width);
    const patch_y_end = @divTrunc((world_y + height), patch_width) + 1;

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
                var arrptr = @ptrCast([*]HeightmapHeight, heightmapOpt.?.*);
                heightmap = arrptr[0..@intCast(u64, patch_size)];
            } else {
                if (evictable_lru_key != null) {
                    // std.debug.print("Evicting {} for patch {}, {}\n", .{ evictable_lru_key.?, patch_x, patch_y });
                    var arrptr = @ptrCast([*]HeightmapHeight, evictable_lru_value);
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
                        std.debug.assert(height_sample * 127 < 255);
                        heightmap[x + y * patch_width] = @floatToInt(HeightmapHeight, height_sample * 127);
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
                    const hmimg = img.image.Image.create(context.frame_allocator, patch_width, patch_width, img.PixelFormat.Grayscale8, img.ImageFormat.Pgm) catch unreachable;
                    // _ = hm;
                    _ = hmimg;
                    for (heightmap) |pixel, i| {
                        hmimg.pixels.?.Grayscale8[i].value = pixel;
                    }

                    var namebuf: [256]u8 = undefined;
                    const namebufslice = std.fmt.bufPrint(namebuf[0..namebuf.len], "heightmap_x{}_y{}.pgm", .{ patch_x, patch_y }) catch unreachable;

                    var pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
                    const encoder_options = img.AllFormats.ImageEncoderOptions{ .pgm = pgm_opt };
                    hmimg.writeToFilePath(namebufslice, hmimg.image_format, encoder_options) catch unreachable;
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

fn funcTemplateCity(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = context;
    _ = params;

    const City = struct {
        pos: Pos,
        border_pos: std.ArrayList(Pos),
    };

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Heightmap Patches");

    var cities = std.ArrayList(City).init(context.frame_allocator);

    const CITY_WIDTH_MAX = 128;
    const CITY_MARGIN_EDGE = CITY_WIDTH_MAX * 4;
    const CITY_MARGIN_CITY = 5000;
    const CITY_SKIP = 64;
    const CITY_HEIGHT_TEST_SKIP = 8;
    _ = CITY_HEIGHT_TEST_SKIP;

    var world_y: i64 = CITY_MARGIN_EDGE;
    while (world_y < world_width - CITY_MARGIN_EDGE) : (world_y += CITY_SKIP) {
        var world_x: i64 = CITY_MARGIN_EDGE;
        x_loop: while (world_x < world_width - CITY_MARGIN_EDGE) : (world_x += CITY_SKIP) {
            for (cities.items) |city| {
                const city_diff_x = std.math.absInt(city.pos[0] - world_x) catch unreachable;
                const city_diff_y = std.math.absInt(city.pos[1] - world_y) catch unreachable;
                if (city_diff_x < CITY_MARGIN_CITY and city_diff_y < CITY_MARGIN_CITY) {
                    continue :x_loop;
                }
            }

            const patches = patch_blk: {
                const prevNodeOutput = patches_input.source orelse unreachable;
                const prevNode = prevNodeOutput.node orelse unreachable;
                const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                    .{
                        .name = g.IdLocal.init("world_x"),
                        .value = v.Variant.createUInt64(world_x - CITY_WIDTH_MAX),
                    },
                    .{
                        .name = g.IdLocal.init("world_y"),
                        .value = v.Variant.createUInt64(world_y - CITY_WIDTH_MAX),
                    },
                    .{
                        .name = g.IdLocal.init("width"),
                        .value = v.Variant.createUInt64(CITY_WIDTH_MAX * 2),
                    },
                    .{
                        .name = g.IdLocal.init("height"),
                        .value = v.Variant.createUInt64(CITY_WIDTH_MAX * 2),
                    },
                }));

                if (res != .success) {
                    unreachable;
                }

                const data = res.success.getPtr(HeightmapOutputData, 1);
                break :patch_blk data;
            };

            // std.debug.assert(patches.count == 9)
            // for (patches) |patch,i| {

            // }

            const height = patches.getHeight(world_x, world_y);
            if (height < 50 or height > 200) {
                continue;
            }

            // const city: City = .{
            //     .pos = .{ world_x, world_y },
            //     .border_pos = std.ArrayList(Pos).init(context.frame_allocator),
            // };

            // var stack_index: u64 = 0;
            // city.border_pos.append(city.pos);
            // city_blk: while (stack_index < city.border_pos.items.len) {
            //     const curr_pos = city.border_pos.items[stack_index];
            //     stack_index += 1;

            //     const posNSWE = [_]Pos{
            //         .{
            //             curr_pos[0],
            //             curr_pos[1] + CITY_HEIGHT_TEST_SKIP,
            //         },
            //         .{
            //             curr_pos[0],
            //             curr_pos[1] - CITY_HEIGHT_TEST_SKIP,
            //         },
            //         .{
            //             curr_pos[0] - CITY_HEIGHT_TEST_SKIP,
            //             curr_pos[1],
            //         },
            //         .{
            //             curr_pos[0] + CITY_HEIGHT_TEST_SKIP,
            //             curr_pos[1],
            //         },
            //     };

            //     nswe_blk: for (posNSWE) |pos| {
            //         height_side = patches.getHeight(pos);
            //         if (std.math.absInt(height_side - height) > CITY_HEIGHT_TEST_SKIP) {
            //             continue :city_blk;
            //         }

            //         for (city.border_pos) |bp| {
            //             if (bp[0] == pos[0] and bp[0] == pos[0]) {
            //                 continue :nswe_blk;
            //             }
            //         }

            //         city.border_pos.append(pos);
            //     }
            // }

            // if (city.border_pos.items.len > 5) {
            //     cities.append(city) catch unreachable;
            //     // std.debug.print("{},{},{}\n", .{ world_x, world_y, height });
            // }
        }
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

pub fn main() void {
    std.debug.print("LOL\n", .{});

    const numberFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("number"),
        .version = 0,
        .func = &funcTemplateNumber,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("value") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 15),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("value") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const addFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("add"),
        .version = 0,
        .func = &funcTemplateAdd,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("valueA") }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("valueB") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 14),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("value") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const heightmapFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("heightmap"),
        .version = 0,
        .func = &funcTemplateHeightmap,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Heightmap Patch Width") }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Seed") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("World Width") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 13),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("Patches") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const cityFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("city"),
        .version = 0,
        .func = &funcTemplateCity,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Heightmap Patches") }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Seed") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("World Width") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 13),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("Cities") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    // const imageSamplerFunc = g.NodeFuncTemplate{
    //     .name = g.IdLocal.init("imageSampler"),
    //     .version = 0,
    //     .func = &funcTemplateImageSampler,
    //     .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Images") }}) //
    //         ++
    //         ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Sample Span") }}) //
    //         ++ //
    //         ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("World Width") }}) //
    //         ++ //
    //         ([_]g.NodeInputTemplate{.{}} ** 13),
    //     .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("Patches") }}) //
    //         ++ //
    //         ([_]g.NodeOutputTemplate{.{}} ** 15),
    // };

    const numberNodeTemplate = g.NodeTemplate{
        .name = g.IdLocal.init("Number"),
        .version = 0,
        .func = numberFunc,
    };
    const addNodeTemplate = g.NodeTemplate{
        .name = g.IdLocal.init("Add"),
        .version = 0,
        .func = addFunc,
    };
    _ = addNodeTemplate;

    const heightmapNodeTemplate = g.NodeTemplate{
        .name = g.IdLocal.init("Heightmap"),
        .version = 0,
        .func = heightmapFunc,
    };

    const cityNodeTemplate = g.NodeTemplate{
        .name = g.IdLocal.init("City"),
        .version = 0,
        .func = cityFunc,
    };

    //
    var seedNode = g.Node{
        .name = g.IdLocal.init("Seed"),
        .template = numberNodeTemplate,
    };
    seedNode.init();
    var seedInputValue = seedNode.getInput(g.IdLocal.init("value"));
    seedInputValue.value = v.Variant.createUInt64(1);
    var seedOutputValue = seedNode.getOutput(g.IdLocal.init("value"));
    seedOutputValue.reference.set("seed");

    //
    var worldWidthNode = g.Node{
        .name = g.IdLocal.init("World Width"),
        .template = numberNodeTemplate,
    };
    worldWidthNode.init();
    var worldWidthInputValue = worldWidthNode.getInput(g.IdLocal.init("value"));
    worldWidthInputValue.value = v.Variant.createUInt64(2048);
    worldWidthInputValue.value = v.Variant.createUInt64(1024 * 32);
    var worldWidthOutputValue = worldWidthNode.getOutput(g.IdLocal.init("value"));
    worldWidthOutputValue.reference.set("worldWidth");

    //
    var patchWidthNode = g.Node{
        .name = g.IdLocal.init("Patch Width"),
        .template = numberNodeTemplate,
    };
    patchWidthNode.init();
    var patchWidthInputValue = patchWidthNode.getInput(g.IdLocal.init("value"));
    patchWidthInputValue.value = v.Variant.createUInt64(256);
    patchWidthInputValue.value = v.Variant.createUInt64(1024);
    var patchWidthOutputValue = patchWidthNode.getOutput(g.IdLocal.init("value"));
    patchWidthOutputValue.reference.set("heightmapPatchWidth");

    //
    var heightmapNode = g.Node{
        .name = g.IdLocal.init("Heightmap"),
        .template = heightmapNodeTemplate,
        .allocator = std.heap.page_allocator,
        // .output_artifacts = true,
    };
    heightmapNode.init();
    var heightmapPatchWidthInputValue = heightmapNode.getInput(g.IdLocal.init("Heightmap Patch Width"));
    heightmapPatchWidthInputValue.reference = g.IdLocal.init("heightmapPatchWidth");
    var heightmapSeedInputValue = heightmapNode.getInput(g.IdLocal.init("Seed"));
    heightmapSeedInputValue.reference = g.IdLocal.init("seed");
    var heightmapWorldWidthInputValue = heightmapNode.getInput(g.IdLocal.init("World Width"));
    heightmapWorldWidthInputValue.reference = g.IdLocal.init("worldWidth");
    var heightmapOutputValue = heightmapNode.getOutput(g.IdLocal.init("Patches"));
    heightmapOutputValue.reference.set("heightmapPatches");

    //
    var cityNode = g.Node{
        .name = g.IdLocal.init("City"),
        .template = cityNodeTemplate,
        .allocator = std.heap.page_allocator,
        .output_artifacts = true,
    };
    cityNode.init();
    var cityPatchesInputValue = cityNode.getInput(g.IdLocal.init("Heightmap Patches"));
    cityPatchesInputValue.reference = g.IdLocal.init("heightmapPatches");
    var citySeedInputValue = cityNode.getInput(g.IdLocal.init("Seed"));
    citySeedInputValue.reference = g.IdLocal.init("seed");
    var cityWorldWidthInputValue = cityNode.getInput(g.IdLocal.init("World Width"));
    cityWorldWidthInputValue.reference = g.IdLocal.init("worldWidth");
    // var cityOutputValue = cityNode.getOutput(g.IdLocal.init("Cities"));
    // cityOutputValue.reference.set("cities");

    // var pcgNode = g.Node{
    //     .name = g.IdLocal.init("pcg"),
    //     .template = numberNodeTemplate,
    // };
    // pcgNode.init();
    // var pcgInputValue = pcgNode.getInput(g.IdLocal.init("value"));
    // pcgInputValue.reference.set("seed");
    // var pcgOutputValue = pcgNode.getOutput(g.IdLocal.init("value"));
    // pcgOutputValue.reference.set("pcg");

    // var addNode = g.Node{
    //     .name = g.IdLocal.init("add"),
    //     .template = addNodeTemplate,
    // };
    // addNode.init();
    // var addInputValueA = addNode.getInput(g.IdLocal.init("valueA"));
    // addInputValueA.value = 2;
    // var addInputValueB = addNode.getInput(g.IdLocal.init("valueB"));
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
