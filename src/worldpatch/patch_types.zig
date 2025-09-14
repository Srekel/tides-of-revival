const std = @import("std");
const zm = @import("zmath");
const zstbi = @import("zstbi");

const config = @import("../config/config.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const util = @import("../util.zig");

const world_patch_manager = @import("world_patch_manager.zig");
const PatchLookup = world_patch_manager.PatchLookup;

pub fn registerPatchTypes(world_patch_mgr: *world_patch_manager.WorldPatchManager) void {
    _ = world_patch_mgr.registerPatchType(.{
        .id = config.patch_type_heightmap,
        // .dependenciesFn = heightmapDependencies,
        .loadFn = heightmapLoad,
    });

    _ = world_patch_mgr.registerPatchType(.{
        .id = config.patch_type_props,
        .loadFn = propsLoad,
    });
}

// ██╗  ██╗███████╗██╗ ██████╗ ██╗  ██╗████████╗███╗   ███╗ █████╗ ██████╗
// ██║  ██║██╔════╝██║██╔════╝ ██║  ██║╚══██╔══╝████╗ ████║██╔══██╗██╔══██╗
// ███████║█████╗  ██║██║  ███╗███████║   ██║   ██╔████╔██║███████║██████╔╝
// ██╔══██║██╔══╝  ██║██║   ██║██╔══██║   ██║   ██║╚██╔╝██║██╔══██║██╔═══╝
// ██║  ██║███████╗██║╚██████╔╝██║  ██║   ██║   ██║ ╚═╝ ██║██║  ██║██║
// ╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

pub const Heightmap = struct {
    heightmap: [config.patch_samples]f32,
    min: f32,
    max: f32,
};

fn heightmapDependencies(
    patch_lookup: world_patch_manager.PatchLookup,
    dependencies: *[world_patch_manager.max_dependencies]PatchLookup,
    ctx: world_patch_manager.PatchTypeContext,
) []PatchLookup {
    if (patch_lookup.lod >= 2) {
        return dependencies[0..0];
    }
    _ = ctx;
    const patch_world_pos = patch_lookup.getWorldPos();
    const parent_patch = world_patch_manager.WorldPatchManager.getLookup(
        @as(f32, @floatFromInt(patch_world_pos.world_x)),
        @as(f32, @floatFromInt(patch_world_pos.world_z)),
        patch_lookup.lod + 1,
        patch_lookup.patch_type_id,
    );
    dependencies[0] = parent_patch;
    return dependencies[0..1];
}

fn heightmapLoad(patch: *world_patch_manager.Patch, ctx: world_patch_manager.PatchTypeContext) void {
    // if (patch.lookup.lod > 1) {
    var heightmap_namebuf: [256]u8 = undefined;
    const heightmap_path = std.fmt.bufPrintZ(
        heightmap_namebuf[0..heightmap_namebuf.len],
        "content/patch/heightmap/lod{}/heightmap_x{}_z{}.heightmap",
        .{
            patch.lookup.lod,
            patch.patch_x,
            patch.patch_z,
        },
    ) catch unreachable;

    const heightmap_asset_id = IdLocal.init(heightmap_path);
    const heightmap_data = ctx.asset_mgr.loadAssetBlocking(heightmap_asset_id, .instant_blocking);
    const header = util.castBytes(config.HeightmapHeader, heightmap_data);
    // const version = header.version;
    // _ = version;
    // const bitdepth = header.bitdepth;
    // _ = bitdepth;
    // const height_min = header.height_min;
    // _ = height_min;
    // const height_max = header.height_max;
    // _ = height_max;

    const height_max_mapped_edge: f32 = @floatFromInt(std.math.pow(u32, 2, 30));
    var heightmap: *Heightmap = ctx.allocator.create(Heightmap) catch unreachable;
    heightmap.min = header.height_min;
    heightmap.max = header.height_max;
    var patch_data: []f32 = heightmap.heightmap[0..];

    // EDGES
    const edges = config.HeightmapHeader.getEdgeSlices(heightmap_data);

    // Top
    for (edges.top, 0..) |height_u32, i| {
        const height_0_32bit: f64 = @floatFromInt(height_u32);
        const height = zm.mapLinearV(height_0_32bit, 0, height_max_mapped_edge, config.terrain_min, config.terrain_max);
        patch_data[i] = @floatCast(height);
    }

    // Bot
    const bot_start = config.patch_resolution * (config.patch_resolution - 1);
    for (edges.bot, 0..) |height_u32, i| {
        const height_0_32bit: f64 = @floatFromInt(height_u32);
        const height = zm.mapLinearV(height_0_32bit, 0, height_max_mapped_edge, config.terrain_min, config.terrain_max);
        patch_data[bot_start + i] = @floatCast(height);
    }

    // Left
    const left_stride = config.patch_resolution;
    for (edges.left, 0..) |height_u32, i| {
        const height_0_32bit: f64 = @floatFromInt(height_u32);
        const height = zm.mapLinearV(height_0_32bit, 0, height_max_mapped_edge, config.terrain_min, config.terrain_max);
        patch_data[i * left_stride] = @floatCast(height);
    }

    // Right
    const right_start = config.patch_resolution - 1;
    const right_stride = config.patch_resolution;
    for (edges.right, 0..) |height_u32, i| {
        const height_0_32bit: f64 = @floatFromInt(height_u32);
        const height = zm.mapLinearV(height_0_32bit, 0, height_max_mapped_edge, config.terrain_min, config.terrain_max);
        patch_data[right_start + i * right_stride] = @floatCast(height);
    }

    // INSIDES
    switch (header.bitdepth) {
        8 => {
            const insides = config.HeightmapHeader.getInsides(heightmap_data, u8);
            for (0..config.patch_resolution - 2) |patch_z| {
                for (0..config.patch_resolution - 2) |patch_x| {
                    const height_0_255: f32 = @floatFromInt(insides[patch_x + patch_z * (config.patch_resolution - 2)]);
                    const height = zm.mapLinearV(height_0_255, 0, 255, header.height_min, header.height_max);
                    const patch_index = patch_x + 1 + (patch_z + 1) * config.patch_resolution;
                    patch_data[patch_index] = height;
                }
            }
        },
        16 => {
            const insides = config.HeightmapHeader.getInsides(heightmap_data, u16);
            for (0..config.patch_resolution - 2) |patch_z| {
                for (0..config.patch_resolution - 2) |patch_x| {
                    const height_0_255: f32 = @floatFromInt(insides[patch_x + patch_z * (config.patch_resolution - 2)]);
                    const height = zm.mapLinearV(height_0_255, 0, std.math.maxInt(u16), header.height_min, header.height_max);
                    const patch_index = patch_x + 1 + (patch_z + 1) * config.patch_resolution;
                    patch_data[patch_index] = height;
                }
            }
        },
        else => unreachable,
    }
    patch.data = std.mem.asBytes(heightmap);

    // std.log.debug("loaded patch ({any},{any}) type:{any}, lod:{any}", .{
    //     patch.lookup.patch_x,
    //     patch.lookup.patch_z,
    //     patch.patch_type_id,
    //     patch.highest_prio,
    // });
    // } else {
    //     const patch_lookup_lower_lod = world_patch_manager.PatchLookup{
    //         .patch_x = patch.lookup.patch_x,
    //         .patch_z = patch.lookup.patch_z,
    //         .lod = patch.lookup.lod + 1,
    //         .patch_type_id = patch.lookup.patch_type_id,
    //     };

    //     const patch_lower_lod_opt = ctx.world_patch_mgr.tryGetPatch(patch_lookup_lower_lod, f32);
    //     if (patch_lower_lod_opt) |patchlower_lod| {
    //         _ = patchlower_lod;

    //         for (patch_data) |*height_patch| {
    //             height_patch.* = config.terrain_max / 2;
    //         }
    //         var patch_data: []f32 = ctx.allocator.alloc(f32, config.patch_samples) catch unreachable;
    //         patch.data = std.mem.sliceAsBytes(patch_data);
    //     } else if (ctx.world_patch_mgr.hasScheduled(patch_lookup_lower_lod)) {
    //         ctx.world_patch_mgr.reschedule(patch.lookup);
    //         ctx.world_patch_mgr.bumpScheduling(patch_lookup_lower_lod);
    //     } else {
    //         ctx.world_patch_mgr.addLoadRequestFromLookups(123, util.sliceOfInstance(world_patch_manager.PatchLookup, &patch.lookup));
    //     }
    // }
}

// ██████╗ ██████╗  ██████╗ ██████╗ ███████╗
// ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝
// ██████╔╝██████╔╝██║   ██║██████╔╝███████╗
// ██╔═══╝ ██╔══██╗██║   ██║██╔═══╝ ╚════██║
// ██║     ██║  ██║╚██████╔╝██║     ███████║
// ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

pub const Prop = struct {
    id: IdLocal,
    pos: [3]f32,
    rot: f32,
};

pub const Props = struct {
    list: []Prop,
};

fn propsLoad(patch: *world_patch_manager.Patch, ctx: world_patch_manager.PatchTypeContext) void {
    var props_namebuf: [256]u8 = undefined;
    const props_path = std.fmt.bufPrintZ(
        props_namebuf[0..props_namebuf.len],
        "content/patch/props/lod{}/props_x{}_z{}.txt",
        .{
            patch.lookup.lod,
            patch.lookup.patch_x,
            patch.lookup.patch_z,
        },
    ) catch unreachable;

    const props_asset_id = IdLocal.init(props_path);
    if (!ctx.asset_mgr.doesAssetExist(props_asset_id)) {
        patch.status = .nonexistent;
        return;
    }

    const props_data = ctx.asset_mgr.loadAssetBlocking(props_asset_id, .instant_blocking);
    if (props_data.len == 0) {
        patch.status = .loaded_empty;
        return;
    }

    var props = std.ArrayList(Prop).initCapacity(ctx.allocator, props_data.len / 30) catch unreachable;
    var buf_reader = std.io.fixedBufferStream(props_data);
    var in_stream = buf_reader.reader();
    var buf: [1024]u8 = undefined;
    while (in_stream.readUntilDelimiterOrEof(&buf, '\n') catch unreachable) |line| {
        var comma_curr: usize = 0;
        var comma_next: usize = std.mem.indexOfScalar(u8, line, ","[0]).?;
        const name = line[comma_curr..comma_next];

        comma_curr = comma_next + 1;
        comma_next = comma_curr + std.mem.indexOfScalar(u8, line[comma_curr..], ","[0]).?;
        const pos_x = std.fmt.parseFloat(f32, line[comma_curr..comma_next]) catch unreachable;

        comma_curr = comma_next + 1;
        comma_next = comma_curr + std.mem.indexOfScalar(u8, line[comma_curr..], ","[0]).?;
        const pos_y = std.fmt.parseFloat(f32, line[comma_curr..comma_next]) catch unreachable;

        comma_curr = comma_next + 1;
        comma_next = comma_curr + std.mem.indexOfScalar(u8, line[comma_curr..], ","[0]).?;
        const pos_z = std.fmt.parseFloat(f32, line[comma_curr..comma_next]) catch unreachable;

        comma_curr = comma_next + 1;
        const rot_y = std.fmt.parseFloat(f32, line[comma_curr..]) catch unreachable;

        const prop = Prop{
            .id = IdLocal.init(name),
            .pos = .{ pos_x, pos_y, pos_z },
            .rot = rot_y,
        };
        props.appendAssumeCapacity(prop);
    }

    var data = ctx.allocator.alignedAlloc(u8, 64, @sizeOf(Props) + @sizeOf(Prop) * props.items.len) catch unreachable;
    var props_instance = std.mem.bytesAsValue(Props, data[0..@sizeOf(Props)]);
    const proplist = std.mem.bytesAsSlice(Prop, data[@sizeOf(Props)..]);
    props_instance.list = proplist;
    @memcpy(proplist, props.items);
    patch.data = std.mem.asBytes(props_instance);
}
