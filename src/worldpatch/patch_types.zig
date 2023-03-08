const std = @import("std");
const zm = @import("zmath");
const zstbi = @import("zstbi");
const IdLocal = @import("../variant.zig").IdLocal;
const config = @import("../config.zig");
const world_patch_manager = @import("world_patch_manager.zig");

// const zigimg = @import("zigimg");

pub fn registerPatchTypes(world_patch_mgr: *world_patch_manager.WorldPatchManager) void {
    _ = world_patch_mgr.registerPatchType(.{
        .id = IdLocal.init("heightmap"),
        .loadFn = heightmapLoad,
    });
}

// ██╗  ██╗███████╗██╗ ██████╗ ██╗  ██╗████████╗███╗   ███╗ █████╗ ██████╗
// ██║  ██║██╔════╝██║██╔════╝ ██║  ██║╚══██╔══╝████╗ ████║██╔══██╗██╔══██╗
// ███████║█████╗  ██║██║  ███╗███████║   ██║   ██╔████╔██║███████║██████╔╝
// ██╔══██║██╔══╝  ██║██║   ██║██╔══██║   ██║   ██║╚██╔╝██║██╔══██║██╔═══╝
// ██║  ██║███████╗██║╚██████╔╝██║  ██║   ██║   ██║ ╚═╝ ██║██║  ██║██║
// ╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

fn heightmapLoad(patch: *world_patch_manager.Patch, ctx: world_patch_manager.PatchTypeLoadContext) void {
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
    const heightmap_data = ctx.asset_manager.loadAssetBlocking(heightmap_asset_id, .instant_blocking);
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
    const range_data = ctx.asset_manager.loadAssetBlocking(range_asset_id, .instant_blocking);
    const range_str_comma = std.mem.indexOfScalar(u8, range_data, ","[0]).?;
    const range_low_str = range_data[0..range_str_comma];
    const range_low = std.fmt.parseFloat(f32, range_low_str) catch unreachable;
    const range_high_str = range_data[range_str_comma + 1 ..];
    const range_high = std.fmt.parseFloat(f32, range_high_str) catch unreachable;
    const diff = range_high - range_low;
    _ = diff;

    var patch_data: []f32 = ctx.allocator.alloc(f32, config.patch_samples) catch unreachable;
    for (heightmap_image.data, patch_data) |height_image, *height_patch| {
        const height_image_0_255 = @intToFloat(f32, height_image);
        const height_0_65535 = zm.map_linearV(height_image_0_255, 0, 255, range_low, range_high);
        // _ = height_0_65535;
        height_patch.* = zm.map_linearV(height_0_65535, 0, 65535, config.terrain_min, config.terrain_max);
    }

    patch.data = std.mem.sliceAsBytes(patch_data);
    // std.log.debug("loaded patch ({any},{any}) type:{any}, lod:{any}", .{
    //     patch.lookup.patch_x,
    //     patch.lookup.patch_z,
    //     patch.patch_type_id,
    //     patch.highest_prio,
    // });
}
