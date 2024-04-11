const std = @import("std");
const Builder = std.build.Builder;

const zforge = @import("external/The-Forge/build.zig");
// const wwise_zig = @import("wwise-zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "TidesOfRevival",
        .root_source_file = .{ .path = thisDir() ++ "/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    _ = b.option([]const u8, "build_date", "date of the build");
    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "build_date", "2023-11-25");

    exe.root_module.addImport("websocket", b.createModule(.{
        .root_source_file = .{ .path = thisDir() ++ "/external/websocket.zig/src/websocket.zig" },
        .imports = &.{},
    }));
    exe.root_module.addImport("zigimg", b.createModule(.{
        .root_source_file = .{ .path = thisDir() ++ "/external/zigimg/zigimg.zig" },
        .imports = &.{},
    }));
    exe.root_module.addImport("args", b.createModule(.{
        .root_source_file = .{ .path = thisDir() ++ "/external/zig-args/args.zig" },
        .imports = &.{},
    }));

    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    exe.linkLibC();
    if (abi != .msvc) {
        exe.linkLibCpp();
    }

    const zforge_pkg = zforge.package(b, target, optimize, .{});

    const zflecs = b.dependency("zflecs", .{});
    exe.linkLibrary(zflecs.artifact("flecs"));

    const zglfw = b.dependency("zglfw", .{});

    const zmath = b.dependency("zmath", .{
        .enable_cross_platform_determinism = false,
    });

    const zmesh = b.dependency("zmesh", .{
        .shape_use_32bit_indices = true,
    });

    const znoise = b.dependency("znoise", .{});

    const zphysics = b.dependency("zphysics", .{
        .use_double_precision = false,
        .enable_cross_platform_determinism = false,
    });

    const zpool = b.dependency("zpool", .{});

    const zstbi = b.dependency("zstbi", .{});

    const ztracy_enable = b.option(bool, "ztracy-enable", "Enable Tracy profiler") orelse false;
    _ = ztracy_enable; // autofix
    // const ztracy = b.dependency("ztracy", .{
    //     .enable_ztracy = ztracy_enable,
    //     .enable_fibers = true,
    // });

    const zwin32 = b.dependency("zwin32", .{});
    const zwin32_path = zwin32.path("").getPath(b);

    const zpix_enable = b.option(bool, "zpix-enable", "Enable PIX for Windows profiler") orelse false;
    const zpix = b.dependency("zpix", .{
        .enable = zpix_enable,
    });
    _ = zpix; // autofix

    // Recast
    // const zignav = b.dependency("zignav", .{});
    // exe.root_module.addImport("zignav", zignav.module("zignav"));
    // exe.linkLibrary(zignav.artifact("zignav_c_cpp"));

    const install_fonts_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/fonts" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/fonts",
    });
    exe.step.dependOn(&install_fonts_step.step);

    const install_systems_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/systems" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/systems",
    });
    exe.step.dependOn(&install_systems_step.step);

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;

    exe.root_module.addImport("zflecs", zflecs.module("root"));
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.root_module.addImport("zmath", zmath.module("root"));
    exe.root_module.addImport("zmesh", zmesh.module("root"));
    exe.root_module.addImport("znoise", znoise.module("root"));
    exe.root_module.addImport("zphysics", zphysics.module("root"));
    exe.root_module.addImport("zpool", zpool.module("root"));
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    // exe.root_module.addImport("ztracy", ztracy.module("root"));

    zforge_pkg.link(exe);
    exe.linkLibrary(zflecs.artifact("flecs"));
    exe.linkLibrary(zglfw.artifact("glfw"));
    exe.linkLibrary(zmesh.artifact("zmesh"));
    exe.linkLibrary(znoise.artifact("FastNoiseLite"));
    exe.linkLibrary(zphysics.artifact("joltc"));
    // exe.linkLibrary(zpix.artifact("pix"));
    exe.linkLibrary(zstbi.artifact("zstbi"));
    // exe.linkLibrary(ztracy.artifact("tracy"));

    @import("zwin32").install_xaudio2(&exe.step, .bin, zwin32_path) catch unreachable;
    @import("zwin32").install_d3d12(&exe.step, .bin, zwin32_path) catch unreachable;
    @import("zwin32").install_directml(&exe.step, .bin, zwin32_path) catch unreachable;
    @import("system_sdk").addLibraryPathsTo(exe);

    // const wwise_dependency = b.dependency("wwise-zig", .{
    //     .target = target,
    //     .optimize = optimize,
    //     .use_communication = true,
    //     .use_default_job_worker = true,
    //     .use_spatial_audio = false,
    //     .use_static_crt = true,
    //     .include_file_package_io_blocking = true,
    //     .configuration = .profile,
    //     .static_plugins = @as([]const []const u8, &.{
    //         // "AkToneSource",
    //         // "AkParametricEQFX",
    //         // "AkDelayFX",
    //         // "AkPeakLimiterFX",
    //         // "AkRoomVerbFX",
    //         // "AkStereoDelayFX",
    //         // "AkSynthOneSource",
    //         // "AkAudioInputSource",
    //         // "AkVorbisDecoder",
    //     }),
    // });

    // exe.root_module.addImport("wwise-zig", wwise_dependency.module("wwise-zig"));

    // const build_soundbanks_step = wwise_zig.addGenerateSoundBanksStep(
    //     b,
    //     "../tides-rpg-source-assets/tides-wwise/tides-wwise.wproj",
    //     .{
    //         .target = target,
    //     },
    // ) catch unreachable;
    // exe.step.dependOn(&build_soundbanks_step.step);

    // const wwise_id_module = wwise_zig.generateWwiseIDModule(
    //     b,
    //     "content/audio/wwise/Wwise_IDs.h",
    //     wwise_dependency.module("wwise-zig"),
    //     .{
    //         // .previous_step = &build_soundbanks_step.step,
    //     },
    // );

    // exe.root_module.addImport("wwise-ids", wwise_id_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn buildTheForgeRenderer(b: *std.Build) *std.Build.Step {
    const build_step = b.step(
        "the-forge-tides-renderer",
        "Build The-Forge renderer",
    );

    const solution_path = thisDir() ++ "/external/The-Forge/Examples_3/TidesRenderer/PC Visual Studio 2019/TidesRenderer.sln";
    const command = [2][]const u8{
        "./tools/external/msvc_BuildTools/MSBuild/Current/Bin/amd64/MSBuild",
        solution_path,
    };

    build_step.dependOn(&b.addSystemCommand(&command).step);
    return build_step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
