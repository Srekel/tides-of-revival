const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .enable_ztracy = b.option(
            bool,
            "enable_ztracy",
            "Enable Tracy profile markers",
        ) orelse false,
        .enable_fibers = b.option(
            bool,
            "enable_fibers",
            "Enable Tracy fiber support",
        ) orelse false,
        .on_demand = b.option(
            bool,
            "on_demand",
            "Build tracy with TRACY_ON_DEMAND",
        ) orelse false,
        .callstack = b.option(
            u32,
            "callstack",
            "If > 0, Builds tracy with TRACY_USE_CALLSTACK and sets TRACY_CALLSTACK to the depth provided.",
        ) orelse 0,
        .shared = b.option(
            bool,
            "shared",
            "Build as shared library",
        ) orelse false,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }

    const options_module = options_step.createModule();

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("libs/tracy/tracy/TracyC.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("libs/tracy/tracy"));
    translate_c.defineCMacro("TRACY_ENABLE", "");
    translate_c.defineCMacro("TRACY_IMPORTS", "");
    if (options.callstack > 0) {
        translate_c.defineCMacro("TRACY_USE_CALLSTACK", "");
        var callstack_buffer: [64]u8 = undefined;
        const callstack = std.fmt.bufPrintIntToSlice(&callstack_buffer, @as(u32, options.callstack), 10, .lower, .{});
        translate_c.defineCMacro("TRACY_CALLSTACK", callstack);
    }

    const ztracy = b.addModule("root", .{
        .root_source_file = b.path("src/ztracy.zig"),
        .imports = &.{
            .{ .name = "ztracy_options", .module = options_module },
        },
    });
    ztracy.addImport("c", translate_c.createModule());

    const tracy = if (options.shared) blk: {
        const lib = b.addSharedLibrary(.{
            .name = "tracy",
            .target = target,
            .optimize = optimize,
        });
        lib.root_module.addCMacro("TRACY_EXPORTS", "");
        break :blk lib;
    } else b.addStaticLibrary(.{
        .name = "tracy",
        .target = target,
        .optimize = optimize,
    });

    tracy.addIncludePath(b.path("libs/tracy/tracy"));
    tracy.addCSourceFile(.{
        .file = b.path("libs/tracy/TracyClient.cpp"),
        .flags = &.{
            if (options.enable_ztracy) "-DTRACY_ENABLE" else "",
            if (options.enable_fibers) "-DTRACY_FIBERS" else "",
            "-fno-sanitize=undefined",
        },
    });
    tracy.root_module.addCMacro("_MT", "1");
    tracy.root_module.addCMacro("_DLL", "1");

    if (options.on_demand) tracy.root_module.addCMacro("TRACY_ON_DEMAND", "");

    tracy.linkLibC();
    if (target.result.abi != .msvc) {
        tracy.linkLibCpp();
    } else {
        tracy.root_module.addCMacro("fileno", "_fileno");
    }

    switch (target.result.os.tag) {
        .windows => {
            tracy.linkSystemLibrary("ws2_32");
            tracy.linkSystemLibrary("dbghelp");
        },
        .macos => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                tracy.addFrameworkPath(system_sdk.path("System/Library/Frameworks"));
            }
        },
        else => {},
    }

    b.installArtifact(tracy);

    const test_step = b.step("test", "Run ztracy tests");

    const tests = b.addTest(.{
        .name = "ztracy-tests",
        .root_source_file = b.path("src/ztracy.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibrary(tracy);
    b.installArtifact(tests);

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
