const std = @import("std");
const Builder = std.build.Builder;
// const builtin = std.builtin.;
const builtin = @import("builtin");

const zforge = @import("external/The-Forge/build.zig");
// const wwise_zig = @import("wwise-zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "TidesOfRevival",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.option([]const u8, "build_date", "date of the build");
    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "build_date", "2023-11-25");

    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    exe.linkLibC();
    if (abi != .msvc) {
        exe.linkLibCpp();
    }

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;

    // ███╗   ███╗ ██████╗ ██████╗ ██╗   ██╗██╗     ███████╗███████╗
    // ████╗ ████║██╔═══██╗██╔══██╗██║   ██║██║     ██╔════╝██╔════╝
    // ██╔████╔██║██║   ██║██║  ██║██║   ██║██║     █████╗  ███████╗
    // ██║╚██╔╝██║██║   ██║██║  ██║██║   ██║██║     ██╔══╝  ╚════██║
    // ██║ ╚═╝ ██║╚██████╔╝██████╔╝╚██████╔╝███████╗███████╗███████║
    // ╚═╝     ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚══════╝

    // if (target.cpu.arch.isX86()) {
    // if (target.abi.isGnu() or target.abi.isMusl()) {
    if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
        exe.addLibraryPath(system_sdk.path("windows/lib/x86_64-windows-gnu"));
    }
    // }
    // }

    // websocket.zig
    exe.root_module.addImport("websocket", b.createModule(.{
        .root_source_file = b.path("external/websocket.zig/src/websocket.zig"),
        .imports = &.{},
    }));

    // zflecs
    const zflecs = b.dependency("zflecs", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(zflecs.artifact("flecs"));
    exe.root_module.addImport("zflecs", zflecs.module("root"));

    // zforge
    const zforge_pkg = zforge.package(b, target, optimize, .{});
    zforge_pkg.link(b, exe);

    // zigimg
    exe.root_module.addImport("zigimg", b.createModule(.{
        .root_source_file = b.path("external/zigimg/zigimg.zig"),
        .imports = &.{},
    }));

    // zig-args
    exe.root_module.addImport("args", b.createModule(.{
        .root_source_file = b.path("external/zig-args/args.zig"),
        .imports = &.{},
    }));

    // ZIG GAMEDEV
    // zglfw
    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    // zgui
    const zgui = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .shared = false,
        .with_implot = false,
        .backend = .glfw_dx12,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    // zmath
    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
        .enable_cross_platform_determinism = false,
    });
    exe.root_module.addImport("zmath", zmath.module("root"));

    // zmesh
    const zmesh = b.dependency("zmesh", .{
        .target = target,
        .optimize = optimize,
        .shape_use_32bit_indices = true,
    });
    exe.root_module.addImport("zmesh", zmesh.module("root"));
    exe.linkLibrary(zmesh.artifact("zmesh"));

    // znoise
    const znoise = b.dependency("znoise", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("znoise", znoise.module("root"));
    exe.linkLibrary(znoise.artifact("FastNoiseLite"));

    // zpix
    const zpix_enable = b.option(bool, "zpix-enable", "Enable PIX for Windows profiler") orelse false;
    const zpix = b.dependency("zpix", .{
        // .target = target,
        // .optimize = optimize,
        .path = @as([]const u8, "C:/Program Files/Microsoft PIX/2409.23/WinPixGpuCapturer.dll"),
        .enable = zpix_enable,
    });
    exe.root_module.addImport("zpix", zpix.module("root"));

    // zphysics
    const zphysics = b.dependency("zphysics", .{
        .target = target,
        .optimize = optimize,
        .use_double_precision = false,
        .enable_cross_platform_determinism = false,
    });
    exe.root_module.addImport("zphysics", zphysics.module("root"));
    exe.linkLibrary(zphysics.artifact("joltc"));

    // zpool
    const zpool = b.dependency("zpool", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zpool", zpool.module("root"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    // ztracy
    const ztracy_enable = b.option(bool, "ztracy-enable", "Enable Tracy profiler") orelse false;
    const ztracy = b.dependency("ztracy", .{
        .target = target,
        .optimize = optimize,
        .enable_ztracy = ztracy_enable,
        .enable_fibers = true,
    });
    exe.root_module.addImport("ztracy", ztracy.module("root"));
    exe.linkLibrary(ztracy.artifact("tracy"));

    // Recast
    // const zignav = b.dependency("zignav", .{});
    // exe.root_module.addImport("zignav", zignav.module("zignav"));
    // exe.linkLibrary(zignav.artifact("zignav_c_cpp"));

    // Im3d
    const im3d = b.dependency("im3d", .{});
    exe.root_module.addImport("im3d", im3d.module("im3d"));
    exe.linkLibrary(im3d.artifact("im3d_c_cpp"));

    // TODO: Asset cookify
    const install_fonts_step = b.addInstallDirectory(.{
        .source_dir = b.path("content/fonts"),
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/fonts",
    });
    exe.step.dependOn(&install_fonts_step.step);

    const install_systems_step = b.addInstallDirectory(.{
        .source_dir = b.path("content/systems"),
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/systems",
    });
    exe.step.dependOn(&install_systems_step.step);

    // zwindows
    const zwindows_dependency = b.dependency("zwindows", .{
        .zxaudio2_debug_layer = (builtin.mode == .Debug),
        .zd3d12_debug_layer = (builtin.mode == .Debug),
        .zd3d12_gbv = b.option(bool, "zd3d12_gbv", "Enable GPU-Based Validation") orelse false,
    });

    // Import the Windows API bindings
    exe.root_module.addImport("zwindows", zwindows_dependency.module("zwindows"));

    // Import the optional zd3d12 helper library
    exe.root_module.addImport("zd3d12", zwindows_dependency.module("zd3d12"));

    // Import the optional zxaudio2 helper library
    exe.root_module.addImport("zxaudio2", zwindows_dependency.module("zxaudio2"));

    // Install vendored binaries
    const zwindows = @import("zwindows");
    zwindows.install_xaudio2(&exe.step, zwindows_dependency, .bin);
    zwindows.install_d3d12(&exe.step, zwindows_dependency, .bin);
    zwindows.install_directml(&exe.step, zwindows_dependency, .bin);

    // WWise
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
