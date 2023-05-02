const std = @import("std");
const img = @import("zigimg");
const znoise = @import("znoise");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const config = @import("../../config.zig");
const IdLocal = v.IdLocal;

const graph_props = @import("props.zig");
const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;
const Pos = [2]i64;

const config_patch_width = 512;

pub fn funcTemplateForest(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    // _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Heightmap Patches");

    var span_world_x: u64 = 0;
    var span_world_z: u64 = 0;
    var span_width: u64 = world_width;
    var span_height: u64 = world_width;
    if (params.len > 0 and !params[0].value.isUnset()) {
        span_world_x = params[0].value.getUInt64();
        span_world_z = params[1].value.getUInt64();
        span_width = params[2].value.getUInt64();
        span_height = params[3].value.getUInt64();
    }

    const patches = patch_blk: {
        const prevNodeOutput = patches_input.source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
            .{
                .name = IdLocal.init("world_x"),
                .value = v.Variant.createUInt64(span_world_x),
            },
            .{
                .name = IdLocal.init("world_z"),
                .value = v.Variant.createUInt64(span_world_z),
            },
            .{
                .name = IdLocal.init("width"),
                .value = v.Variant.createUInt64(span_width),
            },
            .{
                .name = IdLocal.init("height"),
                .value = v.Variant.createUInt64(span_height),
            },
        }));

        if (res != .success) {
            unreachable;
        }

        const data = res.success.getPtr(HeightmapOutputData, 1);
        break :patch_blk data;
    };

    std.fs.cwd().makeDir("content/patch") catch {};
    std.fs.cwd().makeDir("content/patch/props") catch {};

    var rand1 = std.rand.DefaultPrng.init(0);
    var rand = rand1.random();

    var trees = std.ArrayList(graph_props.Prop).initCapacity(context.frame_allocator, 100) catch unreachable;
    const tree_id = IdLocal.init("tree");

    const noise = znoise.FnlGenerator{
        .seed = @intCast(i32, 123),
        .fractal_type = .fbm,
        .frequency = 0.001,
        .octaves = 8,
    };

    const PROPS_LOD = 1;
    const PROPS_PATCH_SIZE = config.patch_size * std.math.pow(u64, 2, PROPS_LOD);
    const PROPS_PATCH_SIZE_F = @intToFloat(f32, config.patch_size * std.math.pow(u64, 2, PROPS_LOD));
    const TREE_STEP = 16;
    const TREE_STEP_F = @intToFloat(f32, TREE_STEP);
    const SAMPLES = @divFloor(PROPS_PATCH_SIZE, TREE_STEP);
    const PATCH_BEGIN_X = span_world_x / PROPS_PATCH_SIZE;
    const PATCH_BEGIN_Z = span_world_z / PROPS_PATCH_SIZE;
    const PATCH_END_X = (span_world_x + span_width) / PROPS_PATCH_SIZE;
    const PATCH_END_Z = (span_world_z + span_width) / PROPS_PATCH_SIZE;
    for (PATCH_BEGIN_Z..PATCH_END_Z) |patch_z| {
        for (PATCH_BEGIN_X..PATCH_END_X) |patch_x| {
            const patch_x_f = @intToFloat(f32, patch_x);
            const patch_z_f = @intToFloat(f32, patch_z);

            for (0..SAMPLES) |local_z| {
                for (0..SAMPLES) |local_x| {
                    const local_x_f = @intToFloat(f32, local_x);
                    const local_z_f = @intToFloat(f32, local_z);
                    const world_x = patch_x_f * PROPS_PATCH_SIZE_F + local_x_f * TREE_STEP_F + rand.float(f32) * TREE_STEP_F * 0.995;
                    const world_z = patch_z_f * PROPS_PATCH_SIZE_F + local_z_f * TREE_STEP_F + rand.float(f32) * TREE_STEP_F * 0.995;

                    // TODO: Pass in non-integer coords
                    const world_y = patches.getHeightWorld(
                        @floatToInt(u32, @floor(world_x)),
                        @floatToInt(u32, @floor(world_z)),
                    );

                    if (world_y < 10 or world_y > 230) {
                        continue;
                    }

                    if (noise.noise2(world_x, world_z) < -0.15) {
                        continue;
                    }

                    // trees.appendAssumeCapacity(.{
                    trees.append(.{
                        .id = tree_id,
                        .pos = .{ world_x, world_y, world_z },
                        .rot = rand.float(f32) * std.math.pi * 2,
                    }) catch unreachable;
                }
            }
        }
    }

    const res = .{ .success = v.Variant.createSlice(trees.items, 1) };
    return res;
}

// ███╗   ███╗ █████╗ ██╗███╗   ██╗
// ████╗ ████║██╔══██╗██║████╗  ██║
// ██╔████╔██║███████║██║██╔██╗ ██║
// ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
// ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const forestFunc = g.NodeFuncTemplate{
    .name = IdLocal.init("forest"),
    .version = 0,
    .func = &funcTemplateForest,
    .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Heightmap Patches") }}) //
        ++
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Seed") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 13),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Forest") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 15),
};

pub const forestNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("Forest"),
    .version = 0,
    .func = forestFunc,
};
