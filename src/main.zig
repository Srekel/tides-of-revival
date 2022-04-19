const std = @import("std");
const g = @import("graph.zig");
const lru = @import("lru_cache.zig");
const v = @import("variant.zig");

const HeightmapHeight = u8;

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
    count: u64 = undefined,
};

fn funcTemplateHeightmap(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = context;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patch_width_input = node.getInputByString("Heightmap Patch Width");
    const patch_width = getInputResult(patch_width_input, context).getUInt64();
    const patch_size = patch_width * patch_width;

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
        var cache = node.allocator.?.create(lru.LRUCache) catch unreachable;
        cache.init(node.allocator.?, 16);
        node.data = cache;
    }

    // var cache = @ptrCast(*lru.LRUCache, @alignCast(@alignOf(*lru.LRUCache), node.data.?));
    var cache = alignedCast(*lru.LRUCache, node.data.?);

    const patch_x_begin = @divTrunc(world_x, patch_width);
    const patch_x_end = @divTrunc((world_x + width), patch_width);
    const patch_y_begin = @divTrunc(world_y, patch_width);
    const patch_y_end = @divTrunc((world_y + height), patch_width);

    var output_data = context.frame_allocator.create(HeightmapOutputData) catch unreachable;
    output_data.count = 0;

    var patch_y = patch_y_begin;
    while (patch_y < patch_y_end) : (patch_y += 1) {
        var patch_x = patch_x_begin;
        while (patch_x < patch_x_end) : (patch_x += 1) {
            const patch_cache_key = @intCast(u64, patch_x + 10000 * patch_y);

            var heightmap: []HeightmapHeight = undefined;
            // var lru_entry: ?lru.LRUCacheEntry = null;
            var evictable_lru_key: ?lru.LRUKey = null;
            var evictable_lru_value: ?lru.LRUValue = null;
            // var heightmapOpt = cache.try_get(patch_cache_key, &lru_entry);
            var heightmapOpt = cache.try_get(patch_cache_key, &evictable_lru_key, &evictable_lru_value);
            if (heightmapOpt != null) {
                var arrptr = @ptrCast([*]HeightmapHeight, heightmapOpt.?);
                heightmap = arrptr[0..@intCast(u64, patch_size)];
            } else {
                if (evictable_lru_key != null) {
                    var arrptr = @ptrCast([*]HeightmapHeight, evictable_lru_value);
                    heightmap = arrptr[0..@intCast(u64, patch_size)];
                } else {
                    heightmap = node.allocator.?.alloc(HeightmapHeight, @intCast(u64, patch_size)) catch unreachable;
                }

                // Calc heightmap
                var x: u64 = 0;
                var y: u64 = 0;
                while (y < patch_width) : (y += 1) {
                    while (x < patch_width) : (x += 1) {
                        // var x_world = patch_x * patch_width + x;
                        // var y_world = patch_y * patch_width + y;
                        heightmap[x + y * patch_size] = @intCast(HeightmapHeight, seed);
                    }
                }

                if (evictable_lru_key != null) {
                    cache.replace(evictable_lru_key.?, patch_cache_key, heightmap.ptr);
                } else {
                    cache.put(patch_cache_key, heightmap.ptr);
                }
            }

            output_data.patches[output_data.count] = heightmap;
            output_data.count += 1;
        }
    }

    const res = .{ .success = v.Variant.createPtr(output_data, 1) };
    return res;
}

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

    // _ = numberFunc;
    // _ = numberNodeTemplate;

    var seedNode = g.Node{
        .name = g.IdLocal.init("Seed"),
        .template = numberNodeTemplate,
    };
    seedNode.init();
    var seedInputValue = seedNode.getInput(g.IdLocal.init("value"));
    seedInputValue.value = v.Variant.createUInt64(1);
    var seedOutputValue = seedNode.getOutput(g.IdLocal.init("value"));
    seedOutputValue.reference.set("seed");

    var worldWidthNode = g.Node{
        .name = g.IdLocal.init("World Width"),
        .template = numberNodeTemplate,
    };
    worldWidthNode.init();
    var worldWidthInputValue = worldWidthNode.getInput(g.IdLocal.init("value"));
    worldWidthInputValue.value = v.Variant.createUInt64(256);
    var worldWidthOutputValue = worldWidthNode.getOutput(g.IdLocal.init("value"));
    worldWidthOutputValue.reference.set("worldWidth");

    var patchWidthNode = g.Node{
        .name = g.IdLocal.init("Patch Width"),
        .template = numberNodeTemplate,
    };
    patchWidthNode.init();
    var patchWidthInputValue = patchWidthNode.getInput(g.IdLocal.init("value"));
    patchWidthInputValue.value = v.Variant.createUInt64(128);
    var patchWidthOutputValue = patchWidthNode.getOutput(g.IdLocal.init("value"));
    patchWidthOutputValue.reference.set("heightmapPatchWidth");

    var heightmapNode = g.Node{
        .name = g.IdLocal.init("Heightmap"),
        .template = heightmapNodeTemplate,
        .allocator = std.heap.page_allocator,
    };
    heightmapNode.init();
    var heightmapPatchWidthInputValue = heightmapNode.getInput(g.IdLocal.init("Heightmap Patch Width"));
    heightmapPatchWidthInputValue.reference = g.IdLocal.init("heightmapPatchWidth");
    var heightmapSeedInputValue = heightmapNode.getInput(g.IdLocal.init("Seed"));
    heightmapSeedInputValue.reference = g.IdLocal.init("seed");
    var heightmapWorldWidthInputValue = heightmapNode.getInput(g.IdLocal.init("World Width"));
    heightmapWorldWidthInputValue.reference = g.IdLocal.init("worldWidth");
    // var heightmapOutputValue = heightmapNode.getOutput(g.IdLocal.init("Patches"));
    // heightmapOutputValue.reference.set("heightmapPatches");

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
    graph.nodes.append(heightmapNode) catch unreachable;
    graph.nodes.append(patchWidthNode) catch unreachable;
    graph.nodes.append(worldWidthNode) catch unreachable;
    // graph.nodes.append(pcgNode) catch unreachable;
    // graph.nodes.append(addNode) catch unreachable;

    std.debug.print("Graph:", .{});
    graph.connect();
    graph.run(allocator);

    // const numberNode = g.NodeTemplate{};

    // graph.nodes.append(.{ .name = "hello", .version = 1, .input = .{} });
}
