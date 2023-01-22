const std = @import("std");

const g = @import("graph/graph.zig");
const lru = @import("../lru_cache.zig");
const v = @import("../variant.zig");
const IdLocal = v.IdLocal;

const img = @import("zigimg");

const zm = @import("zmath");
const znoise = @import("znoise");
const zstbi = @import("zstbi");

const graph_util = @import("graph/util.zig");
const getInputResult = graph_util.getInputResult;
const graph_city = @import("graph/city.zig");
const graph_heightmap = @import("graph/heightmap.zig");

const HeightmapHeight = u16;
const Pos = @Vector(2, i64);

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

// ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗
// ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║
// ██████╔╝███████║   ██║   ██║     ███████║
// ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║
// ██║     ██║  ██║   ██║   ╚██████╗██║  ██║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝

fn funcTemplatePatchArtifact(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    // const patch_width_input = node.getInputByString("Heightmap Patch Width");
    // const patch_width = getInputResult(patch_width_input, context).getUInt64();
    // const patch_size = (patch_width) * (patch_width);

    const artifact_patch_width_input = node.getInputByString("Artifact Patch Width");
    const artifact_patch_width = getInputResult(artifact_patch_width_input, context).getUInt64();
    // const artifact_patch_size = (artifact_patch_width) * (artifact_patch_width);

    const patches_input = node.getInputByString("Heightmap Patches");

    // var world_x: u64 = 0;
    // var world_y: u64 = 0;

    // const PATCH_CACHE_SIZE = 64 * 64;
    // if (node.data == null) {
    //     var data = node.allocator.?.create(HeightmapNodeData) catch unreachable;
    //     data.cache.init(node.allocator.?, PATCH_CACHE_SIZE);
    //     data.noise = .{
    //         .seed = @intCast(i32, seed),
    //         .fractal_type = .fbm,
    //         .frequency = 0.0001,
    //         .octaves = 20,
    //     };
    //     node.data = data;
    // }

    // var data = alignedCast(*HeightmapNodeData, node.data.?);
    // var cache = &data.cache;

    // const patch_x_begin = 0;
    // const patch_x_end = @divTrunc(world_width, patch_width);
    // const patch_y_begin = 0;
    // const patch_y_end = @divTrunc(world_width, patch_width);

    // std.debug.assert((patch_x_end - patch_x_begin) * (patch_y_end - patch_y_begin) < PATCH_CACHE_SIZE);

    // var output_data = context.frame_allocator.create(HeightmapOutputData) catch unreachable;
    // output_data.count = 0;
    // output_data.patch_width = patch_width;
    // output_data.count_x = patch_x_end - patch_x_begin;
    // output_data.count_y = patch_y_end - patch_y_begin;

    std.fs.cwd().makeDir("content/patch/lod0") catch {};
    std.fs.cwd().makeDir("content/patch/lod1") catch {};
    std.fs.cwd().makeDir("content/patch/lod2") catch {};
    std.fs.cwd().makeDir("content/patch/lod3") catch {};
    var namebuf: [256]u8 = undefined;

    // const image_width = artifact_patch_width;
    const precision = 1; // meter
    const best_lod_width = 64; // meter
    const best_lod = 0;
    const worst_lod = 3; // inclusive
    const worst_lod_width = best_lod_width * std.math.pow(u32, 2, worst_lod) / precision;
    const worst_lod_patch_count_per_side = (world_width) / worst_lod_width;
    var lod: u32 = best_lod;
    while (lod <= worst_lod) : (lod += 1) {
        const lod_pixel_stride = std.math.pow(u32, 2, lod) / precision;
        var image = zstbi.Image{
            .data = context.frame_allocator.alloc(u8, artifact_patch_width * artifact_patch_width * 2 * 1) catch unreachable,
            .width = @intCast(u32, artifact_patch_width),
            .height = @intCast(u32, artifact_patch_width),
            .num_components = 1,
            .bytes_per_component = 2,
            .bytes_per_row = 2 * @intCast(u32, artifact_patch_width),
            .is_hdr = false,
        };
        // defer image.deinit();

        var hm_patch_y: u32 = 0;
        while (hm_patch_y < worst_lod_patch_count_per_side) : (hm_patch_y += 1) {
            std.debug.print("Patch artifacts: lod{} row {}/{}\n", .{ lod, hm_patch_y, worst_lod_patch_count_per_side });
            var hm_patch_x: u32 = 0;
            while (hm_patch_x < worst_lod_patch_count_per_side) : (hm_patch_x += 1) {
                const patches = patch_blk: {
                    const prevNodeOutput = patches_input.source orelse unreachable;
                    const prevNode = prevNodeOutput.node orelse unreachable;
                    const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                        .{
                            .name = IdLocal.init("world_x"),
                            .value = v.Variant.createUInt64(hm_patch_x * worst_lod_width),
                        },
                        .{
                            .name = IdLocal.init("world_y"),
                            .value = v.Variant.createUInt64(hm_patch_y * worst_lod_width),
                        },
                        .{
                            .name = IdLocal.init("width"),
                            .value = v.Variant.createUInt64(worst_lod_width + 1),
                        },
                        .{
                            .name = IdLocal.init("height"),
                            .value = v.Variant.createUInt64(worst_lod_width + 1),
                        },
                    }));

                    if (res != .success) {
                        unreachable;
                    }

                    const data = res.success.getPtr(graph_heightmap.HeightmapOutputData, 1);
                    break :patch_blk data;
                };

                const lod_patch_count_per_side = std.math.pow(u32, 2, worst_lod - lod);
                const lod_patch_width = worst_lod_width / lod_patch_count_per_side;
                var lod_patch_y: u32 = 0;
                while (lod_patch_y < lod_patch_count_per_side) : (lod_patch_y += 1) {
                    var lod_patch_x: u32 = 0;
                    while (lod_patch_x < lod_patch_count_per_side) : (lod_patch_x += 1) {
                        var pixel_y: u32 = 0;
                        while (pixel_y < artifact_patch_width) : (pixel_y += 1) {
                            var pixel_x: u32 = 0;
                            while (pixel_x < artifact_patch_width) : (pixel_x += 1) {
                                // TODO: Need to be float
                                const world_x = @intCast(i64, hm_patch_x * worst_lod_width + lod_patch_x * lod_patch_width + pixel_x * lod_pixel_stride);
                                const world_y = @intCast(i64, hm_patch_y * worst_lod_width + lod_patch_y * lod_patch_width + pixel_y * lod_pixel_stride);
                                const height = patches.getHeight(world_x, world_y);
                                const img_i = pixel_x + pixel_y * artifact_patch_width;
                                image.data[img_i] = @intCast(u8, height >> 8);
                                image.data[img_i + 1] = @intCast(u8, height & 0xFF);
                            }
                        }

                        const namebufslice = std.fmt.bufPrintZ(
                            namebuf[0..namebuf.len],
                            "content/patch/lod{}/heightmap_x{}_y{}.png",
                            .{
                                lod,
                                hm_patch_x * lod_patch_count_per_side + lod_patch_x,
                                hm_patch_y * lod_patch_count_per_side + lod_patch_y,
                            },
                        ) catch unreachable;
                        std.debug.print("Patch artifacts: image{s} hx{} lx{} imx0:{}\n", .{
                            namebufslice,
                            hm_patch_x,
                            lod_patch_x,
                            hm_patch_x * worst_lod_width + lod_patch_y * lod_patch_width + 0 * lod_pixel_stride,
                        });
                        image.writeToFile(namebufslice, .png) catch unreachable;
                    }
                }

                // var pgm_opt: img.AllFormats.PGM.EncoderOptions = .{ .binary = true };
                // const encoder_options = img.AllFormats.ImageEncoderOptions{ .pgm = pgm_opt };
                // hmimg.writeToFilePath(namebufslice, encoder_options) catch unreachable;
            }
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

