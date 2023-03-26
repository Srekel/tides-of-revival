const std = @import("std");
const img = @import("zigimg");

const g = @import("graph.zig");
const lru = @import("../../lru_cache.zig");
const v = @import("../../variant.zig");
const config = @import("../../config.zig");
const IdLocal = v.IdLocal;

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

    std.fs.cwd().makeDir("content/patch") catch {};
    std.fs.cwd().makeDir("content/patch/props") catch {};

    const PROPS_LOD = 1;
    const PROPS_PATCH_SIZE = config.patch_size * std.math.pow(u32, 2, PROPS_LOD);
    const PATCH_COUNT = world_width / PROPS_PATCH_SIZE;
    for (0..PATCH_COUNT) |patch_z| {
        for (0..PATCH_COUNT) |patch_x| {
            const props = forest_blk: {
                const prevNodeOutput = forest_props_input.source orelse unreachable;
                const prevNode = prevNodeOutput.node orelse unreachable;
                const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &([_]g.NodeFuncParam{
                    .{
                        .name = IdLocal.init("world_x"),
                        .value = v.Variant.createUInt64(patch_x * PROPS_PATCH_SIZE),
                    },
                    .{
                        .name = IdLocal.init("world_z"),
                        .value = v.Variant.createUInt64(patch_z * PROPS_PATCH_SIZE),
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

                const props = res.success.getSlice(Prop, 1);
                break :forest_blk props;
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

                if (props.len == 0) {
                    std.fs.cwd().deleteFile(namebufslice) catch {};
                    continue;
                }

                const remap_file = std.fs.cwd().createFile(
                    namebufslice,
                    .{ .read = true },
                ) catch unreachable;
                defer remap_file.close();

                for (props) |prop| {
                    const prop_slice = std.fmt.bufPrintZ(
                        namebuf[0..namebuf.len],
                        "prop,{d:.3},{d:.3},{d:.3},{d:.3}\n",
                        .{
                            prop.pos[0], prop.pos[1], prop.pos[2], prop.rot,
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
        ([_]g.NodeInputTemplate{.{ .name = IdLocal.init("World Width") }}) //
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
