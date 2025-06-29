const std = @import("std");

// UTIL
pub fn loadFile(path: []const u8, buf: []u8) []const u8 {
    var buf2: [256]u8 = undefined;
    const path2 = std.fs.cwd().realpath(".", &buf2) catch unreachable;
    std.log.info("LOL {s}", .{path2});
    std.log.info("LOL {s}", .{path});
    const data = std.fs.cwd().readFile(path, buf) catch unreachable;
    return data;
}

pub fn writeFile(data: anytype, name: []const u8) void {
    var buf: [256]u8 = undefined;
    const filepath = std.fmt.bufPrintZ(&buf, "{s}.zig", .{name}) catch unreachable;
    const file = std.fs.cwd().createFile(
        filepath,
        .{ .read = true },
    ) catch unreachable;
    defer file.close();

    const bytes_written = file.writeAll(data) catch unreachable;
    _ = bytes_written; // autofix
}

pub fn hash(str: []const u8) u64 {
    return std.hash.Wyhash.hash(0, str);
}

pub fn print(buf: []u8, comptime fmt: []const u8, args: anytype) []u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch unreachable;
}

pub fn write(writer: anytype, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024 * 4]u8 = undefined;
    const str = print(&buf, fmt, args);
    writer.writeAll(str) catch unreachable;
}

pub fn writeLine(writer: anytype, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024 * 4]u8 = undefined;
    const str = print(&buf, fmt, args);
    writer.writeAll(str) catch unreachable;
    writer.writeAll("\n") catch unreachable;
}

pub fn writeEmptyLine(writer: anytype) void {
    writer.writeAll("\n") catch unreachable;
}
