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
        .id = IdLocal.init("heightmap"),
        // .dependenciesFn = heightmapDependencies,
        .loadFn = heightmapLoad,
    });

    _ = world_patch_mgr.registerPatchType(.{
        .id = IdLocal.init("splatmap"),
        .loadFn = splatmapLoad,
    });

    _ = world_patch_mgr.registerPatchType(.{
        .id = IdLocal.init("props"),
        .loadFn = propsLoad,
    });
}

// ██╗  ██╗███████╗██╗ ██████╗ ██╗  ██╗████████╗███╗   ███╗ █████╗ ██████╗
// ██║  ██║██╔════╝██║██╔════╝ ██║  ██║╚══██╔══╝████╗ ████║██╔══██╗██╔══██╗
// ███████║█████╗  ██║██║  ███╗███████║   ██║   ██╔████╔██║███████║██████╔╝
// ██╔══██║██╔══╝  ██║██║   ██║██╔══██║   ██║   ██║╚██╔╝██║██╔══██║██╔═══╝
// ██║  ██║███████╗██║╚██████╔╝██║  ██║   ██║   ██║ ╚═╝ ██║██║  ██║██║
// ╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

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
        "content/patch/heightmap/lod{}/heightmap_x{}_y{}.png",
        .{
            patch.lookup.lod,
            patch.patch_x,
            patch.patch_z,
        },
    ) catch unreachable;

    const heightmap_asset_id = IdLocal.init(heightmap_path);
    const heightmap_data = ctx.asset_mgr.loadAssetBlocking(heightmap_asset_id, .instant_blocking);
    var heightmap_image = zstbi.Image.loadFromMemory(heightmap_data, 1) catch unreachable;
    defer heightmap_image.deinit();

    var range_namebuf: [256]u8 = undefined;
    const range_path = std.fmt.bufPrintZ(
        range_namebuf[0..range_namebuf.len],
        "content/patch/heightmap/lod{}/heightmap_x{}_y{}.txt",
        .{
            patch.lookup.lod,
            patch.patch_x,
            patch.patch_z,
        },
    ) catch unreachable;

    const range_asset_id = IdLocal.init(range_path);
    const range_data = ctx.asset_mgr.loadAssetBlocking(range_asset_id, .instant_blocking);
    const range_str_comma = std.mem.indexOfScalar(u8, range_data, ","[0]).?;
    const range_low_str = range_data[0..range_str_comma];
    const range_low = std.fmt.parseFloat(f32, range_low_str) catch unreachable;
    const range_high_str = range_data[range_str_comma + 1 ..];
    const range_high = std.fmt.parseFloat(f32, range_high_str) catch unreachable;
    const diff = range_high - range_low;
    _ = diff;

    var patch_data: []f32 = ctx.allocator.alloc(f32, config.patch_samples) catch unreachable;
    for (heightmap_image.data, patch_data) |height_image, *height_patch| {
        const height_image_0_255 = @as(f32, @floatFromInt(height_image));
        const height_0_65535 = zm.mapLinearV(height_image_0_255, 0, 255, range_low, range_high);
        // _ = height_0_65535;
        height_patch.* = zm.mapLinearV(height_0_65535, 0, 65535, config.terrain_min, config.terrain_max);
    }

    patch.data = std.mem.sliceAsBytes(patch_data);
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

// ███████╗██████╗ ██╗      █████╗ ████████╗███╗   ███╗ █████╗ ██████╗
// ██╔════╝██╔══██╗██║     ██╔══██╗╚══██╔══╝████╗ ████║██╔══██╗██╔══██╗
// ███████╗██████╔╝██║     ███████║   ██║   ██╔████╔██║███████║██████╔╝
// ╚════██║██╔═══╝ ██║     ██╔══██║   ██║   ██║╚██╔╝██║██╔══██║██╔═══╝
// ███████║██║     ███████╗██║  ██║   ██║   ██║ ╚═╝ ██║██║  ██║██║
// ╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

fn splatmapLoad(patch: *world_patch_manager.Patch, ctx: world_patch_manager.PatchTypeContext) void {
    var splatmap_namebuf: [256]u8 = undefined;
    const splatmap_path = std.fmt.bufPrintZ(
        splatmap_namebuf[0..splatmap_namebuf.len],
        "content/patch/splatmap/lod{}/splatmap_x{}_y{}.png",
        .{
            patch.lookup.lod,
            patch.lookup.patch_x,
            patch.lookup.patch_z,
        },
    ) catch unreachable;

    const splatmap_asset_id = IdLocal.init(splatmap_path);
    const splatmap_data = ctx.asset_mgr.loadAssetBlocking(splatmap_asset_id, .instant_blocking);
    var splatmap_image = zstbi.Image.loadFromMemory(splatmap_data, 1) catch unreachable;
    defer splatmap_image.deinit();

    var data = ctx.allocator.alloc(u8, splatmap_image.data.len) catch unreachable;
    std.mem.copy(u8, data, splatmap_image.data);
    patch.data = data;
}

// ██████╗ ██████╗  ██████╗ ██████╗ ███████╗
// ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝
// ██████╔╝██████╔╝██║   ██║██████╔╝███████╗
// ██╔═══╝ ██╔══██╗██║   ██║██╔═══╝ ╚════██║
// ██║     ██║  ██║╚██████╔╝██║     ███████║
// ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

fn propsLoad(patch: *world_patch_manager.Patch, ctx: world_patch_manager.PatchTypeContext) void {
    var props_namebuf: [256]u8 = undefined;
    const props_path = std.fmt.bufPrintZ(
        props_namebuf[0..props_namebuf.len],
        "content/patch/props/lod{}/props_x{}_y{}.txt",
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

    const Prop = struct {
        id: IdLocal,
        pos: [3]f32,
        rot: f32,
    };

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

    patch.data = std.mem.sliceAsBytes(props.items);
}
