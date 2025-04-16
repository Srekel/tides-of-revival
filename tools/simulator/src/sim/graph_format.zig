const std = @import("std");
const tides_format = @import("tides_format.zig");

pub fn generateFile(simgraph_path: []const u8, zig_path: []const u8) void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var out = std.ArrayList(u8).init(gpa);
    defer out.deinit();
    var writer = out.writer();

    var file: tides_format.TidesFile = undefined;
    tides_format.openFile(simgraph_path, &file);
    defer tides_format.closeFile(&file);

    _ = tides_format.getKey("nodes", 0);
    tides_format.skipUntil(file, "nodes");
    while (tides_format.getKey(file, 1)) |key| {
        writeNode(key, file, writer);
    }
}

// pub fn
