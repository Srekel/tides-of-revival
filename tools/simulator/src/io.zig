const std = @import("std");

pub fn writeFile(data: anytype, filepath: []const u8) void {
    const file = std.fs.cwd().createFile(
        filepath,
        .{ .read = true },
    ) catch unreachable;
    defer file.close();

    const bytes_written = file.writeAll(data) catch unreachable;
    _ = bytes_written; // autofix
}