pub fn generate() void {
    std.debug.print("LOL\n", .{});

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

    const patchArtifactFunc = g.NodeFuncTemplate{
        .name = IdLocal.init("patchArtifact"),
        .version = 0,
        .func = &funcTemplatePatchArtifact,
        .inputs = ( //
            [_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patch Width") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Artifact Patch Width") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patches") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Artifact Patches") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
            ++ //
            ([_]g.NodeInputTemplate{.{}} ** 10),
        .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Patch Artifacts") }}) //
            ++ //
            ([_]g.NodeOutputTemplate{.{}} ** 15),
    };

    const cityFunc = graph_city.cityFunc;

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
    const heightmapNodeTemplate = graph_heightmap.heightmapNodeTemplate;

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


    const cityNodeTemplate = g.NodeTemplate{
        .name = IdLocal.init("City"),
        .version = 0,
        .func = cityFunc,
    };

    const patchArtifactNodeTemplate = g.NodeTemplate{
        .name = IdLocal.init("Patch Artifact"),
        .version = 0,
        .func = patchArtifactFunc,
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
    var patchArtifactNode = blk: {
        var node = g.Node{
            .name = IdLocal.init("Patch Artifact"),
            .template = patchArtifactNodeTemplate,
            .allocator = std.heap.page_allocator,
            .output_artifacts = true,
        };
        node.init();

        node.getInput(IdLocal.init("Heightmap Patches")).reference = IdLocal.init("heightmapPatches");
        node.getInput(IdLocal.init("Heightmap Patch Width")).reference = IdLocal.init("heightmapPatchWidth");
        node.getInput(IdLocal.init("Artifact Patch Width")).reference = IdLocal.init("artifactPatchWidth");
        node.getInput(IdLocal.init("Seed")).reference = IdLocal.init("seed");
        node.getInput(IdLocal.init("World Width")).reference = IdLocal.init("worldWidth");

        // node.getOutput(IdLocal.init("Patch Artifacts")).reference = IdLocal.init("patchArtifacts");

        // var artifactPatchWidthInput = node.getInput(IdLocal.init("Artifact Patch Width"));
        // artifactPatchWidthInput.reference = IdLocal.init("patchWidth");
        // var seedInput = node.getInput(IdLocal.init("Seed"));
        // seedInput.reference = IdLocal.init("seed");
        // var worldWidthInput = node.getInput(IdLocal.init("World Width"));
        // worldWidthInput.reference = IdLocal.init("worldWidth");
        // var patchesOutput = node.getOutput(IdLocal.init("Patches"));
        // patchesOutput.reference.set("patchArtifacts");
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
    graph.nodes.append(cityNode) catch unreachable;
    graph.nodes.append(patchArtifactNode) catch unreachable;
    // graph.nodes.append(pcgNode) catch unreachable;
    // graph.nodes.append(addNode) catch unreachable;

    std.debug.print("Graph:", .{});
    graph.connect();
    graph.run(allocator);

    // const numberNode = g.NodeTemplate{};

    // graph.nodes.append(.{ .name = "hello", .version = 1, .input = .{} });
}
