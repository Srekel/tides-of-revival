const std = @import("std");
const io = std.io;
const File = io.File;

pub const TidesFile = struct {
    // os_file: *File,
    // reader: io.BufferedReader(4096, File.Reader),
    // stream: io.BufferedReader(4096, File.Reader).Reader,
    buffer: [1024]u8,
    data: std.ArrayList(u8),
    cursor: u64,
};

pub fn openFile(path: []const u8, out_file: *TidesFile, allocator: std.mem.Allocator) void {
    // out_file.os_file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
    // out_file.reader = std.io.bufferedReader(out_file.os_file.reader());
    // out_file.stream = out_file.reader.reader();

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const file_stat = file.stat() catch unreachable;
    out_file.file_data.initCapacity(allocator, file_stat.size);
    out_file.file_data.resize(out_file.file_data.capacity);
    file.readAll(out_file.file_data.items);

    // var buf_reader = std.io.bufferedReader(file.reader());
    // var in_stream = buf_reader.reader();
    // _ = in_stream; // autofix
    // in_stream.readAllArrayList(out_file.file_data, max_append_size: usize)
}

pub fn closeFile(file: *TidesFile) void {
    // file.os_file.close();
    file.file_data.deinit();
}

pub fn peekUntilDelimiter(file: *TidesFile, delimiter: u8) []const u8 {
    _ = delimiter; // autofix
    var cursor = file.cursor;
    _ = cursor; // autofix

}

pub fn getKey(file: *TidesFile, indent: u32) ?[]const u8 {
    for (0..indent) |_| {}
    file.stream.readUntilDelimiterOrEof(&file.buffer, ':');
    file.stream.skipUntilDelimiterOrEof('\n');
}
