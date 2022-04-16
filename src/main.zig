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

fn funcTemplateNumber(node: *g.Node, output: *g.NodeOutput, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    const paramValue = if (params.len == 1) params[0].value.getInt64() else 0;
    if (node.inputs[0].reference.isUnset()) {
        return .{ .success = v.Variant.createInt64(node.inputs[0].value.getInt64() + paramValue) };
    }

    const prevNodeOutput = node.inputs[0].source orelse unreachable;
    const prevNode = prevNodeOutput.node orelse unreachable;
    var res = prevNode.template.func.func.*(prevNode, prevNodeOutput, &.{});
    const number = res.success.getInt64() + paramValue;
    res.success.setInt64(number);
    return res;
}

fn funcTemplateAdd(node: *g.Node, output: *g.NodeOutput, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;
    _ = params;
    var valueA: v.Variant = undefined;
    if (node.inputs[0].reference.isUnset()) {
        valueA = node.inputs[0].value;
    } else {
        const prevNodeOutput = node.inputs[0].source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, &([_]g.NodeFuncParam{.{
            .name = g.IdLocal.init("number"),
            .value = v.Variant.createInt64(0),
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
        const res = prevNode.template.func.func.*(prevNode, prevNodeOutput, &([_]g.NodeFuncParam{.{
            .name = g.IdLocal.init("number"),
            .value = v.Variant.createInt64(0),
        }}));
        if (res != .success) {
            return .waiting;
        }
        valueB = res.success;
    }

    return .{ .success = valueA.getInt64() + valueB.getInt64() };
}

const HEIGHMAP_PATCH_QUERY_MAX = 32;

const HeightmapOutputData = struct {
    patches: [HEIGHMAP_PATCH_QUERY_MAX][]HeightmapHeight = undefined,
    count: u64 = undefined,
};

fn funcTemplateHeightmap(node: *g.Node, output: *g.NodeOutput, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = node;
    _ = output;

    const patch_width_input = node.getInputByString("Heightmap Patch Width");
    const patch_width = if (patch_width_input.reference.isUnset()) patch_width_input.value.getInt64() else unreachable;
    const patch_size = patch_width * patch_width;

    const seed_input = node.getInputByString("Seed");
    const seed = if (seed_input.reference.isUnset()) seed_input.value else unreachable;

    const world_x = params[0].value;
    const world_y = params[1].value;
    const width = params[2].value;
    const height = params[3].value;
    if (node.data == null) {
        var cache = node.allocator.?.create(lru.LRUCache) catch unreachable;
        cache.init(node.allocator.?, 16);
        node.data = cache;
    }

    // var cache = @ptrCast(*lru.LRUCache, @alignCast(@alignOf(*lru.LRUCache), node.data.?));
    var cache = alignedCast(*lru.LRUCache, node.data.?);

    const patch_x_begin = world_x / patch_width;
    const patch_x_end = (world_x + width) / patch_width;
    const patch_y_begin = world_y / patch_width;
    const patch_y_end = (world_y + height) / patch_width;

    var output_data = HeightmapOutputData{};
    output_data.count = 0;

    var patch_x = patch_x_begin;
    var patch_y = patch_y_begin;
    while (patch_y < patch_y_end) : (patch_y += 1) {
        while (patch_x < patch_x_end) : (patch_x += 1) {
            const patch_cache_key = @as(u64, patch_x + 10000 * patch_y);

            var heightmap: []HeightmapHeight = undefined;
            // var lru_entry: ?lru.LRUCacheEntry = null;
            var evictable_lru_key: ?lru.LRUKey = null;
            var evictable_lru_value: ?lru.LRUValue = null;
            // var heightmapOpt = cache.try_get(patch_cache_key, &lru_entry);
            var heightmapOpt = cache.try_get(patch_cache_key, &evictable_lru_key, &evictable_lru_value);
            if (heightmapOpt != null) {
                var arrptr = @ptrCast([*]HeightmapHeight, heightmapOpt.?);
                heightmap = arrptr[0..patch_size];
            } else {
                if (evictable_lru_key != null) {
                    var arrptr = @ptrCast([*]HeightmapHeight, evictable_lru_value);
                    heightmap = arrptr[0..patch_size];
                } else {
                    heightmap = node.allocator.?.alloc(HeightmapHeight, patch_size) catch unreachable;
                }

                // Calc heightmap
                var x = patch_x * patch_width;
                var y = patch_y * patch_width;
                while (y < (patch_y + 1) * patch_width) : (y += 1) {
                    while (x < (patch_x + 1) * patch_width) : (x += 1) {
                        heightmap[x + y * patch_size] = @intCast(HeightmapHeight, seed);
                    }
                }

                // if (lru_entry != null) {
                //     cache.replace(lru_entry.?.key, patch_cache_key, heightmap.ptr);
                // } else {
                //     cache.put(patch_cache_key, heightmap.ptr);
                // }

                var lol = v.Variant.createInt64(1);
                _ = lol;
            }

            output_data.patches[output_data.count] = heightmap;
            output_data.count += 1;
        }
    }

    const res = .{ .success = 1 };
    return res;
}

pub fn main() void {
    std.debug.print("LOL\n", .{});

    const numberFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("number"),
        .version = 0,
        .func = &funcTemplateNumber,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("value"), .data_type = 0 }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 15),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("value"), .data_type = 0 }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const addFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("add"),
        .version = 0,
        .func = &funcTemplateAdd,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("valueA"), .data_type = 0 }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("valueB"), .data_type = 0 }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 14),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("value"), .data_type = 0 }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const heightmapFunc = g.NodeFuncTemplate{
        .name = g.IdLocal.init("heightmap"),
        .version = 0,
        .func = &funcTemplateHeightmap,
        .inputs = ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Heightmap Patch Width"), .data_type = 0 }}) //
            ++
            ([_]g.NodeInputTemplate{.{ .name = g.IdLocal.init("Seed"), .data_type = 0 }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 14),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = g.IdLocal.init("patches"), .data_type = 0 }}) //
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
    seedInputValue.value = 1;
    var seedOutputValue = seedNode.getOutput(g.IdLocal.init("value"));
    seedOutputValue.reference.set("seed");

    var patchWidthNode = g.Node{
        .name = g.IdLocal.init("Patch Width"),
        .template = numberNodeTemplate,
    };
    patchWidthNode.init();
    var patchWidthInputValue = patchWidthNode.getInput(g.IdLocal.init("value"));
    patchWidthInputValue.value = 128;
    var patchWidthOutputValue = patchWidthNode.getOutput(g.IdLocal.init("value"));
    patchWidthOutputValue.reference.set("heightmapPatchWidth");

    var heightmapNode = g.Node{
        .name = g.IdLocal.init("Heightmap"),
        .template = heightmapNodeTemplate,
    };
    heightmapNode.init();
    var heightmapPatchWidthInputValue = heightmapNode.getInput(g.IdLocal.init("Heightmap Patch Width"));
    heightmapPatchWidthInputValue.reference = g.IdLocal.init("heightmapPatchWidth");
    var heightmapSeedInputValue = heightmapNode.getInput(g.IdLocal.init("Seed"));
    heightmapSeedInputValue.reference = g.IdLocal.init("seed");
    var heightmapOutputValue = heightmapNode.getOutput(g.IdLocal.init("value"));
    heightmapOutputValue.reference.set("heightmapPatchWidth");

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
    // graph.nodes.append(pcgNode) catch unreachable;
    // graph.nodes.append(addNode) catch unreachable;

    std.debug.print("Graph:", .{});
    graph.connect();
    graph.run(allocator);

    // const numberNode = g.NodeTemplate{};

    // graph.nodes.append(.{ .name = "hello", .version = 1, .input = .{} });
}
