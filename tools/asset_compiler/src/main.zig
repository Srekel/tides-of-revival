const std = @import("std");
const args = @import("args");

const TextureFormat = enum {
    BC1_UNORM,
    BC1_UNORM_SRGB,
    BC3_UNORM,
    BC4_UNORM,
    BC5_UNORM,
    BC7_UNORM,
    BC7_UNORM_SRGB,
};

const TextureInfoV1 = struct {
    destination_path: []const u8,
    source_path: []const u8,
    dep_path: []const u8,
    format: TextureFormat,
    width: ?u32,
    height: ?u32,
    mip_count: ?u32,
    srgb: ?bool,
    invert_y: ?bool,
};

pub fn main() !void {
    const parsed_args = args.parseForCurrentProcess(struct {
        input: []const u8 = "",
        output: []const u8 = "",
        dep: []const u8 = "",
        @"generate-metadata": bool = false,

        pub const shorthands = .{
            .i = "input",
            .o = "output",
            .d = "dep",
        };
    }, std.heap.page_allocator, .print) catch unreachable;
    defer parsed_args.deinit();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    if (parsed_args.options.@"generate-metadata") {
        std.log.debug("Generate metadata", .{});
        try generateMetadata(arena);
        return;
    }

    var file = try std.fs.openFileAbsolute(parsed_args.options.input, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var texture_info = std.mem.zeroes(TextureInfoV1);
    texture_info.destination_path = try arena.dupe(u8, parsed_args.options.output);
    texture_info.dep_path = try arena.dupe(u8, parsed_args.options.dep);

    var buffer: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        var splits = std.mem.splitScalar(u8, line, ':');
        const tag = splits.first();

        if (std.mem.eql(u8, tag, "version")) {
            const version = splits.next().?;
            std.debug.assert(std.mem.eql(u8, version[1..], "1"));
            continue;
        }

        if (std.mem.eql(u8, tag, "source")) {
            const source = splits.next().?;
            texture_info.source_path = try arena.dupe(u8, source[1..]);
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
            } else if (std.mem.eql(u8, format[1..], "BC4_UNORM")) {
                texture_info.format = .BC4_UNORM;
            } else if (std.mem.eql(u8, format[1..], "BC5_UNORM")) {
                texture_info.format = .BC5_UNORM;
            } if (std.mem.eql(u8, format[1..], "BC7_UNORM")) {
                texture_info.format = .BC7_UNORM;
            } else if (std.mem.eql(u8, format[1..], "BC7_UNORM_SRGB")) {
                texture_info.format = .BC7_UNORM_SRGB;
            } else {
                std.debug.panic("Unsupported format '{s}'", .{format[1..]});
            }

            continue;
        }

        if (std.mem.eql(u8, tag, "width")) {
            const width = splits.next().?;
            texture_info.width = try std.fmt.parseInt(u32, width[1..], 10);
            continue;
        }

        if (std.mem.eql(u8, tag, "height")) {
            const height = splits.next().?;
            texture_info.height = try std.fmt.parseInt(u32, height[1..], 10);
            continue;
        }

        if (std.mem.eql(u8, tag, "mip_count")) {
            const mip_count = splits.next().?;
            texture_info.mip_count = try std.fmt.parseInt(u32, mip_count[1..], 10);
            continue;
        }

        if (std.mem.eql(u8, tag, "srgb")) {
            const srgb = splits.next().?;
            if (std.mem.eql(u8, srgb[1..], "true")) {
                texture_info.srgb = true;
            } else {
                texture_info.srgb = false;
            }

            continue;
        }

        if (std.mem.eql(u8, tag, "invert_y")) {
            const invert_y = splits.next().?;
            if (std.mem.eql(u8, invert_y[1..], "true")) {
                texture_info.invert_y = true;
            } else {
                texture_info.invert_y = false;
            }

            continue;
        }
    }

    try executeTextureConversionV1(&texture_info, arena);
}

