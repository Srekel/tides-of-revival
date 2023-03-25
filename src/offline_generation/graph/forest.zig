const std = @import("std");
const img = @import("zigimg");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const IdLocal = v.IdLocal;

const graph_util = @import("util.zig");
const graph_heightmap = @import("heightmap.zig");
const getInputResult = graph_util.getInputResult;
const HeightmapOutputData = graph_heightmap.HeightmapOutputData;
const Pos = [2]i64;

const config_patch_width = 512;

pub fn funcTemplateForest(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const patches_input = node.getInputByString("Heightmap Patches");

    const patches = patch_blk: {
        const prevNodeOutput = patches_input.source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
            .{
                .name = IdLocal.init("world_x"),
                .value = v.Variant.createUInt64(0),
            },
            .{
                .name = IdLocal.init("world_z"),
                .value = v.Variant.createUInt64(0),
            },
            .{
                .name = IdLocal.init("width"),
                .value = v.Variant.createUInt64(world_width),
            },
            .{
                .name = IdLocal.init("height"),
                .value = v.Variant.createUInt64(world_width),
            },
        }));

        if (res != .success) {
            unreachable;
        }

        const data = res.success.getPtr(HeightmapOutputData, 1);
        break :patch_blk data;
    };

    const Tree = struct {
        pos: [3]f32,
        rot: f32,
    };

    std.fs.cwd().makeDir("content/patch") catch {};
    std.fs.cwd().makeDir("content/patch/props") catch {};

    var rand1 = std.rand.DefaultPrng.init(0);
    var rand = rand1.random();

    const PROPS_PATCH_SIZE = 128;
    const PROPS_LOD = 1;
    const STEP = 8;
    const STEP_F = @intToFloat(f32, STEP);
    const SAMPLES = @divFloor(PROPS_PATCH_SIZE, STEP);
    const PATCH_COUNT = world_width / PROPS_PATCH_SIZE;
    for (0..PATCH_COUNT) |patch_z| {
        for (0..PATCH_COUNT) |patch_x| {
            const patch_x_f = @intToFloat(f32, patch_x);
            const patch_z_f = @intToFloat(f32, patch_z);
            var trees = std.ArrayList(Tree).initCapacity(context.frame_allocator, 1000000) catch unreachable;

            for (0..SAMPLES) |local_z| {
                for (0..SAMPLES) |local_x| {
                    const local_x_f = @intToFloat(f32, local_x);
                    const local_z_f = @intToFloat(f32, local_z);
                    const world_x = patch_x_f * PROPS_PATCH_SIZE + local_x_f * STEP_F + rand.float(f32) * STEP_F * 0.5;
                    const world_z = patch_z_f * PROPS_PATCH_SIZE + local_z_f * STEP_F + rand.float(f32) * STEP_F * 0.5;

                    // TODO: Pass in non-integer coords
                    const world_y = patches.getHeightWorld(
                        @floatToInt(u32, @floor(world_x)),
                        @floatToInt(u32, @floor(world_z)),
                    );

                    if (world_y < 180 or world_y > 230) {
                        continue;
                    }

                    if (rand.boolean()) {
                        continue;
                    }

                    trees.appendAssumeCapacity(.{
                        .pos = .{ world_x, world_y, world_z },
                        .rot = rand.float(f32) * std.math.pi * 2,
                    });
                }
            }

            if (node.output_artifacts) {
                var folderbuf: [256]u8 = undefined;
                var namebuf: [256]u8 = undefined;

                var folderbufslice = std.fmt.bufPrintZ(
                    folderbuf[0..folderbuf.len],
                    "content/patch/props/lod{}",
                    .{PROPS_LOD},
                ) catch unreachable;
                std.fs.cwd().makeDir(folderbufslice) catch {};

                const namebufslice = std.fmt.bufPrintZ(
                    namebuf[0..namebuf.len],
                    "{s}/props_x{}_y{}.txt",
                    .{
                        folderbufslice,
                        patch_x,
                        patch_z,
                    },
                ) catch unreachable;

                if (trees.items.len == 0) {
                    std.fs.cwd().deleteFile(namebufslice) catch {};
                    continue;
                }

                const remap_file = std.fs.cwd().createFile(
                    namebufslice,
                    .{ .read = true },
                ) catch unreachable;
                defer remap_file.close();

                for (trees.items) |tree| {
                    const tree_slice = std.fmt.bufPrintZ(
                        namebuf[0..namebuf.len],
                        "tree,{d:.3},{d:.3},{d:.3},{d:.3}\n",
                        .{
                            tree.pos[0], tree.pos[1], tree.pos[2], tree.rot,
                        },
                    ) catch unreachable;
                    const bytes_written = remap_file.writeAll(tree_slice) catch unreachable;
                    _ = bytes_written;
                }
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
