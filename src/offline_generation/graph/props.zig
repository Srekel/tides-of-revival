const std = @import("std");
const img = @import("zigimg");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const config = @import("../../config.zig");
const IdLocal = v.IdLocal;
const tides_math = @import("../../core/math.zig");

const graph_util = @import("util.zig");
const getInputResult = graph_util.getInputResult;

pub const Prop = struct {
    id: IdLocal,
    pos: [3]f32,
    rot: f32,
};

pub const PropList = []Prop;

pub fn funcTemplateProps(node: *g.Node, output: *g.NodeOutput, context: *g.GraphContext, params: []g.NodeFuncParam) g.NodeFuncResult {
    _ = output;
    _ = params;

    const world_width_input = node.getInputByString("World Width");
    const world_width = getInputResult(world_width_input, context).getUInt64();

    const forest_props_input = node.getInputByString("Forest Props");
    const city_props_input = node.getInputByString("City Props");

    std.fs.cwd().makeDir("content/patch") catch {};
    std.fs.cwd().makeDir("content/patch/props") catch {};

    const props_city: []Prop = city_blk: {
        const prevNodeOutput = city_props_input.source orelse unreachable;
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
            const foo: []Prop = &.{};
            break :city_blk foo;
        }

        const props_city = res.success.getSlice(Prop, 1);
        break :city_blk props_city;
    };

    const PROPS_LOD = 1;
    const PROPS_PATCH_SIZE = config.patch_size * std.math.pow(u32, 2, PROPS_LOD);
    const PATCH_COUNT = world_width / PROPS_PATCH_SIZE;
    for (0..PATCH_COUNT) |patch_z| {
        for (0..PATCH_COUNT) |patch_x| {
            const patch_x_world = patch_x * PROPS_PATCH_SIZE;
            const patch_z_world = patch_z * PROPS_PATCH_SIZE;
            const props_forest = forest_blk: {
                const prevNodeOutput = forest_props_input.source orelse unreachable;
                const prevNode = prevNodeOutput.node orelse unreachable;
                const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                    .{
                        .name = IdLocal.init("world_x"),
                        .value = v.Variant.createUInt64(patch_x_world),
                    },
                    .{
                        .name = IdLocal.init("world_z"),
                        .value = v.Variant.createUInt64(patch_z_world),
                    },
                    .{
                        .name = IdLocal.init("width"),
                        .value = v.Variant.createUInt64(PROPS_PATCH_SIZE),
                    },
                    .{
                        .name = IdLocal.init("height"),
                        .value = v.Variant.createUInt64(PROPS_PATCH_SIZE),
                    },
                }));

                if (res != .success) {
                    const foo: []Prop = &.{};
                    break :forest_blk foo;
                }

                const props_forest = res.success.getSlice(Prop, 1);
                break :forest_blk props_forest;
            };

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

                if (props_forest.len == 0) {
                    std.fs.cwd().deleteFile(namebufslice) catch {};
                    continue;
                }

                const remap_file = std.fs.cwd().createFile(
                    namebufslice,
                    .{ .read = true },
                ) catch unreachable;
                defer remap_file.close();

                blk_tree: for (props_forest) |prop_tree| {
                    const patch_x_world_f = @intToFloat(f32, patch_x_world);
                    const patch_z_world_f = @intToFloat(f32, patch_z_world);
                    const patch_x_world_end_f = patch_x_world_f + @intToFloat(f32, PROPS_PATCH_SIZE);
                    _ = patch_x_world_end_f;
                    const patch_z_world_end_f = patch_z_world_f + @intToFloat(f32, PROPS_PATCH_SIZE);
                    _ = patch_z_world_end_f;
                    for (props_city) |prop_city| {
                        if (tides_math.dist3_xz(prop_city.pos, prop_tree.pos) < 30) {
                            continue :blk_tree;
                        }
                    }

                    const prop_slice = std.fmt.bufPrintZ(
                        namebuf[0..namebuf.len],
                        "tree,{d:.3},{d:.3},{d:.3},{d:.3}\n",
                        .{
                            prop_tree.pos[0], prop_tree.pos[1], prop_tree.pos[2], prop_tree.rot,
                        },
                    ) catch unreachable;
                    const bytes_written = remap_file.writeAll(prop_slice) catch unreachable;
                    _ = bytes_written;
                }

                const patch_x_world_f = @intToFloat(f32, patch_x_world);
                const patch_z_world_f = @intToFloat(f32, patch_z_world);
                const patch_x_world_end_f = patch_x_world_f + @intToFloat(f32, PROPS_PATCH_SIZE);
                const patch_z_world_end_f = patch_z_world_f + @intToFloat(f32, PROPS_PATCH_SIZE);
                for (props_city) |prop| {
                    if (prop.pos[0] < patch_x_world_f or prop.pos[0] >= patch_x_world_end_f) {
                        continue;
                    }
                    if (prop.pos[2] < patch_z_world_f or prop.pos[2] >= patch_z_world_end_f) {
                        continue;
                    }

                    const prop_slice = std.fmt.bufPrintZ(
                        namebuf[0..namebuf.len],
                        "{s},{d:.3},{d:.3},{d:.3},{d:.3}\n",
                        .{
                            prop.id.toString(), prop.pos[0], prop.pos[1], prop.pos[2], prop.rot,
                        },
                    ) catch unreachable;
                    const bytes_written = remap_file.writeAll(prop_slice) catch unreachable;
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

pub const propsFunc = g.NodeFuncTemplate{
    .name = IdLocal.init("props"),
    .version = 0,
    .func = &funcTemplateProps,
    .inputs = ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
        ++
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("Forest Props") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("City Props") }}) //
        ++ //
        ([_]g.NodeInputTemplate{.{}} ** 13),
    .outputs = ([_]g.NodeOutputTemplate{.{ .name = IdLocal.init("Props") }}) //
        ++ //
        ([_]g.NodeOutputTemplate{.{}} ** 15),
};

pub const propsNodeTemplate = g.NodeTemplate{
    .name = IdLocal.init("Props"),
    .version = 0,
    .func = propsFunc,
};
