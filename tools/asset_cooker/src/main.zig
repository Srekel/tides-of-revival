const std = @import("std");
const args = @import("args");

const TextureFormat = enum {
    BC1_UNORM,
    BC1_UNORM_SRGB,
    BC3_UNORM,
    BC5_UNORM,
};

const TextureInfoV1 = struct {
    source_path: []const u8,
    destination_path: []const u8,
    width: ?u32,
    height: ?u32,
    mip_count: u32,
    srgb: bool,
    format: TextureFormat,
};

pub fn main() !void {
    const parsed_args = args.parseForCurrentProcess(struct {
        input: []const u8 = "",
        output: []const u8 = "",

        pub const shorthands = .{
            .i = "input",
            .o = "output",
        };
    }, std.heap.page_allocator, .print) catch unreachable;
    defer parsed_args.deinit();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    std.log.debug("--input {s}", .{parsed_args.options.input});
    std.log.debug("--output {s}", .{parsed_args.options.output});

    // Parse the file, assume texture for now
    var file = try std.fs.cwd().openFile(parsed_args.options.input, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var texture_info = std.mem.zeroes(TextureInfoV1);
    texture_info.destination_path = try arena.dupe(u8, parsed_args.options.output);

    var buffer: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        var splits = std.mem.splitScalar(u8, line, ':');
        const tag = splits.first();

        if (std.mem.eql(u8, tag, "version")) {
            const version = splits.next().?;
            std.log.debug("Version: '{s}'", .{version[1..]});
            std.debug.assert(std.mem.eql(u8, version[1..], "1"));
            continue;
        }

        if (std.mem.eql(u8, tag, "source")) {
            const source = splits.next().?;
            texture_info.source_path = try arena.dupe(u8, source[1..]);
            std.log.debug("Source Path: '{s}'", .{texture_info.source_path});
            continue;
        }

        if (std.mem.eql(u8, tag, "width")) {
            const width = splits.next().?;
            texture_info.width = try std.fmt.parseInt(u32, width[1..], 10);
            std.log.debug("Width: '{d}'", .{texture_info.width.?});
            continue;
        }

        if (std.mem.eql(u8, tag, "height")) {
            const height = splits.next().?;
            texture_info.height = try std.fmt.parseInt(u32, height[1..], 10);
            std.log.debug("Height: '{d}'", .{texture_info.height.?});
            continue;
        }

        if (std.mem.eql(u8, tag, "mip_count")) {
            const mip_count = splits.next().?;
            texture_info.mip_count = try std.fmt.parseInt(u32, mip_count[1..], 10);
            std.log.debug("Mip Count: '{d}'", .{texture_info.mip_count});
            continue;
        }

        if (std.mem.eql(u8, tag, "srgb")) {
            const srgb = splits.next().?;
            if (std.mem.eql(u8, srgb[1..], "true")) {
                texture_info.srgb = true;
            } else {
                texture_info.srgb = false;
            }

            std.log.debug("sRGB: '{}'", .{texture_info.srgb});
            continue;
        }

        if (std.mem.eql(u8, tag, "format")) {
            const format = splits.next().?;
            if (std.mem.eql(u8, format[1..], "BC1_UNORM")) {
                texture_info.format = .BC1_UNORM;
            } else if (std.mem.eql(u8, format[1..], "BC1_UNORM_SRGB")) {
                texture_info.format = .BC1_UNORM_SRGB;
            } else if (std.mem.eql(u8, format[1..], "BC3_UNORM")) {
                texture_info.format = .BC3_UNORM;
            } else if (std.mem.eql(u8, format[1..], "BC5_UNORM")) {
                texture_info.format = .BC5_UNORM;
            } else {
                std.debug.panic("Unsupported format '{s}'", .{format[1..]});
            }

            std.log.debug("Format: '{}'", .{texture_info.format});
            continue;
        }
    }

    try executeTextureConversionV1(&texture_info, arena);
}

fn executeTextureConversionV1(desc: *TextureInfoV1, arena: std.mem.Allocator) !void {
    var argv = std.ArrayList([]const u8).init(arena);
    try argv.append("tools/binaries/texconv/texconv.exe");
    try argv.append("-y");
    try argv.append("-l");
    try argv.append("-nologo");
    try argv.append("-sepalpha");
    try argv.append("-dx10");

    try argv.append("-f");
    switch (desc.format) {
        .BC1_UNORM => {
            try argv.append("BC1_UNORM");
        },
        .BC1_UNORM_SRGB => {
            try argv.append("BC1_UNORM_SRGB");
        },
        .BC3_UNORM => {
            try argv.append("BC3_UNORM");
        },
        .BC5_UNORM => {
            try argv.append("BC5_UNORM");
        },
    }

    if (desc.srgb) {
        try argv.append("-srgb");
    }

    if (desc.mip_count > 0) {
        try argv.append("-m");
        var buf: [8]u8 = undefined;
        try argv.append(try std.fmt.bufPrint(&buf, "{d}", .{desc.mip_count}));
    }

    if (desc.width) |width| {
        try argv.append("-w");
        var buf: [8]u8 = undefined;
        try argv.append(try std.fmt.bufPrint(&buf, "{d}", .{width}));
    }

    if (desc.height) |height| {
        try argv.append("-h");
        var buf: [8]u8 = undefined;
        try argv.append(try std.fmt.bufPrint(&buf, "{d}", .{height}));
    }

    try argv.append("-o");
    try argv.append(desc.destination_path);
    try argv.append(desc.source_path);

    var cmd = std.process.Child.init(@ptrCast(argv.items), std.heap.page_allocator);
    try cmd.spawn();

    const term = try cmd.wait();
    std.debug.assert(term == .Exited);
}