fn executeTextureConversionV1(desc: *TextureInfoV1, arena: std.mem.Allocator) !void {
    // Build texconv.exe process argument list
    // =======================================
    var argv = std.ArrayList([]const u8).init(arena);

    // Executable path
    // NOTE: std.fs.cwd() is tools/binaries/asset_compiler/
    const cwd_absolute = try std.fs.cwd().realpathAlloc(arena, ".");
    var texconv_path_buffer: [1024]u8 = undefined;
    const textcov_absolute_path = try std.fmt.bufPrint(&texconv_path_buffer, "{s}/../texconv/texconv.exe", .{cwd_absolute});
    try argv.append(textcov_absolute_path);

    // Override existing output file
    try argv.append("-y");

    // Force lowercase out file name
    try argv.append("-l");

    // Do not display texconv.exe logo
    try argv.append("-nologo");

    // Use a single processor
    // AssetCooker is running one command per processor, if they all try to use all the processors, it ends up a lot slower!
    try argv.append("-singleproc");

    // Compress alpha separately
    try argv.append("-sepalpha");

    // Generate DX10 headers
    try argv.append("-dx10");

    // Specify the output image format
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
        .BC4_UNORM => {
            try argv.append("BC4_UNORM");
        },
        .BC5_UNORM => {
            try argv.append("BC5_UNORM");
        },
        .BC7_UNORM => {
            try argv.append("BC7_UNORM");
        },
        .BC7_UNORM_SRGB => {
            try argv.append("BC7_UNORM_SRGB");
        },
    }

    // Optional: Specify the output image width
    if (desc.width) |width| {
        try argv.append("-w");
        var buf: [8]u8 = undefined;
        try argv.append(try std.fmt.bufPrint(&buf, "{d}", .{width}));
    }

    // Optional: Specify the output image height
    if (desc.height) |height| {
        try argv.append("-h");
        var buf: [8]u8 = undefined;
        try argv.append(try std.fmt.bufPrint(&buf, "{d}", .{height}));
    }

    // Optional: Specify a desired mip map count
    if (desc.mip_count) |mip_count| {
        if (mip_count > 0) {
            try argv.append("-m");
            var buf: [8]u8 = undefined;
            try argv.append(try std.fmt.bufPrint(&buf, "{d}", .{mip_count}));
        }
    }

    // Optional: Specify the sRGB (input & output) flag
    if (desc.srgb) |srgb| {
        if (srgb) {
            try argv.append("-srgb");
        }
    }

    // Optional: Specify the Invert Y flag
    if (desc.invert_y) |invert_y| {
        if (invert_y) {
            try argv.append("-inverty");
        }
    }

    // Specify the destination image folder path
    try argv.append("-o");
    try argv.append(desc.destination_path);

    // Specify the source image file path
    var source_path_buffer: [1024]u8 = undefined;
    const source_absolute_path = try std.fmt.bufPrint(&source_path_buffer, "{s}/../../../content/{s}", .{cwd_absolute, desc.source_path});
    try argv.append(source_absolute_path);

    var cmd = std.process.Child.init(@ptrCast(argv.items), std.heap.page_allocator);
    try cmd.spawn();

    // Write the .dep file
    {
        var file = try std.fs.cwd().createFile(desc.dep_path, .{});
        defer file.close();

        // Add the source image as input
        try file.writeAll("INPUT: ");
        try file.writeAll(source_absolute_path);
    }

    const term = try cmd.wait();
    std.debug.assert(term == .Exited);
}

fn generateMetadata(arena: std.mem.Allocator) !void {
    var content_dir = try std.fs.cwd().openDir("../../../content", .{.iterate = true, .no_follow = true});
    var walker = try content_dir.walk(arena);
    defer walker.deinit();

    const allowed_types = [_][]const u8{ ".png", ".tga", ".jpg" };
    var textures = std.ArrayList(std.fs.Dir.Walker.Entry).init(arena);
    defer textures.deinit();

    while (try walker.next()) |entry| {
        const ext = std.fs.path.extension(entry.basename);
        const is_texture = for (allowed_types) |allowed_type| {
            if (std.mem.eql(u8, ext, allowed_type)) {
                break true;
            }
        }else false;

        if (is_texture) {
            const path_length = entry.path.len;

            var metadata_path_buffer: [1024]u8 = undefined;
            const metadata_path = try std.fmt.bufPrint(&metadata_path_buffer, "../../../content/{s}.texture", .{entry.path[0..(path_length-4)]});
            var metadata = std.fs.cwd().createFile(metadata_path, .{.exclusive = true}) catch |e| {
                switch (e) {
                    error.PathAlreadyExists => {
                        continue;
                    },
                    else => return e,
                }
            };
            defer metadata.close();

            const format = inferrFormatFromFilename(entry.basename);

            _ = try metadata.write("version: 1\n");
            _ = try metadata.write("source: ");

            _ = try metadata.write(entry.path);
            _ = try metadata.write("\n");

            _ = try metadata.write("format: ");
            switch (format) {
                .BC1_UNORM => {
                    _ = try metadata.write("BC1_UNORM\n");
                },
                .BC1_UNORM_SRGB => {
                    _ = try metadata.write("BC1_UNORM_SRGB\n");
                    _ = try metadata.write("srgb: true\n");
                },
                .BC3_UNORM => {
                    _ = try metadata.write("BC3_UNORM\n");
                },
                .BC4_UNORM => {
                    _ = try metadata.write("BC4_UNORM\n");
                },
                .BC5_UNORM => {
                    _ = try metadata.write("BC5_UNORM\n");
                },
                .BC7_UNORM => {
                    _ = try metadata.write("BC7_UNORM\n");
                },
                .BC7_UNORM_SRGB => {
                    _ = try metadata.write("BC7_UNORM_SRGB\n");
                    _ = try metadata.write("srgb: true\n");
                },
            }
            _ = try metadata.write("\n");


            std.log.debug("Generated metadata for: {s}", .{entry.basename});
        }
    }
}

fn inferrFormatFromFilename(filename: []const u8) TextureFormat {
    const fallback_format = TextureFormat.BC1_UNORM_SRGB;

    if (filename.len <= 12) {
        return fallback_format;
    }

    var substring = filename[(filename.len - 10)..(filename.len - 4)];
    if (std.mem.eql(u8, "normal", substring)) {
        return .BC5_UNORM;
    }

    if (std.mem.eql(u8, "albedo", substring)) {
        return .BC1_UNORM_SRGB;
    }

    if (std.mem.eql(u8, "height", substring)) {
        return .BC4_UNORM;
    }

    substring = filename[(filename.len - 12)..(filename.len - 4)];
    if (std.mem.eql(u8, "emissive", substring)) {
        return .BC1_UNORM_SRGB;
    }

    substring = filename[(filename.len - 7)..(filename.len - 4)];
    if (std.mem.eql(u8, "arm", substring)) {
        return .BC1_UNORM;
    }

    return fallback_format;
}