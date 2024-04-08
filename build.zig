const std = @import("std");
const Builder = std.build.Builder;

const zflecs = @import("external/zig-gamedev/libs/zflecs/build.zig");
const zglfw = @import("external/zig-gamedev/libs/zglfw/build.zig");
const zmath = @import("external/zig-gamedev/libs/zmath/build.zig");
const zmesh = @import("external/zig-gamedev/libs/zmesh/build.zig");
const znoise = @import("external/zig-gamedev/libs/znoise/build.zig");
const zphysics = @import("external/zig-gamedev/libs/zphysics/build.zig");
const zpix = @import("external/zig-gamedev/libs/zpix/build.zig");
const zpool = @import("external/zig-gamedev/libs/zpool/build.zig");
const zstbi = @import("external/zig-gamedev/libs/zstbi/build.zig");
const ztracy = @import("external/zig-gamedev/libs/ztracy/build.zig");
const zwin32 = @import("external/zig-gamedev/libs/zwin32/build.zig");
const zig_recastnavigation = @import("external/zig-recastnavigation/build.zig");
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
    if (abi != .msvc)
        exe.linkLibCpp();

    // Building and Linking Tides Renderer
    {
        const build_step = buildTheForgeRenderer(b);

        const tides_renderer_base_path = thisDir() ++ "/external/The-Forge/Examples_3/TidesRenderer";
        // TODO(gmodarelli): Check if OS is windows and if target is debug
        const tides_renderer_output_path = tides_renderer_base_path ++ "/PC Visual Studio 2019/x64/Debug";

        exe.addLibraryPath(.{ .path = tides_renderer_output_path });
        exe.linkSystemLibrary("TidesRenderer");
        exe.step.dependOn(build_step);

        // Install DLLs
        var install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/TidesRenderer.dll" }, "bin/TidesRenderer.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/TidesRenderer.pdb" }, "bin/TidesRenderer.pdb");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/WinPixEventRunTime.dll" }, "bin/WinPixEventRunTime.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/amd_ags_x64.dll" }, "bin/amd_ags_x64.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/dxcompiler.dll" }, "bin/dxcompiler.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/VkLayer_khronos_validation.dll" }, "bin/VkLayer_khronos_validation.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);

        // Install Configuration Files
        install_file = b.addInstallFile(.{ .path = tides_renderer_base_path ++ "/src/GPUCfg/gpu.cfg" }, "bin/GPUCfg/gpu.cfg");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_base_path ++ "/src/GPUCfg/gpu.data" }, "bin/GPUCfg/gpu.data");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/VkLayer_khronos_validation.json" }, "bin/VkLayer_khronos_validation.json");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
    }

    const zflecs_pkg = zflecs.package(b, target, optimize, .{});

    const zglfw_pkg = zglfw.package(b, target, optimize, .{});

    const zmath_pkg = zmath.package(b, target, optimize, .{
        .options = .{ .enable_cross_platform_determinism = false },
    });

    const zmesh_options = zmesh.Options{ .shape_use_32bit_indices = true };
    const zmesh_pkg = zmesh.package(b, target, optimize, .{ .options = zmesh_options });

    const znoise_pkg = znoise.package(b, target, optimize, .{});

    const zphysics_options = zphysics.Options{
        .use_double_precision = false,
        .enable_cross_platform_determinism = false,
    };
    const zphysics_pkg = zphysics.package(b, target, optimize, .{ .options = zphysics_options });

    const zpool_pkg = zpool.package(b, target, optimize, .{});

    const zstbi_pkg = zstbi.package(b, target, optimize, .{});

    const ztracy_enable = b.option(bool, "ztracy-enable", "Enable Tracy profiler") orelse false;
    const ztracy_options = ztracy.Options{ .enable_ztracy = ztracy_enable };
    const ztracy_pkg = ztracy.package(b, target, optimize, .{ .options = ztracy_options });

    const zwin32_pkg = zwin32.package(b, target, optimize, .{});
    const zpix_enable = b.option(bool, "zpix-enable", "Enable PIX for Windows profiler") orelse false;
    const zpix_pkg = zpix.package(b, target, optimize, .{
        .options = .{ .enable = zpix_enable },
        .deps = .{ .zwin32 = zwin32_pkg.zwin32 },
    });

    // Recast
    const zignav_pkg = zig_recastnavigation.package(b, target, optimize, .{});
    exe.root_module.addImport("zignav", zignav_pkg.zig_recastnavigation);
    zignav_pkg.link(exe);

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

    exe.root_module.addImport("zflecs", zflecs_pkg.zflecs);
    exe.root_module.addImport("zglfw", zglfw_pkg.zglfw);
    exe.root_module.addImport("zmath", zmath_pkg.zmath);
    exe.root_module.addImport("zmesh", zmesh_pkg.zmesh);
    exe.root_module.addImport("znoise", znoise_pkg.znoise);
    exe.root_module.addImport("zpool", zpool_pkg.zpool);
    exe.root_module.addImport("zstbi", zstbi_pkg.zstbi);
    exe.root_module.addImport("ztracy", ztracy_pkg.ztracy);

    zflecs_pkg.link(exe);
    zglfw_pkg.link(exe);
    zmesh_pkg.link(exe);
    znoise_pkg.link(exe);
    zphysics_pkg.link(exe);
    zpix_pkg.link(exe);
    zstbi_pkg.link(exe);
    ztracy_pkg.link(exe);
    zwin32_pkg.link(exe, .{ .d3d12 = true });
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
