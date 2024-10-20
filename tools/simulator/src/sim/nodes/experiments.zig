const std = @import("std");
const types = @import("../types.zig");
const zm = @import("zmath");

pub fn cities(world_settings: types.WorldSettings, heightmap: types.ImageF32, gradient: types.ImageF32, cities_out: *std.ArrayList([3]f32)) void {
    _ = world_settings; // autofix
    _ = gradient; // autofix

    // TODO gradient stuff
    const x = heightmap.size.width / 2;
    const z = heightmap.size.height / 2;
    const height = heightmap.get(x, z);
    cities_out.appendAssumeCapacity(.{ @floatFromInt(x), height, @floatFromInt(z) });

    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    const folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/systemes",
        .{},
    ) catch unreachable;

    std.fs.cwd().makeDir(folderbufslice) catch {};

    var output_file_data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, cities_out.items.len * 50) catch unreachable;
    var writer = output_file_data.writer();

    for (cities_out.items) |city| {
        // city,1072.000,145.403,1152.000,43
        writer.print("city,{d:.3},{d:.3},{d:.3},{}\n", .{ city[0], city[1], city[2], 0 }) catch unreachable;
    }

    const namebufslice = std.fmt.bufPrintZ(
        namebuf[0..namebuf.len],
        "{s}/cities.txt",
        .{
            folderbufslice,
        },
    ) catch unreachable;
    const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
    defer file.close();
    _ = file.writeAll(output_file_data.items) catch unreachable;
}
