const std = @import("std");
const zstbi = @import("zstbi");

const g = @import("graph/graph.zig");
const v = @import("../variant.zig");
const IdLocal = v.IdLocal;

const graph_util = @import("graph/util.zig");
const graph_city = @import("graph/city.zig");
const graph_heightmap = @import("graph/heightmap.zig");
const graph_patch_artifact = @import("graph/patch_artifact.zig");
const graph_terrain_splatmap = @import("graph/terrain_splatmap.zig");

const config_patch_width = 512;

fn funcTemplateNumber(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;

    const paramValue = if (params.len == 1) params[0].value.getUInt64() else 0;
    _ = paramValue;
    if (node.inputs[0].reference.isUnset()) {
        const value = node.inputs[0].value;
        return .{ .success = v.Variant.createUInt64(value.getUInt64()) };
    }

    const prevNodeOutput = node.inputs[0].source orelse unreachable;
    const prevNode = prevNodeOutput.node orelse unreachable;
    var res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &.{});
    const number = res.success.getUInt64();
    res.success = v.Variant.createUInt64(number);
    return res;
}

fn funcTemplateAdd(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;
    var valueA: v.Variant = undefined;
    if (node.inputs[0].reference.isUnset()) {
        valueA = node.inputs[0].value;
    } else {
        const prevNodeOutput = node.inputs[0].source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{.{
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
        const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{.{
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

// ███╗   ███╗ █████╗ ██╗███╗   ██╗
// ████╗ ████║██╔══██╗██║████╗  ██║
// ██╔████╔██║███████║██║██╔██╗ ██║
// ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
// ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub fn generate() void {
    zstbi.init(std.heap.page_allocator);
    defer zstbi.deinit();

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

    const cityNodeTemplate = graph_city.cityNodeTemplate;
    const heightmapNodeTemplate = graph_heightmap.heightmapNodeTemplate;
    const patchArtifactNodeTemplate = graph_patch_artifact.patchArtifactNodeTemplate;
    const splatmapNodeTemplate = graph_terrain_splatmap.splatmapNodeTemplate;

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
    worldWidthInputValue.value = v.Variant.createUInt64(1024 * 4);
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
    patchWidthInputValue.value = v.Variant.createUInt64(config_patch_width);
    var patchWidthOutputValue = patchWidthNode.getOutput(IdLocal.init("value"));
    patchWidthOutputValue.reference.set("heightmapPatchWidth");

    //
    var artifactPatchWidthNode = g.Node{
        .name = IdLocal.init("Artifact Patch Width"),
        .template = numberNodeTemplate,
    };
    artifactPatchWidthNode.init();
    var artifactPatchWidthInputValue = artifactPatchWidthNode.getInput(IdLocal.init("value"));
    // artifactPatchWidthInputValue.value = v.Variant.createUInt64(256);
    artifactPatchWidthInputValue.value = v.Variant.createUInt64(65);
    var artifactPatchWidthOutputValue = artifactPatchWidthNode.getOutput(IdLocal.init("value"));
    artifactPatchWidthOutputValue.reference.set("artifactPatchWidth");

    //
    var heightmapNode = g.Node{
        .name = IdLocal.init("Heightmap"),
        .template = heightmapNodeTemplate,
        .allocator = std.heap.page_allocator,
        .output_artifacts = false,
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
    var splatmapNode = blk: {
        var node = g.Node{
            .name = IdLocal.init("Splatmap"),
            .template = splatmapNodeTemplate,
            .allocator = std.heap.page_allocator,
            .output_artifacts = true,
        };
        node.init();

        node.getInput(IdLocal.init("Heightmap Patches")).reference = IdLocal.init("heightmapPatches");
        node.getInput(IdLocal.init("Heightmap Patch Width")).reference = IdLocal.init("heightmapPatchWidth");
        // node.getInput(IdLocal.init("Artifact Patch Width")).reference = IdLocal.init("artifactPatchWidth");
        node.getInput(IdLocal.init("Seed")).reference = IdLocal.init("seed");
        node.getInput(IdLocal.init("World Width")).reference = IdLocal.init("worldWidth");

        break :blk node;
    };

    //
    var heightmapPatchArtifactNode = blk: {
        var node = g.Node{
            .name = IdLocal.init("Heightmap Patch Artifact"),
            .template = patchArtifactNodeTemplate,
            .allocator = std.heap.page_allocator,
            .output_artifacts = true,
        };
        node.init();

        node.getInput(IdLocal.init("Patches")).reference = IdLocal.init("heightmapPatches");
        node.getInput(IdLocal.init("Patch Width")).reference = IdLocal.init("heightmapPatchWidth");
        node.getInput(IdLocal.init("Artifact Patch Width")).reference = IdLocal.init("artifactPatchWidth");
        node.getInput(IdLocal.init("Seed")).reference = IdLocal.init("seed");
        node.getInput(IdLocal.init("World Width")).reference = IdLocal.init("worldWidth");
        node.getInput(IdLocal.init("Artifact Folder")).value = v.Variant.createStringFixed("patch/heightmap", 1);

        break :blk node;
    };

    var splatmapPatchArtifactNode = blk: {
        var node = g.Node{
            .name = IdLocal.init("Splatmap Patch Artifact"),
            .template = patchArtifactNodeTemplate,
            .allocator = std.heap.page_allocator,
            .output_artifacts = true,
        };
        node.init();

        node.getInput(IdLocal.init("Patches")).reference = IdLocal.init("splatmapPatches");
        node.getInput(IdLocal.init("Patch Width")).reference = IdLocal.init("heightmapPatchWidth");
        node.getInput(IdLocal.init("Artifact Patch Width")).reference = IdLocal.init("artifactPatchWidth");
        node.getInput(IdLocal.init("Seed")).reference = IdLocal.init("seed");
        node.getInput(IdLocal.init("World Width")).reference = IdLocal.init("worldWidth");

        break :blk node;
    };

    //
    var cityNode = g.Node{
        .name = IdLocal.init("City"),
        .template = cityNodeTemplate,
        .allocator = std.heap.page_allocator,
        // .output_artifacts = true,
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

    graph.nodes.append(seedNode) catch unreachable;
    graph.nodes.append(patchWidthNode) catch unreachable;
    graph.nodes.append(artifactPatchWidthNode) catch unreachable;
    graph.nodes.append(worldWidthNode) catch unreachable;
    graph.nodes.append(heightmapNode) catch unreachable;
    // graph.nodes.append(splatmapNode) catch unreachable;
    graph.nodes.append(cityNode) catch unreachable;
    graph.nodes.append(heightmapPatchArtifactNode) catch unreachable;
    // graph.nodes.append(splatmapPatchArtifactNode) catch unreachable;
    // graph.nodes.append(pcgNode) catch unreachable;
    // graph.nodes.append(addNode) catch unreachable;
    _ = splatmapNode;
    // _ = cityNode;
    _ = splatmapPatchArtifactNode;

    std.debug.print("Graph:", .{});
    graph.connect();
    graph.run(allocator);
}
